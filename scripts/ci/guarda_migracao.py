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

Lista de construcoes PERMITIDAS (tentativa 2, ADR-0040 item 2): cada comando de primeiro
nivel e comparado com uma lista curta de DDL comum (tabela, indice, coluna, tipo enumerado,
comentario, INSERT de dado de referencia, SET ROLE saas_owner, search_path); todo o resto
exige aprovacao. Detectores nomeados (funcao, privilegio, dono, papel, row_security,
set_config, COPY, LOAD, extensao, visao...) rodam tambem dentro de literais e corpos $$.

Tentativa 3 (ADR-0040, itens 2a a 2d e 8): GRANT sem aprovacao so em tabela classificada
como nao sensivel em tabelas-sensiveis.txt (ao lado deste script; tabela nova e sensivel por
padrao), REVOKE passa; DROP INDEX e DROP CONSTRAINT exigem aprovacao; CREATE TABLE em saas.*
sem ENABLE e FORCE ROW LEVEL SECURITY na mesma migracao e recusado (inclusive LIKE e CTAS);
SET/DROP DEFAULT em coluna de tenant, chave, storage ou status exige aprovacao. No CI este
script e a lista vem do commit da branch base, nunca do PR.

Uma migracao fora da lista so passa se o par (sha256 do conteudo exato, nome do
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
    "createrole": "atributo CREATEROLE",
    "row_security": "parametro row_security (como a RLS e avaliada)",
    "security_barrier": "opcao security_barrier de visao",
    "security_invoker": "opcao security_invoker de visao",
}

# Parametros que mudam quem acessa o que ou como a seguranca e avaliada. Todo parametro
# com ponto (app.clinica_id, app.papel, app.sessao, saas.transicao: contexto das politicas
# e dos gatilhos) tambem conta.
PARAMETROS_DE_SEGURANCA = {
    "role", "session_authorization", "search_path", "row_security",
    "session_replication_role", "default_transaction_read_only", "transaction_read_only",
    "check_function_bodies", "local_preload_libraries", "session_preload_libraries",
    "shared_preload_libraries", "dynamic_library_path", "jit_provider",
}


def _parametro_de_seguranca(nome):
    nome = nome.strip().lower()
    return nome in PARAMETROS_DE_SEGURANCA or "." in nome


# ---------------------------------------------------------------------------
# Lista de construcoes PERMITIDAS sem aprovacao (comando de primeiro nivel).
# Todo o resto exige aprovacao (ADR-0040, item 2). Na duvida, recusa.
# ---------------------------------------------------------------------------

SCHEMA_PERMITIDO = "saas"
# Convencao das migracoes: o Flyway conecta como saas_migracao e faz SET ROLE saas_owner
# para que o dono dos objetos seja sempre saas_owner. Qualquer outro papel exige aprovacao.
PAPEL_DE_MIGRACAO = "saas_owner"
SEARCH_PATH_PERMITIDO = {"saas", "public", "pg_catalog"}
PARAMETROS_SET_PERMITIDOS = {"lock_timeout", "statement_timeout", "client_min_messages"}
# INSERT sem aprovacao so em tabela de dados de referencia (sem efeito sobre acesso).
# usuario_clinica, paciente_clinica, profissional_clinica, flag_clinica etc. mudam quem
# acessa o que: exigem aprovacao.
TABELAS_REFERENCIA = {"especialidade"}

# Palavras (sem aspas) que nunca aparecem num comando permitido.
PALAVRAS_FORA_DA_LISTA = {
    "security", "security_barrier", "security_invoker", "owner", "grant", "revoke",
    "policy", "trigger", "rule", "execute", "function", "procedure", "routine", "role",
    "authorization", "tablespace", "select", "copy", "program", "definer", "invoker",
    "privileges", "extension", "schema", "system", "bypassrls",
    "superuser", "session_replication_role", "row_security", "load", "returning",
    "view", "inherit", "public",
}

