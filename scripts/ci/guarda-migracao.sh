#!/usr/bin/env bash
# Guarda de migracao (R-07, R-08; ADR-0027, ADR-0039, ADR-0040).
# Uso: scripts/ci/guarda-migracao.sh DIR_MIGRACOES ARQUIVO_APROVACOES
# Sai 0 se toda migracao do diretorio e limpa ou aprovada (sha256 + nome em
# ARQUIVO_APROVACOES); diferente de 0 caso contrario. A analise e de
# guarda_migracao.py (analisador lexico de SQL, nao busca literal de texto).
set -euo pipefail
if [ "$#" -ne 2 ]; then
  echo "uso: $0 DIR_MIGRACOES ARQUIVO_APROVACOES" >&2
  exit 2
fi
aqui="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec python3 -I "$aqui/guarda_migracao.py" "$1" "$2"
