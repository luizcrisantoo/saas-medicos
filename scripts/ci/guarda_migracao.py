#!/usr/bin/env python3
"""Guarda de migracao (R-07, R-08; ADR-0027, ADR-0039, ADR-0040).

Uso: guarda_migracao.py DIR_MIGRACOES ARQUIVO_APROVACOES

Le todo arquivo de DIR_MIGRACOES (recursivo: o Flyway tambem executa callbacks
como beforeMigrate.sql). Cada arquivo .sql passa por um analisador lexico do
SQL do PostgreSQL (comentarios aninhados, aspas simples e duplas, E'', U&'',
U&"", dollar quoting, literais adjacentes) e o conteudo de todo literal e de
todo corpo $$...$$ (DO, CREATE FUNCTION, EXECUTE '...') e analisado de novo
como SQL. As regras olham a sequencia de palavras, nao o texto cru: caixa,
quebras de linha, tabs, comentarios e aspas nao mudam o resultado.

Uma migracao "perigosa" so passa se o par (sha256 do conteudo exato, nome do
arquivo) estiver em ARQUIVO_APROVACOES, no formato do sha256sum. Linhas que
comecam com '#' sao comentarios (a justificativa da aprovacao).

Na duvida a guarda recusa: SQL que o analisador nao entende, SQL dinamico
(EXECUTE de expressao, funcoes que executam texto), placeholder do Flyway e
arquivo que nao e .sql exigem aprovacao.

Saida: 0 se todo arquivo e limpo ou aprovado; 1 se algum e recusado; 2 para
erro de uso ou arquivo de aprovacoes invalido.
"""

import hashlib
import os
import re
import sys

PROFUNDIDADE_MAX = 16


class ErroLexico(Exception):
    pass


# ---------------------------------------------------------------------------
# Analisador lexico
# ---------------------------------------------------------------------------

class Tok:
    __slots__ = ("tipo", "valor", "linha")

    def __init__(self, tipo, valor, linha):
        self.tipo = tipo  # word, qident, str, num, op, param
        self.valor = valor
        self.linha = linha

    def __repr__(self):
        return "Tok(%s,%r,%d)" % (self.tipo, self.valor, self.linha)


def _eh_inicio_ident(c):
    return c.isalpha() or c == "_" or ord(c) > 127


def _eh_ident(c):
    return c.isalnum() or c in "_$" or ord(c) > 127


def _decodifica_e(s):
    """Escapes de E'...' (PostgreSQL 16, 4.1.2.2)."""
    out = []
    i = 0
    n = len(s)
    while i < n:
        c = s[i]
        if c != "\\" or i + 1 >= n:
            out.append(c)
            i += 1
            continue
        d = s[i + 1]
        simples = {"b": "\b", "f": "\f", "n": "\n", "r": "\r", "t": "\t"}
        if d in simples:
            out.append(simples[d])
            i += 2
        elif d in "01234567":
            j = i + 1
            while j < n and j < i + 4 and s[j] in "01234567":
                j += 1
            out.append(chr(int(s[i + 1:j], 8) & 0xFF))
            i = j
        elif d == "x" and i + 2 < n and s[i + 2] in "0123456789abcdefABCDEF":
            j = i + 2
            while j < n and j < i + 4 and s[j] in "0123456789abcdefABCDEF":
                j += 1
            out.append(chr(int(s[i + 2:j], 16)))
            i = j
        elif d in "uU":
            tam = 4 if d == "u" else 8
            hexa = s[i + 2:i + 2 + tam]
            if len(hexa) == tam and all(h in "0123456789abcdefABCDEF" for h in hexa):
                try:
                    out.append(chr(int(hexa, 16)))
                except (ValueError, OverflowError):
                    raise ErroLexico("escape unicode invalido")
                i += 2 + tam
            else:
                out.append(d)
                i += 2
        else:
            out.append(d)
            i += 2
    return "".join(out)