# Antes de "(", palavras-chave e nomes de tipo/funcao comuns aceitos em DDL de tabela.
ANTES_DE_PARENTESE_OK = {
    # palavras-chave
    "key", "unique", "check", "exclude", "include", "where", "values", "default", "as",
    "in", "not", "and", "or", "any", "all", "some", "with", "exists", "enum", "conflict",
    "identity", "array", "row", "filter", "over", "by", "is", "then", "else", "when",
    "case", "distinct", "between", "like", "ilike", "similar",
    # metodos de indice
    "btree", "gin", "gist", "hash", "brin", "spgist",
    # tipos com modificador
    "varchar", "char", "character", "varying", "numeric", "decimal", "bit", "timestamp",
    "timestamptz", "time", "timetz", "interval", "float",
    # funcoes da biblioteca padrao sem efeito colateral
    "now", "gen_random_uuid", "lower", "upper", "btrim", "ltrim", "rtrim", "trim",
    "length", "char_length", "octet_length", "date_trunc", "timezone", "abs", "round",
    "coalesce", "nullif", "greatest", "least", "cast", "extract", "position", "substring",
    "left", "right", "nextval", "clock_timestamp", "statement_timestamp",
    "transaction_timestamp", "jsonb_typeof", "jsonb_array_length", "array_length",
    "cardinality", "to_tsvector", "regexp_replace", "date_part", "make_interval",
}
# Palavra antes de um nome seguido de "(": o nome e tabela, nao funcao.
ANTES_DE_TABELA = {"table", "exists", "into", "on", "only", "references"}


def _kw(t):
    """Palavra-chave: so palavra sem aspas ("owner" entre aspas e identificador)."""
    if t is not None and t.tipo == "word":
        return t.valor
    return None


def _eh_op(t, v):
    return t is not None and t.tipo == "op" and t.valor == v


def _nome_em(st, j):
    """Nome possivelmente qualificado a partir de j: (partes, proximo indice) ou (None, j)."""
    partes = []
    while j < len(st) and st[j].tipo in ("word", "qident"):
        partes.append(st[j].valor)
        if j + 1 < len(st) and _eh_op(st[j + 1], "."):
            j += 2
            continue
        return partes, j + 1
    return None, j


def _alvo_saas(partes):
    return partes is not None and (len(partes) == 1 or (len(partes) == 2 and partes[0] == SCHEMA_PERMITIDO))


def _fecha(st, j):
    """st[j] e '(': indice depois do ')' correspondente, ou None."""
    prof = 0
    while j < len(st):
        if _eh_op(st[j], "("):
            prof += 1
        elif _eh_op(st[j], ")"):
            prof -= 1
            if prof == 0:
                return j + 1
        j += 1
    return None


def _pula(st, j, *palavras):
    """Pula a sequencia de palavras-chave opcional; devolve o novo indice."""
    if all(j + k < len(st) and _kw(st[j + k]) == p for k, p in enumerate(palavras)):
        return j + len(palavras)
    return j


def _partes_virgula(st, j, fim):
    """Divide st[j:fim] nas virgulas de nivel 0."""
    partes, atual, prof = [], [], 0
    for t in st[j:fim]:
        if _eh_op(t, "(") or _eh_op(t, "["):
            prof += 1
        elif _eh_op(t, ")") or _eh_op(t, "]"):
            prof -= 1
        if prof == 0 and _eh_op(t, ","):
            partes.append(atual)
            atual = []
        else:
            atual.append(t)
    partes.append(atual)
    return partes


def _conteudo_comum(st):
    """Confere o corpo de um comando permitido: palavras e chamadas fora da lista."""
    for i, t in enumerate(st):
        if t.tipo == "param" or (t.tipo == "op" and t.valor in ("\\", "${")):
            return "parametro, meta-comando ou placeholder em comando comum"
        w = _kw(t)
        if w in PALAVRAS_FORA_DA_LISTA:
            # ENABLE/FORCE ROW LEVEL SECURITY: so reforca a RLS
            if w == "security" and i >= 3 and _kw(st[i - 1]) == "level" and _kw(st[i - 2]) == "row" \
                    and _kw(st[i - 3]) in ("enable", "force"):
                continue
            return "palavra '%s' fora da lista de DDL comum" % w.upper()
        if t.tipo in ("word", "qident") and i + 1 < len(st) and _eh_op(st[i + 1], "("):
            # nome seguido de "(": tabela (depois de TABLE/ON/INTO/REFERENCES...) ou chamada
            k = i
            while k >= 2 and _eh_op(st[k - 1], ".") and st[k - 2].tipo in ("word", "qident"):
                k -= 2
            antes = _kw(st[k - 1]) if k >= 1 else None
            if antes in ANTES_DE_TABELA:
                continue
            if k != i:
                return "chamada qualificada (%s) em comando comum" % ".".join(
                    x.valor for x in st[k:i + 1] if x.tipo != "op")
            if t.tipo == "word" and w in ANTES_DE_PARENTESE_OK:
                continue
            # nome de coluna seguido de tipo com modificador ja passou acima (varchar etc.)
            return "chamada de funcao fora da lista em comando comum (%s)" % t.valor
    return None


