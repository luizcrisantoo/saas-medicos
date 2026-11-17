#!/usr/bin/env python3
"""F8: storage S3 com SSE-KMS e URL assinada curta, validacao de tipo e tamanho, auditoria do acesso (ADR-0010, R-04)."""
import os
import secrets
import sys
import urllib.parse

sys.path.insert(0, os.path.join(os.environ["ACC"], "lib"))
from aceite_http import req, resultado, sql, vaza_excecao  # noqa: E402

URL = os.environ["APP_URL"]
COOKIE = {"Cookie": "SESSAO=" + "a8" * 32}
E1, E2 = "e8000000-0000-0000-0005-000000000001", "e8000000-0000-0000-0005-000000000002"
X1, X2, X3, Y1 = (f"a8000000-0000-0000-000b-00000000000{i}" for i in (1, 2, 3, 4))
BUCKET, KMS = os.environ["SAAS_S3_BUCKET"], os.environ["SAAS_S3_KMS_KEY_ID"]
MAX_EXP = 300  # "poucos minutos" (ADR-0010): ate 5 minutos


def n_anexos():
    return int(sql("select count(*) from saas.anexo_encaminhamento") or -1)


def upload(enc, tipo, tam, sha=None):
    return req("POST", f"{URL}/api/encaminhamentos/{enc}/anexos", {"tipoMime": tipo, "tamanhoBytes": tam, "sha256": sha or secrets.token_hex(32)}, COOKIE)


def confere_url(u, chave, kms):
    p = urllib.parse.urlparse(u or "")
    q = {k.lower(): v for k, v in urllib.parse.parse_qsl(p.query)}
    erros = []
    if q.get("x-amz-algorithm") != "AWS4-HMAC-SHA256":
        erros.append("sem assinatura SigV4")
    if "/sa-east-1/s3/aws4_request" not in q.get("x-amz-credential", ""):
        erros.append("regiao/servico da credencial nao e sa-east-1/s3")
    try:
        exp = int(q.get("x-amz-expires", "0"))
    except ValueError:
        exp = 0
    if not 0 < exp <= MAX_EXP:
        erros.append(f"X-Amz-Expires={exp} (maximo {MAX_EXP})")
    if BUCKET not in (p.netloc + p.path):
        erros.append("bucket do ambiente ausente na URL")
    if chave and not urllib.parse.unquote(p.path).endswith("/" + chave):
        erros.append("objeto da URL nao e a chave_storage gerada pelo servidor")
    if kms:
        sh = q.get("x-amz-signedheaders", "")
        for h in ("x-amz-server-side-encryption", "x-amz-server-side-encryption-aws-kms-key-id"):
            if h not in sh.split(";"):
                erros.append(f"{h} fora dos cabecalhos assinados")
    return erros


# F8.1 upload valido
antes = n_anexos()
sha = secrets.token_hex(32)
r = upload(E1, "application/pdf", 1048576, sha)
j = r.json() if isinstance(r.json(), dict) else {}
aid = str(j.get("anexoId", ""))
linha = sql(f"select tipo_mime||'|'||tamanho_bytes||'|'||encode(sha256,'hex')||'|'||status_varredura||'|'||enviado_por_tipo||'|'||chave_storage "
            f"from saas.anexo_encaminhamento where id = '{aid}'") if len(aid) == 36 else ""
resultado("F8.1", r.status in (200, 201) and n_anexos() == antes + 1, f"upload de PDF de 1 MiB autorizado e registrado (status {r.status})")
partes = linha.split("|") if linha else []
resultado("F8.1", partes[:5] == ["application/pdf", "1048576", sha, "PENDENTE", "PROFISSIONAL"], f"metadados do anexo gravados como enviados, varredura PENDENTE ({partes[:5]})")
chave = partes[5] if len(partes) > 5 else None
erros = confere_url(j.get("url"), chave, True)
resultado("F8.1", not erros, f"URL de upload assinada, curta, no bucket do ambiente, na chave opaca e com SSE-KMS assinado ({erros[:3]})")
cab = {str(k).lower(): str(v) for k, v in (j.get("cabecalhos") or {}).items()}
resultado("F8.1", cab.get("x-amz-server-side-encryption") == "aws:kms" and cab.get("x-amz-server-side-encryption-aws-kms-key-id") == KMS,
          "resposta informa os cabecalhos SSE-KMS obrigatorios com a chave KMS configurada")

# F8.2 tipo invalido
for tipo in ("application/zip", "image/gif", "image/svg+xml", "text/html", "application/x-msdownload", "application/pdf; charset=binary"):
    a = n_anexos()
    r = upload(E1, tipo, 1000)
    resultado("F8.2", 400 <= r.status < 500 and n_anexos() == a and "x-amz-signature" not in r.texto().lower(), f"tipo {tipo}: recusado sem registro nem URL (status {r.status})")

