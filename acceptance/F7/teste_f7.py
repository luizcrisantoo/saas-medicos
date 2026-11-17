#!/usr/bin/env python3
"""F7: contexto de sessao por transacao, pool seguro, isolamento entre clinicas e I-20 (token nunca no texto do SQL)."""
import os
import random
import re
import sys
import threading

sys.path.insert(0, os.path.join(os.environ["ACC"], "lib"))
from aceite_http import req, resultado, sql  # noqa: E402

URL = os.environ["APP_URL"]
CA, CB = "a7000000-0000-0000-0000-000000000001", "b7000000-0000-0000-0000-000000000001"
TOK = {"admA": "a7" * 32, "recA": "b7" * 32, "admB": "c7" * 32}
IDS_A = {f"a7000000-0000-0000-000a-00000000000{i}" for i in (1, 2, 3)}
IDS_B = {f"b7000000-0000-0000-000a-00000000000{i}" for i in (1, 2)}


def aud(tok=None, clinica=None, papel=None):
    cab = {}
    if tok:
        cab["Cookie"] = f"SESSAO={tok}"
    if clinica:
        cab["X-Clinica-Id"] = clinica
    if papel:
        cab["X-Papel"] = papel
    r = req("GET", URL + "/api/auditoria", cab=cab)
    ids = set()
    if r.status == 200 and isinstance(r.json(), list):
        ids = {str(x.get("id")) for x in r.json() if isinstance(x, dict)}
    return r.status, ids


def ve_a(st, ids):
    return st == 200 and IDS_A <= ids and not (ids & IDS_B)


def ve_b(st, ids):
    return st == 200 and IDS_B <= ids and not (ids & IDS_A)


def nada(st, ids):
    return st in (401, 403) or (st == 200 and not (ids & (IDS_A | IDS_B)))


st, ids = aud(TOK["admA"], CA, "ADMIN")
resultado("F7.1", ve_a(st, ids), f"ADMIN da clinica A ve a auditoria de A e nada de B (status {st}, {len(ids & IDS_A)}/3 de A, {len(ids & IDS_B)} de B)")
st, ids = aud(TOK["admB"], CB, "ADMIN")
resultado("F7.1", ve_b(st, ids), f"ADMIN da clinica B ve a auditoria de B e nada de A (status {st})")
for nome, args in (("RECEPCAO de A pedindo como RECEPCAO", (TOK["recA"], CA, "RECEPCAO")),
                   ("RECEPCAO de A declarando papel ADMIN", (TOK["recA"], CA, "ADMIN")),
                   ("ADMIN de A declarando a clinica B", (TOK["admA"], CB, "ADMIN")),
                   ("ADMIN de A sem clinica declarada", (TOK["admA"], None, None)),
                   ("sem sessao", (None, CA, "ADMIN"))):
    st, ids = aud(*args)
    resultado("F7.2", nada(st, ids), f"{nome}: 401/403 ou lista sem auditoria das clinicas (status {st})")
st, ids = aud(TOK["admA"], CA, "ADMIN")
resultado("F7.2", ve_a(st, ids), f"controle: a mesma sessao de ADMIN com a clinica certa continua vendo (status {st})")

# F7.3 pool de 1 conexao: sequencia aleatoria e concorrente nunca mistura contexto
roteiro = [("A", (TOK["admA"], CA, "ADMIN"), ve_a), ("B", (TOK["admB"], CB, "ADMIN"), ve_b),
           ("rec", (TOK["recA"], CA, "ADMIN"), nada), ("anon", (None, CA, "ADMIN"), nada),
           ("lixo", ("ff" * 32, CB, "ADMIN"), nada)]
random.seed(20261117)
seq = [random.choice(roteiro) for _ in range(40)]
erros = []
for nome, args, cond in seq:
    st, ids = aud(*args)
    if not cond(st, ids):
        erros.append(f"{nome}:{st}")
resultado("F7.3", not erros, f"40 requisicoes alternadas (A, B, papel falso, sem sessao, sessao inexistente) com pool de 1 conexao: {len(erros)} inconsistentes {erros[:4]}")
erros_c = []


def trabalho(lista):
    for nome, args, cond in lista:
        st, ids = aud(*args)
        if not cond(st, ids):
            erros_c.append(f"{nome}:{st}")


ts = [threading.Thread(target=trabalho, args=([random.choice(roteiro) for _ in range(15)],)) for _ in range(4)]
[t.start() for t in ts]
[t.join() for t in ts]
resultado("F7.3", not erros_c, f"4 clientes concorrentes, 60 requisicoes: {len(erros_c)} inconsistentes {erros_c[:4]}")

# F7.4 I-20: token nunca no texto do SQL (log do servidor com log_statement=all) nem em pg_stat_statements
pg = open(os.environ["PGLOG"], errors="replace").readlines()[int(os.environ["APP_L0"]):]
resultado("F7.4", any(re.search(r"\] saas_app@", l) for l in pg), "controle: a aplicacao consultou o banco como saas_app durante o teste")
vaz = [n for n, t in TOK.items() if any(t in l for l in pg)]
resultado("F7.4", not vaz, f"nenhum token de sessao no log do PostgreSQL ({vaz})")
q = sql("select string_agg(query, E'\\n') from public.pg_stat_statements")
vaz2 = [n for n, t in TOK.items() if t in (q or "")]
resultado("F7.4", not vaz2 and q != "", f"nenhum token de sessao em pg_stat_statements ({vaz2})")
app_l = [l for l in pg if re.search(r"\] saas_app@", l)]
lit = [l.strip()[:120] for l in app_l if re.search(r"set_config\(\s*'app\.\w+'\s*,\s*'", l, re.I) or re.search(r"\bset\s+(local\s+|session\s+)?app\.\w+", l, re.I)
       or re.search(r"set_config\([^)]*,\s*false\s*\)", l, re.I)]
usa = [l for l in app_l if "set_config" in l.lower()]
resultado("F7.5", bool(usa) and not lit, f"saas_app grava o contexto com set_config parametrizado e local a transacao ({len(usa)} usos, {len(lit)} literais ou de sessao: {lit[:1]})")