# ADR-0040 item 2d: SET/DROP DEFAULT sem aprovacao so em coluna que nao seja de tenant
# (clinica_id e afins), chave, storage ou status. Na duvida (nome casa com o padrao), recusa.
PADRAO_COLUNA_PROTEGIDA = re.compile(
    r"(^id$|_id$|^id_|clinica|tenant|organiza|empresa|conta|dono|owner|usuario|papel|role|"
    r"chave|key|pk|fk|uuid|hash|token|codigo|segredo|secret|"
    r"storage|bucket|objeto|caminho|path|arquivo|s3|url|uri|"
    r"status|situacao|estado|fase|etapa|ativo|ligad|revogad|aprovad|verificad)")


def _default_em_coluna(acao):
    """Para ALTER [COLUMN] c SET DEFAULT ... / DROP DEFAULT: (True, nome da coluna); senao (False, None)."""
    a = [_kw(t) for t in acao]
    if not a or a[0] != "alter":
        return False, None
    j = 2 if len(a) > 1 and a[1] == "column" else 1
    if j >= len(acao) or acao[j].tipo not in ("word", "qident"):
        return False, None
    resto = a[j + 1:]
    if resto[:2] == ["set", "default"] or resto == ["drop", "default"]:
        return True, acao[j].valor
    return False, None


def _acao_alter_table(acao):
    """Acao de ALTER TABLE permitida sem aprovacao (so cria ou reforca)."""
    if not acao:
        return False
    a = [_kw(t) for t in acao]
    if a[0] == "add":
        return True  # coluna ou restricao nova
    if a[0] == "validate" and len(a) >= 2 and a[1] == "constraint":
        return True
    if a[:4] in (["enable", "row", "level", "security"], ["force", "row", "level", "security"]) and len(a) == 4:
        return True
    # RENAME fica de fora: renomear tabela ou coluna e criar outra com o nome antigo troca o
    # objeto que funcoes e visoes leem pelo nome, sem politica (sombra).
    if a[0] == "alter":
        j = 2 if len(a) > 1 and a[1] == "column" else 1
        resto = a[j + 1:]
        if resto[:3] == ["set", "not", "null"] and len(resto) == 3:
            return True
        if resto[:2] == ["set", "default"] or resto == ["drop", "default"]:
            return False  # decidido em _default_protegido (precisa do nome da coluna)
        if (resto[:1] == ["type"] or resto[:3] == ["set", "data", "type"]) and "using" not in resto:
            # sem USING: conversao por cast, preserva o dado (USING reescreve, ex.: clinica_id)
            return True
    return False


# GRANT/REVOKE sem aprovacao (decisao do Orquestrador na F5, tentativa 2; ADR-0040 item 2):
# so privilegio de tabela ou de coluna em saas.* para os papeis da aplicacao. TRUNCATE (ignora
# RLS), TRIGGER, ALL (inclui os dois), PUBLIC, papel, WITH GRANT OPTION, GRANTED BY, CASCADE,
# EXECUTE em funcao, ALL TABLES IN SCHEMA e qualquer objeto fora de saas.* exigem aprovacao.
PAPEIS_DA_APLICACAO = {"saas_app", "saas_jobs", "saas_auth"}