def _decodifica_unicode(s, esc="\\"):
    """Escapes de U&'...' e U&"..." com o caractere de escape dado."""
    out = []
    i = 0
    n = len(s)
    hexd = "0123456789abcdefABCDEF"
    while i < n:
        c = s[i]
        if c != esc:
            out.append(c)
            i += 1
            continue
        if i + 1 < n and s[i + 1] == esc:
            out.append(esc)
            i += 2
        elif i + 1 < n and s[i + 1] == "+" and len(s[i + 2:i + 8]) == 6 and all(h in hexd for h in s[i + 2:i + 8]):
            try:
                out.append(chr(int(s[i + 2:i + 8], 16)))
            except (ValueError, OverflowError):
                raise ErroLexico("escape unicode invalido")
            i += 8
        elif len(s[i + 1:i + 5]) == 4 and all(h in hexd for h in s[i + 1:i + 5]):
            out.append(chr(int(s[i + 1:i + 5], 16)))
            i += 5
        else:
            raise ErroLexico("escape unicode invalido")
    return "".join(out)


def tokeniza(sql):
    toks = []
    i = 0
    n = len(sql)
    linha = 1

    def conta(a, b):
        return sql.count("\n", a, b)

    def le_aspas(ini, delim, barra):
        """Le do caractere apos o delimitador de abertura ate o de fechamento."""
        j = ini
        buf = []
        while True:
            if j >= n:
                raise ErroLexico("literal sem fechamento")
            c = sql[j]
            if barra and c == "\\" and j + 1 < n:
                buf.append(sql[j:j + 2])
                j += 2
                continue
            if c == delim:
                if j + 1 < n and sql[j + 1] == delim:
                    buf.append(delim if not barra else delim * 2)
                    j += 2
                    continue
                return "".join(buf), j + 1
            buf.append(c)
            j += 1

    while i < n:
        c = sql[i]
        if c in " \t\r\n\f\v":
            if c == "\n":
                linha += 1
            i += 1
            continue
        if sql.startswith("--", i):
            j = sql.find("\n", i)
            i = n if j < 0 else j
            continue
        if sql.startswith("/*", i):
            prof = 0
            j = i
            while j < n:
                if sql.startswith("/*", j):
                    prof += 1
                    j += 2
                elif sql.startswith("*/", j):
                    prof -= 1
                    j += 2
                    if prof == 0:
                        break
                else:
                    j += 1
            if prof != 0:
                raise ErroLexico("comentario sem fechamento")
            linha += conta(i, j)
            i = j
            continue
        ini_linha = linha
        # literais com prefixo: E'', B'', X'', N'', U&'', U&""
        if c in "eE" and i + 1 < n and sql[i + 1] == "'":
            bruto, j = le_aspas(i + 2, "'", True)
            bruto = bruto.replace("''", "'")
            toks.append(Tok("str", _decodifica_e(bruto), ini_linha))
            linha += conta(i, j)
            i = j
            continue
        if c in "uU" and sql.startswith("&'", i + 1):
            bruto, j = le_aspas(i + 3, "'", False)
            toks.append(Tok("ustr", bruto, ini_linha))
            linha += conta(i, j)
            i = j
            continue
        if c in "uU" and sql.startswith('&"', i + 1):
            bruto, j = le_aspas(i + 3, '"', False)
            toks.append(Tok("uqident", bruto, ini_linha))
            linha += conta(i, j)
            i = j
            continue
        if c in "bBxXnN" and i + 1 < n and sql[i + 1] == "'":
            bruto, j = le_aspas(i + 2, "'", False)
            toks.append(Tok("str", bruto, ini_linha))
            linha += conta(i, j)
            i = j
            continue
        if c == "'":
            bruto, j = le_aspas(i + 1, "'", False)
            toks.append(Tok("str", bruto, ini_linha))
            linha += conta(i, j)
            i = j
            continue
        if c == '"':
            bruto, j = le_aspas(i + 1, '"', False)
            toks.append(Tok("qident", bruto.lower(), ini_linha))
            linha += conta(i, j)
            i = j
            continue
        if c == "$":
            m = re.match(r"\$([A-Za-z_\u0080-￿][A-Za-z0-9_\u0080-￿]*)?\$", sql[i:])
            if m:
                tag = m.group(0)
                fim = sql.find(tag, i + len(tag))
                if fim < 0:
                    raise ErroLexico("dollar quote sem fechamento")
                toks.append(Tok("str", sql[i + len(tag):fim], ini_linha))
                j = fim + len(tag)
                linha += conta(i, j)
                i = j
                continue
            m = re.match(r"\$[0-9]+", sql[i:])
            if m:
                toks.append(Tok("param", m.group(0), ini_linha))
                i += len(m.group(0))
                continue
            if sql.startswith("${", i):
                toks.append(Tok("op", "${", ini_linha))
                i += 2
                continue
            toks.append(Tok("op", "$", ini_linha))
            i += 1
            continue
        if _eh_inicio_ident(c):
            j = i + 1
            while j < n and _eh_ident(sql[j]):
                j += 1
            toks.append(Tok("word", sql[i:j].lower(), ini_linha))
            i = j
            continue
        if c.isdigit() or (c == "." and i + 1 < n and sql[i + 1].isdigit()):
            j = i + 1
            while j < n and (sql[j].isalnum() or sql[j] in "._"):
                j += 1
            toks.append(Tok("num", sql[i:j], ini_linha))
            i = j
            continue
        if sql.startswith("||", i):
            toks.append(Tok("op", "||", ini_linha))
            i += 2
            continue
        toks.append(Tok("op", c, ini_linha))
        i += 1

    # UESCAPE e literais adjacentes
    saida = []
    k = 0
    while k < len(toks):
        t = toks[k]
        if t.tipo in ("ustr", "uqident"):
            esc = "\\"
            if (k + 2 < len(toks) and toks[k + 1].tipo == "word" and toks[k + 1].valor == "uescape"
                    and toks[k + 2].tipo == "str" and len(toks[k + 2].valor) == 1):
                esc = toks[k + 2].valor
                k += 2
            val = _decodifica_unicode(t.valor, esc)
            t = Tok("str" if t.tipo == "ustr" else "qident",
                    val if t.tipo == "ustr" else val.lower(), t.linha)
        if t.tipo == "str" and saida and saida[-1].tipo == "str":
            # 'a'
            # 'b' e um literal so no PostgreSQL; junta sempre (na duvida, mais deteccao)
            saida[-1] = Tok("str", saida[-1].valor + t.valor, saida[-1].linha)
        else:
            saida.append(t)
        k += 1
    return saida


