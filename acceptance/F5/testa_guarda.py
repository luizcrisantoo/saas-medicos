#!/usr/bin/env python3
"""Ataca a guarda de migracao do CI (gate R-07 e R-08) com migracoes maliciosas.

Uso: testa_guarda.py GUARDA RAIZ_REPO
Contrato (docs/fase2/spec.md, secao 3.5): GUARDA DIR_MIGRACOES ARQUIVO_APROVACOES sai 0 se toda
migracao do diretorio e limpa ou aprovada pelo sha256 exato do conteudo, e diferente de 0 caso contrario.
Imprime 'ok|falha <grupo> <caso>' por caso. Grupos: REPO, PROIBIDO, VARIANTE, LIMPO, APROVACAO.

Classificacao de tabelas (secao 3.5, iteracao 9): a guarda le 'tabelas-sensiveis.txt' do proprio
diretorio (scripts/ci/, o mesmo que o CI tira da branch base). Os casos sinteticos rodam uma copia de
scripts/ci/ em diretorio temporario cuja lista ganha 'nao_sensivel aceite_ref' no fim (tabela criada
pelo proprio caso, com ENABLE e FORCE RLS); o repositorio nao e alterado. As tabelas de
SENSIVEIS_MINIMAS sao sensiveis pelo spec: GRANT nelas sem aprovacao e recusado qualquer que seja o
conteudo da lista do repositorio.
"""
import hashlib
import os
import shutil
import subprocess
import sys
import tempfile

# A tabela de apoio tem ENABLE e FORCE RLS: CREATE TABLE sem RLS passou a ser recusado (F5.2), e sem
# isso todo caso proibido seria recusado pelo motivo errado (iteracao 9).
BASE = ("SET ROLE saas_owner;\nCREATE TABLE saas.aceite_guarda(id uuid PRIMARY KEY);\n"
        "ALTER TABLE saas.aceite_guarda ENABLE ROW LEVEL SECURITY;\n"
        "ALTER TABLE saas.aceite_guarda FORCE ROW LEVEL SECURITY;\n")
# Tabela nao sensivel criada pelo proprio caso e classificada so na copia da lista (CLASSIFICA).
TABELA_REF = ("CREATE TABLE saas.aceite_ref(id uuid PRIMARY KEY, obs text);\n"
              "ALTER TABLE saas.aceite_ref ENABLE ROW LEVEL SECURITY;\n"
              "ALTER TABLE saas.aceite_ref FORCE ROW LEVEL SECURITY;\n")
CLASSIFICA = "nao_sensivel aceite_ref"
# Spec, secao 3.5: dado de paciente e clinico, auditoria, historico de status, link/codigo/sessao,
# desafio do encaminhador, consentimento, anexos, usuarios/papeis e flags.
SENSIVEIS_MINIMAS = (
    "paciente", "paciente_clinica", "encaminhamento", "vaga_encaminhamento", "agendamento",
    "contrarreferencia", "envio_notificacao", "evento_auditoria", "historico_status_encaminhamento",
    "link_paciente", "sessao", "desafio_encaminhador", "consentimento", "anexo_encaminhamento",
    "usuario", "usuario_clinica", "profissional_clinica", "flag_clinica",
)
PROIBIDOS = {
    "disable_trigger": "ALTER TABLE saas.historico_status_encaminhamento DISABLE TRIGGER historico_so_inclusao;",
    "no_force_rls": "ALTER TABLE saas.encaminhamento NO FORCE ROW LEVEL SECURITY;",
    "disable_rls": "ALTER TABLE saas.encaminhamento DISABLE ROW LEVEL SECURITY;",
    "drop_policy": "DROP POLICY encaminhamento_origem ON saas.encaminhamento;",
    "drop_trigger": "DROP TRIGGER encaminhamento_valida ON saas.encaminhamento;",
    "session_replication_role": "SET session_replication_role = replica;",
    "create_policy": "CREATE POLICY aberta ON saas.encaminhamento FOR SELECT USING (true);",
    "alter_policy": "ALTER POLICY encaminhamento_paciente ON saas.encaminhamento USING (true);",
    "create_trigger": "CREATE TRIGGER t BEFORE UPDATE ON saas.encaminhamento FOR EACH ROW EXECUTE FUNCTION saas.bloqueia_alteracao();",
    # iteracao 9 (Orquestrador, a partir do Revisor da F5; Red Team R-07/R-08)
    # o antigo caso limpo coluna_e_grant: GRANT de coluna em tabela sensivel agora exige aprovacao
    "grant_coluna_tabela_sensivel": "ALTER TABLE saas.paciente ADD COLUMN aceite_obs text;\n"
                                    "GRANT SELECT (aceite_obs) ON saas.paciente TO saas_app;",
    # tabela nova e sensivel ate ser classificada: o mesmo GRANT do caso limpo, sem a classificacao
    "grant_tabela_nova_nao_classificada": TABELA_REF + "GRANT SELECT (obs) ON saas.aceite_ref TO saas_app;",
    "drop_index_unico": "DROP INDEX saas.link_um_ativo_por_encaminhamento;",
    "drop_constraint": "ALTER TABLE saas.usuario_clinica DROP CONSTRAINT usuario_clinica_usuario_id_clinica_id_papel_key;",
    "create_table_sem_rls": "CREATE TABLE saas.aceite_sem_rls(id uuid PRIMARY KEY, clinica_id uuid);",
    "default_clinica_id": "ALTER TABLE saas.paciente_clinica ALTER COLUMN clinica_id SET DEFAULT '00000000-0000-0000-0000-000000000001';",
}
for _t in SENSIVEIS_MINIMAS:
    PROIBIDOS["grant_sensivel_" + _t] = f"GRANT SELECT ON saas.{_t} TO saas_app;"