# Classificacao das tabelas (ADR-0040 item 2a): lida do arquivo ao lado deste script, isto e,
# no CI, da copia da branch base (item 8), nunca da copia do PR.
ARQUIVO_CLASSIFICACAO = os.path.join(os.path.dirname(os.path.abspath(__file__)), "tabelas-sensiveis.txt")
# Sensiveis no minimo, qualquer que seja o conteudo da lista (spec 3.5): uma linha
# "nao_sensivel paciente" na lista nao libera GRANT em saas.paciente.
SENSIVEIS_MINIMAS = frozenset({
    "paciente", "paciente_clinica", "encaminhamento", "vaga_encaminhamento", "agendamento",
    "contrarreferencia", "envio_notificacao", "evento_auditoria", "historico_status_encaminhamento",
    "link_paciente", "sessao", "desafio_encaminhador", "consentimento", "anexo_encaminhamento",
    "usuario", "usuario_clinica", "profissional_clinica", "flag_clinica",
})
TABELAS_SENSIVEIS = set(SENSIVEIS_MINIMAS)
TABELAS_NAO_SENSIVEIS = set()
_NOME_TABELA = re.compile(r"^[a-z_][a-z0-9_]*$")


def le_classificacao(caminho):
    """Linhas 'sensivel <tabela>' ou 'nao_sensivel <tabela>'; '#' inicia comentario."""
    sens, nao = set(), set()
    if not os.path.exists(caminho):
        print("guarda: classificacao de tabelas ausente (%s): toda tabela e sensivel" % caminho)
        return sens, nao
    with open(caminho, "r", encoding="utf-8") as f:
        for num, linha in enumerate(f, 1):
            linha = linha.split("#", 1)[0].strip()
            if not linha:
                continue
            partes = linha.split()
            if len(partes) != 2 or partes[0] not in ("sensivel", "nao_sensivel") \
                    or not _NOME_TABELA.match(partes[1]):
                raise ValueError("linha %d invalida ('sensivel <tabela>' ou 'nao_sensivel <tabela>')" % num)
            (sens if partes[0] == "sensivel" else nao).add(partes[1])
    if sens & nao:
        raise ValueError("tabela classificada nas duas classes: %s" % ", ".join(sorted(sens & nao)))
    return sens, nao
PRIVILEGIOS_DE_TABELA = {"select", "insert", "update", "delete", "references"}


def _grant_fora_da_lista(st):
    """None se o GRANT/REVOKE e de tabela/coluna em saas.* para papel da aplicacao."""
    k = [_kw(t) for t in st]
    n = len(st)
    motivo = "%s fora da lista (so privilegio de tabela ou coluna em saas.* para %s)" % (
        (k[0] or "?").upper(), ", ".join(sorted(PAPEIS_DA_APLICACAO)))
    if k[0] not in ("grant", "revoke") or "on" not in k:
        return motivo
    on = k.index("on")
    privs = _partes_virgula(st, 1, on)
    for pv in privs:
        if not pv or pv[0].tipo != "word":
            return motivo
        w = pv[0].valor
        if k[0] == "revoke" and w == "all" and len(privs) == 1:
            resto = pv[2:] if len(pv) > 1 and _kw(pv[1]) == "privileges" else pv[1:]
            if resto:
                return motivo
            continue
        if w not in PRIVILEGIOS_DE_TABELA:
            return motivo
        if len(pv) > 1:
            # lista de colunas: (a, b)
            if not (_eh_op(pv[1], "(") and _fecha(pv, 1) == len(pv)
                    and all(t.tipo in ("word", "qident") or _eh_op(t, ",") for t in pv[2:-1])):
                return motivo
    j = _pula(st, on + 1, "table")
    destino = "to" if k[0] == "grant" else "from"
    if destino not in k[j:]:
        return motivo
    d = j + k[j:].index(destino)
    for obj in _partes_virgula(st, j, d):
        partes, fim = _nome_em(obj, 0)
        if partes is None or fim != len(obj) or len(partes) != 2 or partes[0] != SCHEMA_PERMITIDO:
            return "%s em objeto fora de saas.* (use o nome qualificado saas.tabela)" % k[0].upper()
        # ADR-0040 item 2a: GRANT sem aprovacao so em tabela classificada como nao sensivel na
        # lista da branch base; tabela sensivel ou ainda nao classificada exige aprovacao.
        # REVOKE so reduz acesso: passa em qualquer tabela de saas.*.
        if k[0] == "grant" and any(t.tipo == "qident" for t in obj):
            # o analisador guarda nomes entre aspas em minusculas: "Especialidade" nao e a
            # tabela especialidade, e nao da para saber qual e
            return "GRANT em tabela com nome entre aspas (saas.%s), exige aprovacao" % partes[1]
        if k[0] == "grant" and partes[1] not in TABELAS_NAO_SENSIVEIS:
            if partes[1] in TABELAS_SENSIVEIS:
                return "GRANT em tabela sensivel (saas.%s), exige aprovacao" % partes[1]
            return "GRANT em tabela nao classificada (saas.%s), sensivel por padrao ate entrar em %s" % (
                partes[1], os.path.basename(ARQUIVO_CLASSIFICACAO))
    fim = n
    if k[0] == "revoke" and k[-1] == "restrict":
        fim = n - 1
    for papel in _partes_virgula(st, d + 1, fim):
        if len(papel) != 1 or papel[0].tipo != "word" or papel[0].valor not in PAPEIS_DA_APLICACAO:
            return motivo
    return None


