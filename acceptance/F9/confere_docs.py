#!/usr/bin/env python3
"""F9.7: rascunhos de termos de uso e politica de privacidade, marcados para revisao de advogado.
Uso: confere_docs.py RAIZ -> 'ok|falha F9.7 <detalhe>'."""
import os
import sys
import unicodedata


def norm(t):
    return unicodedata.normalize("NFKD", t).encode("ascii", "ignore").decode().lower()


raiz = sys.argv[1]
MARCA = "RASCUNHO PARA REVISAO DE ADVOGADO"
arqs = {"termos": os.path.join(raiz, "docs/legal/termos-de-uso.md"), "politica": os.path.join(raiz, "docs/legal/politica-de-privacidade.md")}
txt = {}
for k, p in arqs.items():
    if not os.path.isfile(p):
        print(f"falha F9.7 ausente: {p}")
        sys.exit(0)
    txt[k] = norm(open(p, encoding="utf-8", errors="replace").read())
for k, t in txt.items():
    print(("ok" if norm(MARCA) in t[:600] else "falha") + f" F9.7 {k}: marca '{MARCA}' no inicio")
    print(("ok" if "rodrigo" not in t and "luiz" not in t else "falha") + f" F9.7 {k}: sem nome de pessoa real do negocio")
    print(("ok" if "\u2014" not in open(arqs[k], encoding="utf-8").read() else "falha") + f" F9.7 {k}: sem travessao")
pol = txt["politica"]
for termo in ("dado de saude", "sensive", "consentimento", "revoga", "acesso", "corre", "exclus", "encarregado", "retencao", "controlador", "operador"):
    print(("ok" if termo in pol else "falha") + f" F9.7 politica cita '{termo}'")
print(("ok" if pol.count("a definir") >= 2 else "falha") + " F9.7 politica marca como A DEFINIR o que nao foi decidido (retencao, papeis controlador e operador)")
ter = txt["termos"]
for termo in ("mensalidade", "encaminha", "livre", "escolh"):
    print(("ok" if termo in ter else "falha") + f" F9.7 termos cita '{termo}'")
