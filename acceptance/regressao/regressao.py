#!/usr/bin/env python3
"""Normaliza e compara a saida das baterias de regressao impressas (Red Team).

Uso:
  regressao.py normaliza ENTRADA SAIDA
  regressao.py tabela SONDAS NEUTRAS RESULTADO FUNCOES_V2
    Baterias com tabela de resultado: toda sonda do golden (SONDAS, gerado contra o modelo-v2) tem
    que estar presente e ok, salvo as NEUTRAS. Sonda nova so falha se nao for a linha da matriz
    P-funcao de uma funcao que nao existe no modelo-v2, ou a linha da matriz de uma tabela nova
    (TABELAS_NOVAS: tabelas do banco que o modelo-v2 nao tem); objetos novos seguem as regras gerais de F2.6.
  regressao.py semente BATERIA ENTRADA SAIDA DIFF
    Acrescenta a semente I-22 (telefone_contato) nas baterias rls, indep1 e indep2; recusa se a
    adaptacao nao for so acrescimo ou se alguma linha de sonda mudar. Ver SEMENTES abaixo.
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


# ---------------------------------------------------------------------------------------------
# Adaptacao de SEMENTE ao modelo da Fase 2 (docs/fase2/spec.md, secao 6, "Semente I-22").
# I-22 (F3.3): o caso guarda o telefone de contato informado na criacao (encaminhamento_cria o
# exige) e o envio ao paciente so sai para ele. As baterias da Fase 1 criam encaminhamentos por
# INSERT direto de superusuario, sem esse dado. A adaptacao so ACRESCENTA, na semente, o dado que
# todo caso criado pelo caminho real tem: telefone_contato = telefone da ficha na data da semente.
# Nada e removido nem trocado; nenhuma linha de sonda/afirmacao muda (conferido abaixo). Contra o
# modelo-v2 (sem a coluna) o acrescimo nao faz nada, entao o golden continua o mesmo.
# ---------------------------------------------------------------------------------------------
_COLUNA = ("EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='saas' "
           "AND table_name='encaminhamento' AND column_name='telefone_contato')")
_SEMENTE_TOPO = (
    "-- [regressao F2.9 | semente I-22, docs/fase2/spec.md secao 6] contato do caso = telefone da ficha\n"
    "DO $semente$ BEGIN IF " + _COLUNA + " THEN EXECUTE 'UPDATE saas.encaminhamento e SET telefone_contato = p.telefone "
    "FROM saas.paciente p WHERE p.id = e.paciente_id AND e.telefone_contato IS NULL'; END IF; END $semente$;"
)
_SEMENTE_EB = (
    "  IF " + _COLUNA + " THEN EXECUTE 'UPDATE saas.encaminhamento e SET telefone_contato = p.telefone "
    "FROM saas.paciente p WHERE p.id = e.paciente_id AND e.id = $1' USING eb; END IF; "
    "-- [regressao F2.9 | semente I-22, spec secao 6]"
)
# bateria -> [(linha ancora exata, ocorrencias da ancora no original, qual ocorrencia, antes|depois, texto, topo)]
# topo=True: a ancora tem que vir antes da primeira sonda (e semente, nao bloco de teste).
SEMENTES = {
    "rls": [("SET session_replication_role = replica;", 2, 1, "depois", _SEMENTE_TOPO, True)],
    "indep1": [("ALTER TABLE encaminhamento ENABLE TRIGGER USER;", 1, 1, "antes", _SEMENTE_TOPO, True)],
    "indep2": [
        ("ALTER TABLE encaminhamento ENABLE TRIGGER USER;", 1, 1, "antes", _SEMENTE_TOPO, True),
        # N2: o caso eb e preparado no inicio do bloco (INSERT de superusuario), antes de qualquer afirmacao
        ("    VALUES (eb,'e0000000-0000-0000-0002-000000000001','c0000000-0000-0000-0003-000000000001',"
         "'dddddddd-0000-0000-0000-000000000001','\\xcc03','ROTINA','CRIADO',now()+interval '10 days');",
         1, 1, "depois", _SEMENTE_EB, False),
    ],
}
# linhas que sao sonda/afirmacao nas baterias de tabela
SONDA = re.compile(r"teste_aux\.sonda\(|\bt\.chk\(|\bt\.a\(|\bt\.flush\(|\br2\.(?:sonda|chk|reg)\(|INSERT INTO (?:teste_aux|t|r2)\.res")


def sondas_de(linhas):
    return [l for l in linhas if SONDA.search(l)]


def semente(bateria, entrada, saida, diff_arq):
    orig = open(entrada).read().split("\n")
    regras = SEMENTES.get(bateria, [])
    out = list(orig)
    acrescidas = 0
    for ancora, total, qual, onde, texto, topo in regras:
        idx = [i for i, l in enumerate(out) if l == ancora]
        if len(idx) != total:
            print(f"semente {bateria}: ancora encontrada {len(idx)} vez(es), esperado {total}: {ancora[:70]}")
            return 1
        i = idx[qual - 1]
        if topo:
            prim = next((k for k, l in enumerate(out) if SONDA.search(l)), len(out))
            if i > prim:
                print(f"semente {bateria}: ancora depois da primeira sonda (linha {i + 1} > {prim + 1})")
                return 1
        novas = texto.split("\n")
        if any(SONDA.search(l) for l in novas):
            print(f"semente {bateria}: texto acrescido contem sonda")
            return 1
        pos = i + 1 if onde == "depois" else i
        out[pos:pos] = novas
        acrescidas += len(novas)
    # guarda: so acrescimo. Tirando as linhas acrescidas, o arquivo e o original; sondas identicas.
    import difflib
    d = list(difflib.unified_diff(orig, out, "original", "adaptado", lineterm="", n=0))
    menos = [l for l in d if l.startswith("-") and not l.startswith("---")]
    mais = [l for l in d if l.startswith("+") and not l.startswith("+++")]
    if menos or len(mais) != acrescidas:
        print(f"semente {bateria}: adaptacao nao e so acrescimo ({len(menos)} linha(s) removida(s))")
        return 1
    if sondas_de(orig) != sondas_de(out):
        print(f"semente {bateria}: linhas de sonda diferem")
        return 1
    open(saida, "w").write("\n".join(out))
    open(diff_arq, "w").write("\n".join(d) + "\n" + f"# sondas: {len(sondas_de(orig))} antes, {len(sondas_de(out))} depois; "
                              f"linhas removidas: 0; acrescidas: {acrescidas}\n")
    return 0


if __name__ == "__main__":
    cmd = sys.argv[1]
    if cmd == "semente":
        sys.exit(semente(*sys.argv[2:6]))
    if cmd == "normaliza":
        open(sys.argv[3], "w").write("\n".join(normaliza(open(sys.argv[2], errors="replace").read().splitlines())) + "\n")
    elif cmd == "tabela":
        sys.exit(tabela(*sys.argv[2:7]))
    elif cmd == "compara":
        sys.exit(compara(sys.argv[2], sys.argv[3], sys.argv[4].split(",") if len(sys.argv) > 4 else []))
    else:
        sys.exit(2)
