#!/usr/bin/env python3
"""F6: autenticacao Cognito como resource server + sessao de equipe no banco (ADR-0006, 0007, 0023; E-10 sem MFA)."""
import os
import re
import secrets
import sys

sys.path.insert(0, os.path.join(os.environ["ACC"], "lib"))
from aceite_http import Chave, claims_cognito, jwt, req, resultado, sha256hex, sql, vaza_excecao  # noqa: E402

URL = os.environ["APP_URL"]
ISS = os.environ["AUTH_ISSUER"]
CLI = os.environ["AUTH_CLIENTES"].split(",")
D = os.environ["JWKS_DIR"]
k1 = Chave.carrega("aceite-k1", os.path.join(D, "k1.pem"))
k2 = Chave.carrega("aceite-k2", os.path.join(D, "k2.pem"))
USADOS = []


def n_sessoes(sub):
    v = sql(f"select count(*) from saas.sessao s join saas.usuario u on u.id = s.usuario_id where u.sub_oidc = '{sub}'")
    return int(v or -1)


def abre(tok):
    USADOS.append(tok)
    return req("POST", URL + "/api/sessao/equipe", cab={"Authorization": "Bearer " + tok})


def cookie_sessao(resp):
    for c in resp.cookies():
        m = re.match(r"\s*SESSAO=([^;]*)", c)
        if m:
            return m.group(1), c
    return None, None


# F6.2 token valido
antes = n_sessoes("f6-sub-recepcao")
r = abre(jwt(k1, claims_cognito("f6-sub-recepcao", ISS, CLI[0])))
valor, bruto = cookie_sessao(r)
depois = n_sessoes("f6-sub-recepcao")
resultado("F6.2", r.status in (200, 201, 204), f"token valido abre sessao (status {r.status})")
resultado("F6.2", depois == antes + 1, f"uma linha nova em saas.sessao para o usuario ({antes} -> {depois})")
ok_hash = bool(valor) and bool(re.fullmatch(r"[0-9a-f]{64}", valor or "")) and \
    sql(f"select count(*) from saas.sessao where token_hash = decode('{sha256hex(valor)}','hex') and encerrada_em is null") == "1"
resultado("F6.2", ok_hash, "cookie SESSAO carrega o token cuja sha256 esta em saas.sessao (ADR-0023)")
attrs = (bruto or "").lower()
resultado("F6.2", all(a in attrs for a in ("httponly", "secure", "samesite=")) and "path=/" in attrs,
          "cookie com HttpOnly, Secure, SameSite e Path=/")
r2 = req("GET", URL + "/api/sessao", cab={"Cookie": f"SESSAO={valor}"} if valor else {})
resultado("F6.2", r2.status == 200 and (r2.json() or {}).get("tipo") == "EQUIPE", f"GET /api/sessao com o cookie: 200 e tipo EQUIPE (status {r2.status})")
r3 = abre(jwt(k1, claims_cognito("f6-sub-recepcao-2", ISS, CLI[1])))
resultado("F6.2", r3.status in (200, 201, 204), f"segundo client_id permitido tambem abre sessao (status {r3.status})")

# F6.3 tokens invalidos: 401 (403 aceito para usuario inexistente ou inativo), nenhuma sessao nova, sem detalhe interno
sub = "f6-sub-recepcao"
base = claims_cognito(sub, ISS, CLI[0])
casos = {
    "assinatura de outra chave com kid publicado": jwt(k2, base, kid="aceite-k1"),
    "kid desconhecido": jwt(k2, base),
    "iss de outro user pool": jwt(k1, claims_cognito(sub, "https://cognito-idp.sa-east-1.amazonaws.com/sa-east-1_Outro", CLI[0])),
    "iss com sufixo": jwt(k1, claims_cognito(sub, ISS + "x", CLI[0])),
    "client_id nao permitido": jwt(k1, claims_cognito(sub, ISS, "cliente-intruso")),
    "expirado": jwt(k1, claims_cognito(sub, ISS, CLI[0], exp_em=-600)),
    "token_use=id": jwt(k1, claims_cognito(sub, ISS, CLI[0], token_use="id")),
    "alg none": jwt(k1, base, alg="none"),
    "HS256 com a chave publica como segredo": jwt(k1, base, alg="HS256", segredo_hs=k1.pem_publico()),
    "malformado": "abc.def",
    "access token sem client_id (so aud)": jwt(k1, {k: v for k, v in claims_cognito(sub, ISS, CLI[0], aud=CLI[0]).items() if k != "client_id"}),
}
for nome, tok in casos.items():
    a = n_sessoes(sub)
    r = abre(tok)
    resultado("F6.3", r.status == 401 and n_sessoes(sub) == a and not vaza_excecao(r), f"{nome}: 401 sem sessao nova (status {r.status})")