def _fora_da_lista(st):
    """None se o comando de primeiro nivel e permitido sem aprovacao; senao o motivo."""
    k = [_kw(t) for t in st]
    n = len(st)
    desc = " ".join(x.upper() for x in k[:3] if x) or "comando"
    motivo = "fora da lista de construcoes permitidas sem aprovacao (%s)" % desc

    def fim_ok(j):
        return j == n

    w0 = k[0]
    # SET ROLE saas_owner / RESET ROLE / SET [LOCAL] search_path / parametros inofensivos
    if w0 == "reset" and k[1:] == ["role"]:
        return None
    if w0 == "set":
        j = 1
        if j < n and k[j] in ("local", "session"):
            j += 1
        if j < n and k[j] == "role" and j + 2 == n and st[j + 1].tipo in ("word", "qident", "str") \
                and st[j + 1].valor == PAPEL_DE_MIGRACAO:
            return None
        if j < n and k[j] in ("search_path",) and j + 1 < n and (k[j + 1] == "to" or _eh_op(st[j + 1], "=")):
            itens = _partes_virgula(st, j + 2, n)
            if all(len(it) == 1 and it[0].tipo in ("word", "qident", "str")
                   and it[0].valor in SEARCH_PATH_PERMITIDO for it in itens):
                return None
            return "SET search_path fora de %s" % sorted(SEARCH_PATH_PERMITIDO)
        if j < n and k[j] in PARAMETROS_SET_PERMITIDOS and j + 1 < n \
                and (k[j + 1] == "to" or _eh_op(st[j + 1], "=")) and j + 3 == n \
                and st[j + 2].tipo in ("num", "str", "word"):
            return None
        return motivo

    if w0 in ("grant", "revoke"):
        return _grant_fora_da_lista(st)

    bloqueio = _conteudo_comum(st)

    if w0 == "create":
        j = 1
        if j < n and k[j] == "table":
            j += 1
            j = _pula(st, j, "if", "not", "exists")
            partes, j = _nome_em(st, j)
            if not _alvo_saas(partes):
                return "DDL fora do schema saas (%s)" % ".".join(partes or ["?"])
            if j >= n or not _eh_op(st[j], "("):
                return motivo + ": CREATE TABLE sem lista de colunas (AS, PARTITION OF, OF tipo)"
            j = _fecha(st, j)
            if j is not None and j < n and k[j] == "with" and j + 1 < n and _eh_op(st[j + 1], "("):
                j = _fecha(st, j + 1)
            if j is None or not fim_ok(j):
                return motivo + ": CREATE TABLE com clausula apos as colunas (INHERITS, PARTITION BY...)"
            return bloqueio
        if j < n and k[j] in ("unique", "index"):
            j = _pula(st, j, "unique")
            if j >= n or k[j] != "index":
                return motivo
            j = _pula(st, j + 1, "concurrently")
            j = _pula(st, j, "if", "not", "exists")
            if j < n and k[j] != "on":
                j += 1  # nome do indice (sem schema)
            if j >= n or k[j] != "on":
                return motivo
            j = _pula(st, j + 1, "only")
            partes, j = _nome_em(st, j)
            if not _alvo_saas(partes):
                return "DDL fora do schema saas (%s)" % ".".join(partes or ["?"])
            return bloqueio
        if j < n and k[j] == "sequence":
            j = _pula(st, j + 1, "if", "not", "exists")
            partes, j = _nome_em(st, j)
            if not _alvo_saas(partes):
                return "DDL fora do schema saas (%s)" % ".".join(partes or ["?"])
            return bloqueio
        if j < n and k[j] == "type":
            partes, j = _nome_em(st, j + 1)
            if not _alvo_saas(partes):
                return "DDL fora do schema saas (%s)" % ".".join(partes or ["?"])
            if k[j:j + 2] == ["as", "enum"] and j + 2 < n and _eh_op(st[j + 2], "("):
                fim = _fecha(st, j + 2)
                if fim == n and all(t.tipo == "str" or _eh_op(t, ",") for t in st[j + 3:fim - 1]):
                    return None
            return motivo
        return motivo

    if w0 == "alter":
        if n > 1 and k[1] == "table":
            j = _pula(st, 2, "if", "exists")
            j = _pula(st, j, "only")
            partes, j = _nome_em(st, j)
            if not _alvo_saas(partes):
                return "DDL fora do schema saas (%s)" % ".".join(partes or ["?"])
            for acao in _partes_virgula(st, j, n):
                eh_default, coluna = _default_em_coluna(acao)
                if eh_default:
                    if PADRAO_COLUNA_PROTEGIDA.search(coluna.lower()):
                        return ("SET/DROP DEFAULT em coluna de tenant, chave, storage ou status "
                                "(%s) exige aprovacao" % coluna)
                    continue
                if not _acao_alter_table(acao):
                    d = " ".join(x.valor.upper() for x in acao[:4] if x.tipo == "word") or "?"
                    return motivo + ": acao de ALTER TABLE fora da lista (%s)" % d
            return bloqueio
        if n > 1 and k[1] == "index":
            j = _pula(st, 2, "if", "exists")
            partes, j = _nome_em(st, j)
            if _alvo_saas(partes) and k[j:j + 2] == ["rename", "to"] and j + 3 == n:
                return bloqueio
            return motivo
        if n > 1 and k[1] == "type":
            partes, j = _nome_em(st, 2)
            if not _alvo_saas(partes):
                return "DDL fora do schema saas (%s)" % ".".join(partes or ["?"])
            if k[j:j + 2] == ["add", "value"]:
                j = _pula(st, j + 2, "if", "not", "exists")
                if j < n and st[j].tipo == "str":
                    j += 1
                    if j < n and k[j] in ("before", "after") and j + 1 < n and st[j + 1].tipo == "str":
                        j += 2
                    if j == n:
                        return None
            return motivo
        return motivo

    # DROP INDEX e DROP CONSTRAINT exigem aprovacao (ADR-0040 item 2b): indice unico e
    # restricao sao regra de negocio ou de seguranca.
    if w0 == "drop" and n > 1 and k[1] == "index":
        return "DROP INDEX exige aprovacao (indice unico e regra de negocio/seguranca)"

    if w0 == "comment" and n > 2 and k[1] == "on" and k[2] in ("table", "column", "index", "sequence", "type"):
        partes, j = _nome_em(st, 3)
        if partes is None:
            return motivo
        if k[2] == "column":
            ok = len(partes) == 2 or (len(partes) == 3 and partes[0] == SCHEMA_PERMITIDO)
        else:
            ok = _alvo_saas(partes)
        if not ok:
            return "DDL fora do schema saas (%s)" % ".".join(partes)
        if k[j:j + 1] == ["is"] and j + 2 == n and (st[j + 1].tipo == "str" or k[j + 1] == "null"):
            return None  # o literal e dado (e ainda passa pela reanalise)
        return motivo

    if w0 == "insert" and n > 1 and k[1] == "into":
        partes, j = _nome_em(st, 2)
        if not _alvo_saas(partes):
            return "DDL fora do schema saas (%s)" % ".".join(partes or ["?"])
        if partes[-1] not in TABELAS_REFERENCIA:
            return motivo + ": INSERT fora das tabelas de referencia %s" % sorted(TABELAS_REFERENCIA)
        if j < n and _eh_op(st[j], "("):
            j = _fecha(st, j)
        if j is None or j >= n or k[j] != "values":
            return motivo + ": INSERT sem VALUES"
        j += 1
        while j is not None and j < n and _eh_op(st[j], "("):
            j = _fecha(st, j)
            if j is not None and j < n and _eh_op(st[j], ","):
                j += 1
        if j is not None and j < n and k[j:j + 2] == ["on", "conflict"]:
            j += 2
            if j < n and _eh_op(st[j], "("):
                j = _fecha(st, j)
            if j is not None and k[j:j + 2] == ["do", "nothing"]:
                j += 2
        if j != n:
            return motivo + ": INSERT com clausula fora da lista (ON CONFLICT DO UPDATE, RETURNING...)"
        return bloqueio

    return motivo


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

        # --- quem acessa o que e como a seguranca e avaliada (ADR-0040, item 2) ---
        if w in ("create", "alter", "drop"):
            j = i + 1
            if _seq(st, j, "or", "replace"):
                j += 2
            while _palavra(st[j] if j < n else None) in ("temp", "temporary", "recursive", "materialized",
                                                          "trusted", "procedural", "unique"):
                j += 1
            obj = _palavra(st[j]) if j < n else None
            if obj in ("function", "procedure", "routine", "aggregate"):
                acha(t.linha, "%s %s (muda codigo usado por politica, gatilho ou papel)" % (w.upper(), obj.upper()))
            elif obj in ("role", "user", "group"):
                acha(t.linha, "%s %s (papel e atributos)" % (w.upper(), obj.upper()))
            elif obj == "view":
                acha(t.linha, "%s VIEW (visao contorna ou muda a RLS)" % w.upper())
            elif obj == "extension":
                acha(t.linha, "%s EXTENSION" % w.upper())
            elif obj in ("schema", "database", "server", "language", "cast", "operator", "publication",
                         "subscription", "tablespace", "conversion", "collation", "statistics",
                         "transform", "access"):
                acha(t.linha, "%s %s" % (w.upper(), obj.upper()))
            elif obj == "foreign":
                acha(t.linha, "%s FOREIGN ..." % w.upper())
            elif obj == "default" and _seq(st, j + 1, "privileges"):
                acha(t.linha, "ALTER DEFAULT PRIVILEGES")
        if w in ("grant", "revoke") and not (not aninhado and i == 0 and _grant_fora_da_lista(st) is None):
            acha(t.linha, "%s (privilegios)" % w.upper())
        if w == "public" and i > 0 and palavras[i - 1] in ("to", "from") and t.tipo == "word":
            acha(t.linha, "privilegio TO/FROM PUBLIC")
        if w == "security" and _seq(st, i + 1, ("definer", "invoker")):
            acha(t.linha, "SECURITY %s" % palavras[i + 1].upper())
        if w == "security" and _seq(st, i + 1, "label"):
            acha(t.linha, "SECURITY LABEL")
        if w == "owner" and _seq(st, i + 1, "to"):
            acha(t.linha, "OWNER TO (troca o dono)")
        if w == "reassign" and _seq(st, i + 1, "owned"):
            acha(t.linha, "REASSIGN OWNED")
        if w in ("set", "reset"):
            j = i + 1
            if _palavra(st[j] if j < n else None) in ("local", "session") and not _seq(st, j, "session", "authorization"):
                j += 1
            alvo_set = _palavra(st[j]) if j < n else None
            if alvo_set == "session" and _seq(st, j + 1, "authorization"):
                acha(t.linha, "%s SESSION AUTHORIZATION" % w.upper())
            elif alvo_set == "role" and w == "set":
                papel = st[j + 1].valor if j + 1 < n and st[j + 1].tipo in ("word", "qident", "str") else None
                if papel != PAPEL_DE_MIGRACAO:
                    acha(t.linha, "SET ROLE %s (papel diferente de %s)" % (papel, PAPEL_DE_MIGRACAO))
            elif alvo_set is not None and w == "set" and j + 1 < n and (
                    _palavra(st[j + 1]) == "to" or _eh_op(st[j + 1], "=") or _eh_op(st[j + 1], ".")):
                nome = alvo_set
                if _eh_op(st[j + 1], ".") and j + 2 < n:
                    nome = alvo_set + "." + (st[j + 2].valor or "")
                if _parametro_de_seguranca(nome) and nome != "search_path":
                    acha(t.linha, "SET %s (parametro de seguranca)" % nome)
        if w == "set_config" and i + 2 < n and _eh_op(st[i + 1], "(") and st[i + 2].tipo == "str" \
                and _parametro_de_seguranca(st[i + 2].valor):
            acha(t.linha, "set_config('%s') (parametro de seguranca)" % st[i + 2].valor)
        if w == "copy" and t.tipo == "word":
            acha(t.linha, "COPY (PROGRAM, arquivo do servidor ou carga de dados)")
        if w == "program" and t.tipo == "word":
            acha(t.linha, "PROGRAM (executa comando do sistema)")
        if w == "load" and t.tipo == "word" and i + 1 < n and st[i + 1].tipo == "str":
            acha(t.linha, "LOAD (carrega biblioteca)")
        if w in ("lo_import", "lo_export", "pg_read_file", "pg_read_binary_file", "pg_ls_dir",
                 "pg_stat_file", "pg_file_write") and i + 1 < n and _eh_op(st[i + 1], "("):
            acha(t.linha, "funcao de arquivo do servidor (%s)" % w)

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


