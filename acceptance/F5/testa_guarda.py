#!/usr/bin/env python3
"""Ataca a guarda de migracao do CI (gate R-07 e R-08) com migracoes maliciosas.

Uso: testa_guarda.py GUARDA RAIZ_REPO
Contrato (docs/fase2/spec.md, secao 3.5): GUARDA DIR_MIGRACOES ARQUIVO_APROVACOES sai 0 se toda
migracao do diretorio e limpa ou aprovada pelo sha256 exato do conteudo, e diferente de 0 caso contrario.
Imprime 'ok|falha <grupo> <caso>' por caso. Grupos: REPO, PROIBIDO, VARIANTE, LIMPO, APROVACAO.
"""
import hashlib
import os
import shutil
import subprocess
import sys
import tempfile

BASE = "SET ROLE saas_owner;\nCREATE TABLE saas.aceite_guarda(id uuid PRIMARY KEY);\n"
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
}
# casos que o Executor nao ve no criterio (anti reward hacking; ver acceptance/NOTAS-ANTI-HACK.md)
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
}
LIMPOS = {
    "tabela_rls_indice": BASE + "ALTER TABLE saas.aceite_guarda ENABLE ROW LEVEL SECURITY;\n"
                         "ALTER TABLE saas.aceite_guarda FORCE ROW LEVEL SECURITY;\n"
                         "CREATE INDEX aceite_guarda_idx ON saas.aceite_guarda (id);\nRESET ROLE;\n",
    "coluna_e_grant": "SET ROLE saas_owner;\nALTER TABLE saas.paciente ADD COLUMN aceite_obs text;\n"
                      "GRANT SELECT (aceite_obs) ON saas.paciente TO saas_app;\nRESET ROLE;\n",
}


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
                rc = roda(guarda, d, a)
                bom = (rc != 0 and not isinstance(rc, str)) if esperado_rejeita else rc == 0
                print(("ok" if bom else "falha") + f" {grupo} {nome} (saida {rc})")
    # aprovacao presa ao conteudo exato
    with tempfile.TemporaryDirectory() as tmp:
        d, a = prepara(raiz, tmp)
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