SEM_CLASSIFICACAO = {"grant_tabela_nova_nao_classificada"}
# casos que o Executor nao ve no criterio (anti reward hacking; notas privadas do Orquestrador)
VARIANTES = {
    "minusculas": "alter table saas.historico_status_encaminhamento disable trigger all;",
    "quebra_de_linha": "ALTER TABLE saas.encaminhamento\n  DISABLE\n  TRIGGER\n  encaminhamento_valida;",
    "comentario_no_meio": "ALTER TABLE saas.encaminhamento NO /* revisado */ FORCE ROW LEVEL SECURITY;",
    "tab_e_espacos": "DROP\tPOLICY   IF EXISTS encaminhamento_origem ON saas.encaminhamento;",
    "aspas_e_only": 'ALTER TABLE ONLY "saas"."encaminhamento" DISABLE ROW LEVEL SECURITY;',
    "set_local_srr": "SET LOCAL session_replication_role TO replica;",
    "set_config_srr": "SELECT set_config('session_replication_role', 'replica', true);",
    "create_or_replace_trigger": "CREATE OR REPLACE TRIGGER t2 AFTER INSERT ON saas.paciente FOR EACH ROW EXECUTE FUNCTION saas.bloqueia_alteracao();",
    "constraint_trigger": "CREATE CONSTRAINT TRIGGER t3 AFTER INSERT ON saas.paciente FOR EACH ROW EXECUTE FUNCTION saas.bloqueia_alteracao();",
    "dentro_de_do": "DO $$ BEGIN EXECUTE 'ALTER TABLE saas.encaminhamento DISABLE TRIGGER encaminhamento_valida'; END $$;",
    "policy_comentada_e_real": "-- revisado pelo Red Team\nCREATE POLICY p2 ON saas.paciente FOR SELECT USING (true);",
    # iteracao 9
    "grant_minusculas_aspas": 'grant select, update on table "saas"."consentimento" to saas_app;',
    "grant_all_tables_in_schema": "GRANT SELECT ON ALL TABLES IN SCHEMA saas TO saas_app;",
    "grant_lista_mista": TABELA_REF + "GRANT SELECT ON saas.aceite_ref, saas.sessao TO saas_app;",
    "drop_index_concurrently": "drop index concurrently if exists saas.agendamento_um_ativo_por_encaminhamento;",
    "drop_constraint_if_exists": "ALTER TABLE ONLY saas.anexo_encaminhamento DROP CONSTRAINT IF EXISTS anexo_encaminhamento_chave_storage_key CASCADE;",
    "create_table_so_enable": "CREATE TABLE saas.aceite_meia(id uuid PRIMARY KEY);\n"
                              "ALTER TABLE saas.aceite_meia ENABLE ROW LEVEL SECURITY;",
    "create_table_rls_de_outra": "create table if not exists saas.aceite_outra(id uuid primary key);\n"
                                 "ALTER TABLE saas.aceite_guarda ENABLE ROW LEVEL SECURITY;\n"
                                 "ALTER TABLE saas.aceite_guarda FORCE ROW LEVEL SECURITY;",
    "drop_default_status": "ALTER TABLE ONLY saas.anexo_encaminhamento ALTER COLUMN status_varredura DROP DEFAULT;",
    "default_chave_storage": "alter table saas.anexo_encaminhamento alter chave_storage set default 'fixa';",
}
LIMPOS = {
    "tabela_rls_indice": BASE + "ALTER TABLE saas.aceite_guarda ENABLE ROW LEVEL SECURITY;\n"
                         "ALTER TABLE saas.aceite_guarda FORCE ROW LEVEL SECURITY;\n"
                         "CREATE INDEX aceite_guarda_idx ON saas.aceite_guarda (id);\nRESET ROLE;\n",
    # iteracao 9: o GRANT saiu de saas.paciente (sensivel, virou PROIBIDO grant_coluna_tabela_sensivel)
    # para saas.aceite_ref, criada aqui com ENABLE e FORCE RLS e classificada como nao sensivel; a
    # coluna nova em tabela sensivel continua tendo que passar.
    "coluna_e_grant": "SET ROLE saas_owner;\n" + TABELA_REF + "ALTER TABLE saas.paciente ADD COLUMN aceite_obs text;\n"
                      "GRANT SELECT (obs) ON saas.aceite_ref TO saas_app;\n"
                      "GRANT SELECT, INSERT ON saas.aceite_ref TO saas_app;\nRESET ROLE;\n",
    # REVOKE so reduz acesso: passa mesmo em tabela sensivel
    "revoke_sensivel": "SET ROLE saas_owner;\nREVOKE SELECT (telefone) ON saas.profissional FROM saas_app;\n"
                       "REVOKE UPDATE ON saas.paciente FROM saas_app;\nRESET ROLE;\n",
}