r = upload(E1, "application/pdf", 1000)
resultado("F8.2", r.status in (200, 201), f"controle: application/pdf aceito (status {r.status})")

# F8.3 tamanho
for tam in (20971521, 0, -5):
    a = n_anexos()
    r = upload(E1, "image/jpeg", tam)
    resultado("F8.3", 400 <= r.status < 500 and n_anexos() == a, f"tamanho {tam}: recusado sem registro (status {r.status})")
for tipo, tam in (("image/png", 20971520), ("image/jpeg", 1)):
    r = upload(E1, tipo, tam)
    resultado("F8.3", r.status in (200, 201), f"controle: {tipo} com {tam} bytes aceito (status {r.status})")

# F8.4 encaminhamento de outro medico
a = n_anexos()
r = upload(E2, "application/pdf", 1000)
resultado("F8.4", r.status in (403, 404) and n_anexos() == a and not vaza_excecao(r), f"upload em encaminhamento alheio: 403/404 sem registro (status {r.status})")
r = req("POST", f"{URL}/api/encaminhamentos/{E1}/anexos", {"tipoMime": "application/pdf", "tamanhoBytes": 10, "sha256": secrets.token_hex(32)})
resultado("F8.4", r.status == 401, f"upload sem sessao: 401 (status {r.status})")
r = upload(E1, "application/pdf", 1000)
resultado("F8.4", r.status in (200, 201), f"controle: no proprio encaminhamento o upload e aceito (status {r.status})")


def aud(anexo):
    return int(sql(f"select count(*) from saas.evento_auditoria where recurso_id = '{anexo}'") or -1)


def download(anexo, cookie=True):
    return req("GET", f"{URL}/api/anexos/{anexo}/download", cab=COOKIE if cookie else {})


# F8.5 download de anexo LIMPO
a0 = aud(X1)
r = download(X1)
jd = r.json() if isinstance(r.json(), dict) else {}
chave1 = sql(f"select chave_storage from saas.anexo_encaminhamento where id = '{X1}'")
erros = confere_url(jd.get("url"), chave1, False)
resultado("F8.5", r.status == 200 and not erros, f"download de anexo LIMPO devolve URL assinada curta da chave certa (status {r.status}, {erros[:3]})")
# F8.7 auditoria: um evento por acesso concedido
resultado("F8.7", aud(X1) == a0 + 1, f"download concedido grava exatamente 1 EventoAuditoria do anexo ({a0} -> {aud(X1)})")
r = download(X1)
resultado("F8.7", aud(X1) == a0 + 2, "segundo download grava outro evento")

# F8.6 anexo nao liberado ou alheio
for nome, anexo in (("PENDENTE", X2), ("INFECTADO", X3), ("de outro encaminhamento", Y1)):
    r = download(anexo)
    resultado("F8.6", 400 <= r.status < 500 and "x-amz-signature" not in r.texto().lower() and not vaza_excecao(r), f"anexo {nome}: recusado sem URL (status {r.status})")
r = download(X1, cookie=False)
resultado("F8.6", r.status == 401 and "x-amz-signature" not in r.texto().lower(), f"download sem sessao: 401 (status {r.status})")
r = download(X1)
resultado("F8.6", r.status == 200 and "x-amz-signature" in r.texto().lower(), f"controle: o anexo LIMPO do proprio caso continua liberado (status {r.status})")

# F8.8 acesso sem registro nao acontece: com a auditoria indisponivel, nenhuma URL sai
sql("create trigger aceite_falha before insert on saas.evento_auditoria for each row execute function aceite.falha_auditoria()")
r = download(X1)
sql("drop trigger aceite_falha on saas.evento_auditoria")
resultado("F8.8", r.status >= 400 and "x-amz-signature" not in r.texto().lower(), f"auditoria falhando: download nao devolve URL (status {r.status})")
r = download(X1)
resultado("F8.8", r.status == 200 and "x-amz-signature" in r.texto().lower(), f"controle: com a auditoria de volta o download volta a funcionar (status {r.status})")

# F8.9 URL assinada nunca no log da aplicacao
logs = open(os.environ["APP_LOG"], errors="replace").read().lower()
resultado("F8.9", "x-amz-signature" in (str(j.get("url")) + str(jd.get("url"))).lower(), "controle: URLs assinadas foram emitidas durante o teste")
resultado("F8.9", "x-amz-signature=" not in logs, "nenhuma URL assinada no log da aplicacao")