# ---------------------------------------------------------------------------
# Regras
# ---------------------------------------------------------------------------

def _palavra(t):
    if t is None:
        return None
    if t.tipo in ("word", "qident"):
        return t.valor
    return None


FUNCOES_QUE_EXECUTAM_TEXTO = {
    "dblink", "dblink_exec", "dblink_send_query", "dblink_open", "dblink_fetch",
    "query_to_xml", "query_to_xmlschema", "query_to_xml_and_xmlschema",
    "ts_stat", "ts_rewrite", "pg_background_launch",
}

PALAVRAS_PROIBIDAS = {
    "session_replication_role": "session_replication_role (desliga gatilhos e regras)",
    "bypassrls": "atributo BYPASSRLS (papel que ignora RLS)",
    "superuser": "atributo SUPERUSER",
}


def _seq(toks, i, *esperado):
    """Confere palavras consecutivas a partir de i. Cada item: str ou tupla de alternativas."""
    for k, e in enumerate(esperado):
        w = _palavra(toks[i + k]) if i + k < len(toks) else None
        if w is None:
            return False
        if isinstance(e, tuple):
            if w not in e:
                return False
        elif w != e:
            return False
    return True


def _alvo(toks, j):
    """Nome (schema, tabela) a partir de j, pulando ONLY / IF EXISTS / TABLE."""
    while _palavra(toks[j] if j < len(toks) else None) in ("only", "table", "if", "exists"):
        j += 1
    nomes = []
    while j < len(toks):
        w = _palavra(toks[j])
        if w is None:
            break
        nomes.append(w)
        if j + 1 < len(toks) and toks[j + 1].tipo == "op" and toks[j + 1].valor == ".":
            j += 2
            continue
        break
    return nomes


def _divide(toks):
    stmts = []
    atual = []
    for t in toks:
        if t.tipo == "op" and t.valor == ";":
            if atual:
                stmts.append(atual)
            atual = []
        else:
            atual.append(t)
    if atual:
        stmts.append(atual)
    return stmts