def guarda_copia(guarda, tmp, classifica=True):
    """Copia o diretorio da guarda (scripts/ci/) e acrescenta CLASSIFICA a lista da copia."""
    dst = os.path.join(tmp, "ci")
    shutil.copytree(os.path.dirname(os.path.abspath(guarda)), dst, symlinks=True,
                    ignore=shutil.ignore_patterns("__pycache__"))
    if classifica:
        with open(os.path.join(dst, "tabelas-sensiveis.txt"), "a") as f:
            f.write("\n" + CLASSIFICA + "\n")
    return os.path.join(dst, os.path.basename(guarda))


def roda(guarda, d, aprov):
    try:
        r = subprocess.run([guarda, d, aprov], capture_output=True, text=True, timeout=60)
        return r.returncode
    except Exception as e:  # noqa: BLE001
        return f"erro: {e}"


def prepara(raiz, tmp):
    mig = os.path.join(raiz, "src/main/resources/db/migration")
    aprov = os.path.join(raiz, "src/main/resources/db/aprovacoes.sha256")
    d = os.path.join(tmp, "migration")
    shutil.copytree(mig, d)
    a = os.path.join(tmp, "aprovacoes.sha256")
    shutil.copy(aprov, a) if os.path.exists(aprov) else open(a, "w").close()
    return d, a


def proximo_nome(d, desc):
    vs = []
    for f in os.listdir(d):
        if f.startswith("V") and "__" in f:
            try:
                vs.append(int(f[1:].split("__")[0].split("_")[0].split(".")[0]))
            except ValueError:
                pass
    return f"V{max(vs + [0]) + 900}__{desc}.sql"


def main(guarda, raiz):
    if not (os.path.isfile(guarda) and os.access(guarda, os.X_OK)):
        print(f"falha REPO guarda ausente ou nao executavel: {guarda}")
        return
    mig = os.path.join(raiz, "src/main/resources/db/migration")
    if not os.path.isdir(mig):
        print("falha REPO sem db/migration")
        return
    with tempfile.TemporaryDirectory() as tmp:
        d, a = prepara(raiz, tmp)
        rc = roda(guarda, d, a)
        print(("ok" if rc == 0 else "falha") + f" REPO migracoes do repositorio com as aprovacoes dele (saida {rc})")
    for grupo, casos, esperado_rejeita in (("PROIBIDO", PROIBIDOS, True), ("VARIANTE", VARIANTES, True), ("LIMPO", LIMPOS, False)):
        for nome, corpo in casos.items():
            with tempfile.TemporaryDirectory() as tmp:
                d, a = prepara(raiz, tmp)
                texto = corpo if grupo == "LIMPO" else BASE + corpo + "\nRESET ROLE;\n"
                open(os.path.join(d, proximo_nome(d, "aceite_" + nome)), "w").write(texto)
                rc = roda(guarda_copia(guarda, tmp, nome not in SEM_CLASSIFICACAO), d, a)
                bom = (rc != 0 and not isinstance(rc, str)) if esperado_rejeita else rc == 0
                print(("ok" if bom else "falha") + f" {grupo} {nome} (saida {rc})")
    # aprovacao presa ao conteudo exato
    with tempfile.TemporaryDirectory() as tmp:
        d, a = prepara(raiz, tmp)
        guarda = guarda_copia(guarda, tmp)
        nome = proximo_nome(d, "aceite_aprovada")
        texto = BASE + PROIBIDOS["create_policy"] + "\nRESET ROLE;\n"
        p = os.path.join(d, nome)
        open(p, "w").write(texto)
        h = hashlib.sha256(texto.encode()).hexdigest()
        with open(a, "a") as f:
            f.write(f"\n{h}  {nome}\n")
        rc1 = roda(guarda, d, a)
        print(("ok" if rc1 == 0 else "falha") + f" APROVACAO migracao com o sha256 aprovado passa (saida {rc1})")
        open(p, "w").write(texto.replace("USING (true)", "USING (true OR true)"))
        rc2 = roda(guarda, d, a)
        print(("ok" if rc2 != 0 else "falha") + f" APROVACAO conteudo alterado depois da aprovacao e recusado (saida {rc2})")
        outro = proximo_nome(d, "aceite_outra")
        os.rename(p, os.path.join(d, outro))
        open(os.path.join(d, outro), "w").write(texto)
        rc3 = roda(guarda, d, a)
        print(("ok" if rc3 != 0 else "falha") + f" APROVACAO aprovacao de outro arquivo nao vale para este nome (saida {rc3})")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
