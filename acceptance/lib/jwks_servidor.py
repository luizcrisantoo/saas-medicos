#!/usr/bin/env python3
"""JWKS local para os testes de aceite. Uso: jwks_servidor.py PORTA DIR
Gera k1 (publicada) e k2 (nunca publicada), grava os PEM privados em DIR e serve /jwks.json so com k1."""
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from aceite_http import Chave, serve_jwks  # noqa: E402

porta, d = int(sys.argv[1]), sys.argv[2]
os.makedirs(d, exist_ok=True)
k1, k2 = Chave("aceite-k1"), Chave("aceite-k2")
k1.salva(os.path.join(d, "k1.pem"))
k2.salva(os.path.join(d, "k2.pem"))
open(os.path.join(d, "k1.pub.pem"), "wb").write(k1.pem_publico())
serve_jwks(porta, [k1])
open(os.path.join(d, "pronto"), "w").write("ok")
while True:
    time.sleep(3600)