def _tabela_criada(st):
    """Nome da tabela de saas.* (ou sem schema) criada por um CREATE ... TABLE de qualquer
    forma (colunas, LIKE, AS SELECT, PARTITION OF, OF tipo, TEMP, UNLOGGED); senao None."""
    k = [_kw(t) for t in st]
    if not k or k[0] != "create":
        return None
    j = 1
    while j < len(k) and k[j] in ("or", "replace", "global", "local", "temp", "temporary", "unlogged"):
        j += 1
    if j >= len(k) or k[j] != "table":
        return None
    j = _pula(st, j + 1, "if", "not", "exists")
    partes, fim = _nome_em(st, j)
    if partes is None:
        return None
    if len(partes) == 1 or (len(partes) == 2 and partes[0] == SCHEMA_PERMITIDO):
        if fim >= 1 and st[fim - 1].tipo == "qident":
            # nome entre aspas e guardado em minusculas: "N" e n seriam confundidos no
            # confronto com o ALTER TABLE; marca como sem RLS conferivel
            return '"%s"' % partes[-1]
        return partes[-1]
    return None


def _rls_ligada(st):
    """Tabelas (nome sem schema) e acoes de RLS de um ALTER TABLE: (nome, {'enable','force'})."""
    k = [_kw(t) for t in st]
    if len(k) < 3 or k[0] != "alter" or k[1] != "table":
        return None, set()
    j = _pula(st, 2, "if", "exists")
    j = _pula(st, j, "only")
    partes, j = _nome_em(st, j)
    if not _alvo_saas(partes):
        return None, set()
    acoes = set()
    for acao in _partes_virgula(st, j, len(st)):
        a = [_kw(t) for t in acao]
        if a in (["enable", "row", "level", "security"], ["force", "row", "level", "security"]):
            acoes.add(a[0])
    return partes[-1], acoes


