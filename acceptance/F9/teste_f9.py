#!/usr/bin/env python3
"""F9: base LGPD. Consentimento conceder/revogar pela API (paciente, sessao por caso) e efeito na visibilidade da clinica destino."""
import os
import subprocess
import sys

sys.path.insert(0, os.path.join(os.environ["ACC"], "lib"))
from aceite_http import req, resultado, sql, vaza_excecao  # noqa: E402

URL = os.environ["APP_URL"]
PAC = {"Cookie": "SESSAO=" + "a9" * 32}
OUTRA = {"Cookie": "SESSAO=" + "b9" * 32}
REC = {"Cookie": "SESSAO=" + "c9" * 32, "X-Clinica-Id": "b9000000-0000-0000-0000-000000000001", "X-Papel": "RECEPCAO"}
E, E2, E3 = (f"e9000000-0000-0000-0005-00000000000{i}" for i in (1, 2, 3))
CB = "b9000000-0000-0000-0000-000000000001"
PA = "c9000000-0000-0000-0003-000000000001"
PB = "c9000000-0000-0000-0003-000000000002"
C_B = "f9000000-0000-0000-000c-000000000003"


def n_cons():
    return int(sql("select count(*) from saas.consentimento") or -1)


def recepcao_ve_caso():
    """Como a recepcao destino ve o encaminhamento E pela RLS (papel saas_app, sessao de equipe)."""
    script = ("begin;\nselect set_config('app.sessao', $1, true), set_config('app.clinica_id', $2, true), set_config('app.papel', $3, true) "
              f"\\bind '{'c9' * 32}' '{CB}' 'RECEPCAO' \\g\nselect count(*) from saas.encaminhamento where id = '{E}';\ncommit;\n")
    r = subprocess.run(["psql", "-X", "-q", "-At", "-h", os.environ["PGDIR"], "-p", os.environ["PGPORTA"], "-U", "saas_app", "-d", "app"],
                       input=script, capture_output=True, text=True)
    linhas = [l for l in r.stdout.splitlines() if l.strip().isdigit()]
    return linhas[-1] if linhas else "erro"


# F9.1 texto versionado do consentimento
r = req("GET", URL + "/api/termos/consentimento/COMPARTILHAR_CASO", cab=PAC)
t = r.json() if isinstance(r.json(), dict) else {}
versao, texto = str(t.get("versao") or ""), str(t.get("texto") or "")
resultado("F9.1", r.status == 200 and t.get("finalidade") == "COMPARTILHAR_CASO" and versao and len(texto) >= 40,
          f"texto do consentimento COMPARTILHAR_CASO servido com versao (status {r.status})")

# F9.2 conceder
a = n_cons()
resultado("F9.6", recepcao_ve_caso() == "0", "controle: sem consentimento a clinica destino nao ve o caso")
r = req("POST", URL + "/api/consentimentos", {"finalidade": "COMPARTILHAR_CASO", "encaminhamentoId": E, "clinicaId": CB, "versao": versao}, PAC)
cid = str((r.json() or {}).get("id", "")) if isinstance(r.json(), dict) else ""
row = sql(f"select paciente_id||'|'||finalidade||'|'||encaminhamento_id||'|'||clinica_id||'|'||versao_texto||'|'||canal||'|'||(revogado_em is null)||'|'||(texto_aceito = $t${texto}$t$) "
          f"from saas.consentimento where id = '{cid}'") if len(cid) == 36 else ""
resultado("F9.2", r.status in (200, 201) and n_cons() == a + 1, f"paciente concede COMPARTILHAR_CASO pela API (status {r.status})")
p = row.split("|") if row else []
resultado("F9.2", p[:5] == [PA, "COMPARTILHAR_CASO", E, CB, versao] and len(p) == 8 and p[5] in ("SITE", "WHATSAPP") and p[6] == "true" and p[7] == "true",
          f"registro com paciente da sessao, caso, clinica destino, versao e o texto exato servido ({p[:6]})")