def _regras_comando(st, aninhado, achados):
    n = len(st)
    palavras = [_palavra(t) for t in st]

    def acha(linha, motivo):
        achados.append((linha, motivo))

    for i in range(n):
        w = palavras[i]
        t = st[i]
        if not aninhado and t.tipo == "op" and t.valor == "\\":
            acha(t.linha, "meta-comando de cliente (\\...) fora de literal")
        if w is None:
            continue
        if w in PALAVRAS_PROIBIDAS:
            acha(t.linha, PALAVRAS_PROIBIDAS[w])

        if w == "create":
            j = i + 1
            if _seq(st, j, "or", "replace"):
                j += 2
            if _seq(st, j, "constraint", "trigger") or _seq(st, j, "trigger"):
                acha(t.linha, "CREATE TRIGGER")
            elif _seq(st, j, "event", "trigger"):
                acha(t.linha, "CREATE EVENT TRIGGER")
            elif _seq(st, j, "policy"):
                acha(t.linha, "CREATE POLICY")
            elif _seq(st, j, "rule"):
                acha(t.linha, "CREATE RULE")
        elif w == "alter":
            if _seq(st, i + 1, "policy"):
                acha(t.linha, "ALTER POLICY")
            elif _seq(st, i + 1, "trigger"):
                acha(t.linha, "ALTER TRIGGER")
            elif _seq(st, i + 1, "rule"):
                acha(t.linha, "ALTER RULE")
            elif _seq(st, i + 1, "event", "trigger"):
                acha(t.linha, "ALTER EVENT TRIGGER")
            elif _seq(st, i + 1, "system"):
                acha(t.linha, "ALTER SYSTEM")
        elif w == "drop":
            if _seq(st, i + 1, "policy"):
                acha(t.linha, "DROP POLICY")
            elif _seq(st, i + 1, "trigger"):
                acha(t.linha, "DROP TRIGGER")
            elif _seq(st, i + 1, "rule"):
                acha(t.linha, "DROP RULE")
            elif _seq(st, i + 1, "event", "trigger"):
                acha(t.linha, "DROP EVENT TRIGGER")
            elif _seq(st, i + 1, "owned"):
                acha(t.linha, "DROP OWNED")
        elif w == "disable":
            if _seq(st, i + 1, "trigger"):
                acha(t.linha, "DISABLE TRIGGER")
            elif _seq(st, i + 1, "rule"):
                acha(t.linha, "DISABLE RULE")
            elif _seq(st, i + 1, "row", "level", "security"):
                acha(t.linha, "DISABLE ROW LEVEL SECURITY")
        elif w == "no" and _seq(st, i + 1, "force", "row", "level", "security"):
            acha(t.linha, "NO FORCE ROW LEVEL SECURITY")
        elif w == "enable" and _seq(st, i + 1, ("replica", "always"), ("trigger", "rule")):
            acha(t.linha, "ENABLE %s %s (muda quando o gatilho ou a regra dispara)"
                 % (palavras[i + 1].upper(), palavras[i + 2].upper()))
        elif w == "returns" and _seq(st, i + 1, ("trigger", "event_trigger")):
            if "create" in palavras[:i]:
                acha(t.linha, "CREATE FUNCTION ... RETURNS %s (cria ou substitui funcao de gatilho)"
                     % palavras[i + 1].upper())

        # escrita direta no catalogo do sistema (pg_trigger, pg_policy, pg_class, pg_settings...)
        alvo = None
        if w in ("update", "truncate"):
            alvo = _alvo(st, i + 1)
        elif w in ("insert", "merge") and _seq(st, i + 1, "into"):
            alvo = _alvo(st, i + 2)
        elif w == "delete" and _seq(st, i + 1, "from"):
            alvo = _alvo(st, i + 2)
        elif w == "alter" and _seq(st, i + 1, "table"):
            alvo = _alvo(st, i + 2)
        elif w == "copy":
            alvo = _alvo(st, i + 1)
        if alvo and (alvo[-1].startswith("pg_") or alvo[0] == "pg_catalog"):
            acha(t.linha, "escrita no catalogo do sistema (%s)" % ".".join(alvo))

        # SQL dinamico
        if w == "execute":
            prox = _palavra(st[i + 1]) if i + 1 < n else None
            if prox in ("function", "procedure", "on"):
                continue
            if i > 0 and palavras[i - 1] in ("grant", "revoke"):
                continue
            if i > 0 and st[i - 1].tipo == "op" and st[i - 1].valor == ",":
                # GRANT SELECT, EXECUTE ON ...
                continue
            arg = st[i + 1] if i + 1 < n else None
            depois = st[i + 2] if i + 2 < n else None
            literal = arg is not None and arg.tipo == "str" and (
                depois is None or _palavra(depois) in ("using", "into")
                or (depois.tipo == "op" and depois.valor == ")"))
            preparado = (not aninhado) and arg is not None and arg.tipo in ("word", "qident")
            if not literal and not preparado:
                acha(t.linha, "SQL dinamico (EXECUTE de expressao nao literal)")
        if w in FUNCOES_QUE_EXECUTAM_TEXTO and i + 1 < n and st[i + 1].tipo == "op" and st[i + 1].valor == "(":
            acha(t.linha, "funcao que executa SQL em texto (%s)" % w)
        if w == "set_config" and i + 1 < n and st[i + 1].tipo == "op" and st[i + 1].valor == "(":
            a = st[i + 2] if i + 2 < n else None
            b = st[i + 3] if i + 3 < n else None
            if not (a is not None and a.tipo == "str" and b is not None and b.tipo == "op" and b.valor == ","):
                acha(t.linha, "set_config com nome de parametro nao literal")

    if "drop" in palavras and "cascade" in palavras:
        acha(st[0].linha, "DROP ... CASCADE (pode remover gatilho ou politica dependente)")