def _confere_rls_das_tabelas_novas(stmts, achados):
    """ADR-0040 item 2c: toda tabela criada em saas.* tem ENABLE e FORCE ROW LEVEL SECURITY
    em comando de primeiro nivel posterior, na mesma migracao."""
    for i, st in enumerate(stmts):
        nome = _tabela_criada(st)
        if nome is None:
            continue
        visto = set()
        for depois in stmts[i + 1:]:
            alvo, acoes = _rls_ligada(depois)
            if alvo == nome:
                visto |= acoes
        falta = {"enable", "force"} - visto
        if falta:
            achados.append((st[0].linha, "CREATE TABLE saas.%s sem %s ROW LEVEL SECURITY na mesma migracao" % (
                nome, " e ".join(x.upper() for x in sorted(falta)))))


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
    stmts = _divide(toks)
    for st in stmts:
        _regras_comando(st, aninhado, achados)
        if not aninhado:
            motivo = _fora_da_lista(st)
            if motivo:
                achados.append((st[0].linha, motivo))
    if not aninhado:
        _confere_rls_das_tabelas_novas(stmts, achados)
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
    try:
        sens, nao = le_classificacao(ARQUIVO_CLASSIFICACAO)
    except (ValueError, UnicodeDecodeError) as e:
        print("guarda: classificacao de tabelas invalida: %s" % e, file=sys.stderr)
        return 2
    TABELAS_SENSIVEIS.update(sens)
    TABELAS_NAO_SENSIVEIS.update(nao - SENSIVEIS_MINIMAS)

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
              "'<sha256>  <arquivo>' em src/main/resources/db/aprovacoes.sha256, com aprovacao do dono "
              "(CODEOWNERS)." % recusadas)
        return 1
    print("guarda: %d arquivo(s) conferido(s), nenhum recusado." % len(arquivos))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
