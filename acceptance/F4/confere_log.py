#!/usr/bin/env python3
"""Confere no log do servidor os alertas exigidos por F4 (R-08 e volume de preparos, E-09).

Uso: confere_log.py PG_LOG  -> imprime 'ok|falha <id> <detalhe>' por verificacao.
Um alerta e uma linha com o marcador (ALERTA_DDL_SAAS ou ALERTA_PREPARO_VOLUME) que nao e eco de
comando ('statement:'). Para R-08 a linha tem que citar a tabela alvo (saas.<tabela>).
"""
import sys

ALVOS = {
    "R08_A": ("CREATE POLICY", "saas.encaminhamento"),
    "R08_B": ("ALTER POLICY", "saas.encaminhamento"),
    "R08_C": ("CREATE TRIGGER", "saas.paciente"),
    "R08_D": ("DISABLE TRIGGER", "saas.historico_status_encaminhamento"),
    "R08_E": ("NO FORCE ROW LEVEL SECURITY", "saas.consentimento"),
    "R08_F": ("DROP POLICY", "saas.encaminhamento"),
    "R08_G": ("CREATE RULE", "saas.agendamento"),
    "R08_H": ("ALTER POLICY ... RENAME", "saas.encaminhamento"),
}


def segmento(linhas, ini, fim):
    dentro, seg, achou = False, [], False
    for l in linhas:
        if "LOG:  ACEITE_MARCA " + ini in l:
            dentro, achou = True, True
            continue
        if "LOG:  ACEITE_MARCA " + fim in l:
            break
        if dentro:
            seg.append(l)
    return seg if achou else None


def alertas(seg, marcador):
    return [l for l in seg if marcador in l and "statement:" not in l]


def main(arq):
    linhas = open(arq, errors="replace").read().splitlines()
    for k, (ddl, tabela) in ALVOS.items():
        seg = segmento(linhas, k + "_INICIO", k + "_FIM")
        if seg is None:
            print(f"falha {k} marcas ausentes no log")
            continue
        al = [l for l in alertas(seg, "ALERTA_DDL_SAAS") if tabela in l]
        print(("ok " if al else "falha ") + f"{k} {ddl} em {tabela}: {len(al)} alerta(s)")
    s1 = segmento(linhas, "VOL_INICIO", "VOL_19")
    s2 = segmento(linhas, "VOL_19", "VOL_FIM")
    if s1 is None or s2 is None:
        print("falha VOL marcas ausentes no log")
        return
    a1, a2 = alertas(s1, "ALERTA_PREPARO_VOLUME"), alertas(s2, "ALERTA_PREPARO_VOLUME")
    print(("ok " if not a1 else "falha ") + f"VOL_ABAIXO sem alerta ate 19 preparos: {len(a1)}")
    print(("ok " if a2 else "falha ") + f"VOL_ACIMA alerta entre o 20o e o 21o preparo: {len(a2)}")
    vaz = [l for l in a1 + a2 if "988884002" in l]
    print(("ok " if not vaz else "falha ") + f"VOL_SEM_CONTATO alerta sem o telefone do destinatario: {len(vaz)}")


if __name__ == "__main__":
    main(sys.argv[1])