resultado("F9.6", recepcao_ve_caso() == "1", "com consentimento ativo a clinica destino ve o caso")

# F9.3 recusas
for nome, corpo, cab in (
        ("versao inexistente", {"finalidade": "COMPARTILHAR_CASO", "encaminhamentoId": E, "clinicaId": CB, "versao": "versao-que-nao-existe"}, PAC),
        ("outro caso da mesma paciente (fora do link da sessao)", {"finalidade": "COMPARTILHAR_CASO", "encaminhamentoId": E2, "clinicaId": CB, "versao": versao}, PAC),
        ("caso de outra paciente", {"finalidade": "COMPARTILHAR_CASO", "encaminhamentoId": E3, "clinicaId": CB, "versao": versao}, PAC),
        ("recepcao tentando conceder pelo paciente", {"finalidade": "COMPARTILHAR_CASO", "encaminhamentoId": E, "clinicaId": CB, "versao": versao}, REC),
        ("sem sessao", {"finalidade": "COMPARTILHAR_CASO", "encaminhamentoId": E, "clinicaId": CB, "versao": versao}, {})):
    a = n_cons()
    r = req("POST", URL + "/api/consentimentos", corpo, cab)
    resultado("F9.3", 400 <= r.status < 500 and n_cons() == a and not vaza_excecao(r), f"{nome}: recusado sem registro (status {r.status})")
a = n_cons()
r = req("POST", URL + "/api/consentimentos", {"finalidade": "COMPARTILHAR_CASO", "encaminhamentoId": E, "clinicaId": CB, "versao": versao,
                                               "pacienteId": PB, "textoAceito": "texto forjado pelo cliente", "canal": "RECEPCAO"}, PAC)
forjado = sql("select count(*) from saas.consentimento where texto_aceito = 'texto forjado pelo cliente' or (paciente_id = '%s' and versao_texto <> 'semente') or canal = 'RECEPCAO'" % PB)
resultado("F9.3", forjado == "0", f"campos forjados no corpo (paciente, texto, canal) nunca sao gravados (status {r.status})")

resultado("F9.3", len(cid) == 36, "controle: o pedido valido da mesma paciente foi aceito")

# F9.4 listar
r = req("GET", URL + "/api/consentimentos", cab=PAC)
ids = {str(x.get("id")) for x in (r.json() or []) if isinstance(x, dict)} if isinstance(r.json(), list) else set()
resultado("F9.4", r.status == 200 and cid in ids and C_B not in ids, f"paciente lista os proprios consentimentos do caso, sem os de outra pessoa (status {r.status})")

# F9.5 revogar
r = req("DELETE", f"{URL}/api/consentimentos/{cid}", cab=PAC)
rev1 = sql(f"select revogado_em from saas.consentimento where id = '{cid}'") if cid else ""
resultado("F9.5", r.status in (200, 204) and rev1 != "", f"paciente revoga pela API e o registro ganha revogado_em (status {r.status})")
r = req("DELETE", f"{URL}/api/consentimentos/{cid}", cab=PAC)
rev2 = sql(f"select revogado_em from saas.consentimento where id = '{cid}'") if cid else "x"
resultado("F9.5", r.status in (404, 409, 410) and rev2 == rev1, f"revogar de novo: 404/409/410 e data original mantida (status {r.status})")
r = req("DELETE", f"{URL}/api/consentimentos/{C_B}", cab=PAC)
resultado("F9.5", r.status in (403, 404) and sql(f"select revogado_em is null from saas.consentimento where id = '{C_B}'") == "t",
          f"revogar consentimento de outra pessoa: 403/404 e nada muda (status {r.status})")
r = req("DELETE", f"{URL}/api/consentimentos/{C_B}", cab=OUTRA)
resultado("F9.5", r.status in (200, 204), f"controle: a titular revoga o proprio consentimento (status {r.status})")
resultado("F9.6", recepcao_ve_caso() == "0", "depois da revogacao a clinica destino deixa de ver o caso")