for nome, s in (("usuario inexistente", "f6-sub-nao-existe"), ("usuario inativo", "f6-sub-inativo")):
    a = int(sql("select count(*) from saas.sessao") or -1)
    r = abre(jwt(k1, claims_cognito(s, ISS, CLI[0])))
    resultado("F6.3", r.status in (401, 403) and int(sql("select count(*) from saas.sessao") or -1) == a and not vaza_excecao(r),
              f"{nome}: recusado sem sessao nova (status {r.status})")
r = req("POST", URL + "/api/sessao/equipe")
resultado("F6.3", r.status == 401, f"sem Authorization: 401 (status {r.status})")
r = abre(jwt(k1, claims_cognito(sub, ISS, CLI[0])))
resultado("F6.3", r.status in (200, 201, 204), f"controle: o mesmo usuario com token valido abre sessao (status {r.status})")

# F6.4 cookie invalido
for nome, c in (("cookie nao hexadecimal", "zz-nao-e-hex"), ("cookie hexadecimal desconhecido", secrets.token_hex(32)), ("sem cookie", None)):
    r = req("GET", URL + "/api/sessao", cab={"Cookie": f"SESSAO={c}"} if c else {})
    resultado("F6.4", r.status == 401 and not vaza_excecao(r), f"{nome}: 401 sem detalhe interno (status {r.status})")

r = req("GET", URL + "/api/sessao", cab={"Cookie": f"SESSAO={valor}"} if valor else {})
resultado("F6.4", r.status == 200, f"controle: cookie valido continua aceito (status {r.status})")

# F6.5 logout
r = req("DELETE", URL + "/api/sessao", cab={"Cookie": f"SESSAO={valor}"} if valor else {})
enc = sql(f"select count(*) from saas.sessao where token_hash = decode('{sha256hex(valor)}','hex') and encerrada_em is not null") if valor else "0"
resultado("F6.5", r.status in (200, 204) and enc == "1", f"DELETE /api/sessao encerra a sessao no banco (status {r.status}, encerrada={enc})")
r = req("GET", URL + "/api/sessao", cab={"Cookie": f"SESSAO={valor}"} if valor else {})
resultado("F6.5", r.status == 401, f"cookie de sessao encerrada: 401 (status {r.status})")

# F6.6 nenhum token nem cookie nos logs da aplicacao e do PostgreSQL (ADR-0026, itens 3 e 5)
logs = open(os.environ["APP_LOG"], errors="replace").read()
pg = "".join(open(os.environ["PGLOG"], errors="replace").readlines()[int(os.environ["APP_L0"]):])
segredos = [t for t in USADOS if len(t) > 20] + ([valor] if valor else [])
vaz_app = [s[:12] for s in segredos if s in logs or s.split(".")[-1][:40] in logs and len(s.split(".")[-1]) >= 40]
vaz_pg = [s[:12] for s in segredos if s in pg]
resultado("F6.6", bool(valor), "controle: houve sessao aberta e cookie emitido durante o teste")
resultado("F6.6", not vaz_app, f"log da aplicacao sem JWT nem cookie ({len(vaz_app)} vazamentos)")
resultado("F6.6", not vaz_pg, f"log do PostgreSQL sem JWT nem cookie ({len(vaz_pg)} vazamentos)")

# F6.7 sessao aberta pela credencial saas_auth
resultado("F6.7", "connection authorized: user=saas_auth" in pg, "a sessao de equipe e aberta por conexao saas_auth (credencial propria, ADR-0024)")
resultado("F6.7", "connection authorized: user=saas_app" in pg, "consultas da web por conexao saas_app")