REGEX_RESERVA = [
    (r"\bcreate (or replace )?(constraint )?trigger\b", "CREATE TRIGGER"),
    (r"\bcreate event trigger\b", "CREATE EVENT TRIGGER"),
    (r"\bcreate policy\b", "CREATE POLICY"),
    (r"\bcreate (or replace )?rule\b", "CREATE RULE"),
    (r"\balter (policy|trigger|rule|event trigger|system)\b", "ALTER POLICY/TRIGGER/RULE"),
    (r"\bdrop (policy|trigger|rule|event trigger|owned)\b", "DROP POLICY/TRIGGER/RULE"),
    (r"\bdisable (trigger|rule|row level security)\b", "DISABLE TRIGGER/RULE/RLS"),
    (r"\bno force row level security\b", "NO FORCE ROW LEVEL SECURITY"),
    (r"\benable (replica|always) (trigger|rule)\b", "ENABLE REPLICA/ALWAYS"),
    (r"session_replication_role", "session_replication_role"),
    (r"bypassrls", "BYPASSRLS"),
    (r"\bexecute\b", "SQL dinamico em literal nao analisavel"),
    (r"\bpg_(trigger|policy|rewrite|class|event_trigger|settings|authid)\b", "catalogo do sistema"),
]


def _reserva(texto, linha, achados):
    """Literal que nao e SQL valido: busca normalizada (caixa, espacos, comentarios, aspas)."""
    s = re.sub(r"/\*.*?\*/", " ", texto, flags=re.S)
    s = re.sub(r"--[^\n]*", " ", s)
    s = s.replace('"', "").replace("'", " ").lower()
    s = re.sub(r"\s+", " ", s)
    for padrao, motivo in REGEX_RESERVA:
        if re.search(padrao, s):
            achados.append((linha, motivo + " (literal nao analisavel)"))


def analisa(sql, aninhado=False, linha_base=0, profundidade=0, achados=None):
    if achados is None:
        achados = []
    if profundidade > PROFUNDIDADE_MAX:
        achados.append((linha_base, "aninhamento de literais profundo demais"))
        return achados
    try:
        toks = tokeniza(sql)
    except ErroLexico as e:
        if aninhado:
            _reserva(sql, linha_base, achados)
        else:
            achados.append((linha_base, "SQL nao analisavel: %s" % e))
            _reserva(sql, linha_base, achados)
        return achados
    if aninhado:
        for t in toks:
            t.linha = linha_base
    else:
        for t in toks:
            t.linha += linha_base
    for st in _divide(toks):
        _regras_comando(st, aninhado, achados)
    for t in toks:
        if t.tipo == "str" and t.valor.strip():
            analisa(t.valor, True, t.linha, profundidade + 1, achados)
    return achados


