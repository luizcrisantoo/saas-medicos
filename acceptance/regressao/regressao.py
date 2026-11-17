#!/usr/bin/env python3
"""Normaliza e compara a saida das baterias de regressao impressas (Red Team).

Uso:
  regressao.py normaliza ENTRADA SAIDA
  regressao.py tabela SONDAS NEUTRAS RESULTADO FUNCOES_V2
    Baterias com tabela de resultado: toda sonda do golden (SONDAS, gerado contra o modelo-v2) tem
    que estar presente e ok, salvo as NEUTRAS. Sonda nova so falha se nao for a linha da matriz
    P-funcao de uma funcao que nao existe no modelo-v2, ou a linha da matriz de uma tabela nova
    (TABELAS_NOVAS: tabelas do banco que o modelo-v2 nao tem); objetos novos seguem as regras gerais de F2.6.
  regressao.py compara GOLDEN OBTIDO NEUTROS
    NEUTROS = lista separada por virgula de ids de bloco (ex.: R2N1a,R2N3) cuja saida
    depende de um gate da Fase 2: o bloco inteiro fica fora da comparacao (o gate e
    conferido pelas sondas novas de F3/F4). Fora desses blocos a saida normalizada tem
    que ser identica a da bateria executada contra docs/arquitetura/modelo-v2.sql.
"""
import re
import sys

UUID = re.compile(r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}")
TS = re.compile(r"\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}:\d{2}(\.\d+)?([+-]\d{2}(:?\d{2})?|Z)?")
HEX = re.compile(r"\b[0-9a-f]{16,}\b")
BYTEA = re.compile(r"\\x[0-9a-f]+")
PSQLPOS = re.compile(r"psql:[^ ]*?:\d+: ")
PID = re.compile(r"\[\d+\]")
TMP = re.compile(r"/tmp/[^ :\"']+")
CABEC = re.compile(r"^(?:=+ )?((?:R2N|RT|N)\d+[a-z]?)[\. ]")


def normaliza_linha(s: str) -> str:
    s = PSQLPOS.sub("psql: ", s)
    s = UUID.sub("<uuid>", s)
    s = TS.sub("<ts>", s)
    s = BYTEA.sub("<bytea>", s)
    s = HEX.sub("<hex>", s)
    s = PID.sub("[pid]", s)
    s = TMP.sub("<tmp>", s)
    s = re.sub(r"-{2,}", "--", s)
    s = re.sub(r"\s+", " ", s).strip()
    return s


def normaliza(linhas):
    out = []
    for l in linhas:
        n = normaliza_linha(l)
        if n:
            out.append(n)
    return out


def blocos(linhas):
    """Lista de (id_bloco, linha). O id e o do ultimo cabecalho visto (N5b, R2N1a, ...)."""
    atual, sec = "INICIO", "INICIO"
    res = []
    for l in linhas:
        m = CABEC.match(l)
        if m:
            ident = m.group(1)
            if l.startswith("="):
                sec = ident
                atual = ident
            else:
                atual = ident
        res.append((atual, sec, l))
    return res


def neutro(ident, sec, neutros):
    for n in neutros:
        if not n:
            continue
        if ident == n or sec == n or (ident.startswith(n) and not ident[len(n):len(n) + 1].isdigit()):
            return True
    return False


def compara(golden, obtido, neutros):
    g = [x for x in blocos(open(golden).read().splitlines()) if not neutro(x[0], x[1], neutros)]
    o = [x for x in blocos(open(obtido).read().splitlines()) if not neutro(x[0], x[1], neutros)]
    import difflib
    d = list(difflib.unified_diff([f"{a}| {c}" for a, b, c in g], [f"{a}| {c}" for a, b, c in o],
                                  "esperado(modelo-v2)", "obtido", lineterm="", n=1))
    if d:
        print("\n".join(d[:80]))
        if len(d) > 80:
            print(f"... ({len(d) - 80} linhas de diff omitidas)")
        return 1
    return 0


def tabela(sondas, neutras_arq, resultado, funcs_arq, tabelas_novas_arq=None):
    esperadas = [l.rstrip("\n") for l in open(sondas) if l.strip()]
    neutras, toleradas = set(), set()
    try:
        for l in open(neutras_arq):
            l = l.rstrip("\n")
            if l.startswith("?"):
                toleradas.add(l[1:])
            elif l and not l.startswith("#"):
                neutras.add(l)
    except FileNotFoundError:
        pass
    funcs_v2 = set(x.strip() for x in open(funcs_arq) if x.strip())
    novas = set()
    if tabelas_novas_arq:
        novas = set(x.strip() for x in open(tabelas_novas_arq) if x.strip())
    obt = {}
    for l in open(resultado):
        l = l.rstrip("\n")
        if "\t" in l:
            n, ok = l.rsplit("\t", 1)
            obt.setdefault(n, []).append(ok == "t")
    ruins = []
    for n in esperadas:
        if n in neutras:
            continue
        if n not in obt:
            if n not in toleradas:
                ruins.append("AUSENTE: " + n)
        elif not all(obt[n]):
            ruins.append("FALHA: " + n)
    for n, oks in obt.items():
        if n in esperadas or n in neutras or all(oks):
            continue
        m = re.search(r"EXECUTE (\S+) \[", n)
        if m and m.group(1) not in funcs_v2:
            continue
        if novas and set(re.findall(r"[a-z_][a-z0-9_]*", n)) & novas:
            continue  # sonda gerada pela matriz para uma tabela que nao existe no modelo-v2
        ruins.append("FALHA(nova): " + n)
    print("\n".join(ruins))
    return 0


if __name__ == "__main__":
    cmd = sys.argv[1]
    if cmd == "normaliza":
        open(sys.argv[3], "w").write("\n".join(normaliza(open(sys.argv[2], errors="replace").read().splitlines())) + "\n")
    elif cmd == "tabela":
        sys.exit(tabela(*sys.argv[2:7]))
    elif cmd == "compara":
        sys.exit(compara(sys.argv[2], sys.argv[3], sys.argv[4].split(",") if len(sys.argv) > 4 else []))
    else:
        sys.exit(2)