def analisa_arquivo(caminho):
    with open(caminho, "rb") as f:
        dados = f.read()
    achados = []
    if not caminho.lower().endswith(".sql"):
        achados.append((0, "arquivo que nao e .sql no diretorio de migracoes"))
        return dados, achados
    try:
        texto = dados.decode("utf-8")
    except UnicodeDecodeError:
        achados.append((0, "arquivo nao e UTF-8 valido"))
        return dados, achados
    if texto.startswith("﻿"):
        texto = texto[1:]
    if "\x00" in texto:
        achados.append((0, "byte nulo no arquivo"))
    if "${" in texto:
        achados.append((0, "placeholder do Flyway (${...})"))
    analisa(texto, achados=achados)
    return dados, achados


# ---------------------------------------------------------------------------
# Aprovacoes
# ---------------------------------------------------------------------------

LINHA_APROVACAO = re.compile(r"^([0-9a-fA-F]{64}) [ *](.+)$")


def le_aprovacoes(caminho):
    aprov = set()
    if not os.path.exists(caminho):
        print("guarda: arquivo de aprovacoes ausente (%s): nenhuma aprovacao" % caminho)
        return aprov
    with open(caminho, "r", encoding="utf-8") as f:
        for num, linha in enumerate(f, 1):
            linha = linha.rstrip("\r\n")
            if not linha.strip() or linha.lstrip().startswith("#"):
                continue
            m = LINHA_APROVACAO.match(linha)
            if not m:
                raise ValueError("linha %d invalida (formato do sha256sum: '<sha256>  <arquivo>')" % num)
            nome = m.group(2).strip()
            aprov.add((m.group(1).lower(), os.path.basename(nome)))
    return aprov


def main(argv):
    if len(argv) != 3:
        print("uso: guarda-migracao.sh DIR_MIGRACOES ARQUIVO_APROVACOES", file=sys.stderr)
        return 2
    diretorio, arq_aprov = argv[1], argv[2]
    if not os.path.isdir(diretorio):
        print("guarda: diretorio inexistente: %s" % diretorio, file=sys.stderr)
        return 2
    try:
        aprovacoes = le_aprovacoes(arq_aprov)
    except (ValueError, UnicodeDecodeError) as e:
        print("guarda: arquivo de aprovacoes invalido: %s" % e, file=sys.stderr)
        return 2

    arquivos = []
    for raiz, dirs, nomes in os.walk(diretorio):
        dirs.sort()
        for nome in sorted(nomes):
            arquivos.append(os.path.join(raiz, nome))

    recusadas = 0
    for caminho in arquivos:
        rel = os.path.relpath(caminho, diretorio)
        if os.path.islink(caminho):
            print("RECUSADA  %s: link simbolico" % rel)
            recusadas += 1
            continue
        dados, achados = analisa_arquivo(caminho)
        sha = hashlib.sha256(dados).hexdigest()
        if not achados:
            print("LIMPA     %s" % rel)
            continue
        motivos = sorted({m for _, m in achados})
        if (sha, os.path.basename(caminho)) in aprovacoes:
            print("APROVADA  %s (sha256 %s): %s" % (rel, sha, "; ".join(motivos)))
            continue
        recusadas += 1
        print("RECUSADA  %s (sha256 %s), exige aprovacao registrada:" % (rel, sha))
        vistos = set()
        for linha, motivo in sorted(achados):
            if (linha, motivo) in vistos:
                continue
            vistos.add((linha, motivo))
            print("    linha %d: %s" % (linha, motivo))
    if recusadas:
        print("guarda: %d arquivo(s) recusado(s). Aprovacao: revisao do Red Team no PR e a linha "
              "'<sha256>  <arquivo>' em src/main/resources/db/aprovacoes.sha256." % recusadas)
        return 1
    print("guarda: %d arquivo(s) conferido(s), nenhum recusado." % len(arquivos))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
