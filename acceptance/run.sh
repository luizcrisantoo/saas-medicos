#!/usr/bin/env bash
# Runner dos testes de aceite da Fase 2 (Operacao v2). Escrito pelo Arquiteto; o Executor nao altera
# nada em acceptance/ (checksum em docs/fase2/progresso.md).
#
# Uso:
#   acceptance/run.sh F<n>        roda os criterios da feature n (1 a 12)
#   acceptance/run.sh regressao   so a regressao das baterias -r2 (criterio F2.9)
#   acceptance/run.sh all         todas as features, em ordem
# Saida: uma linha VERDE/VERMELHO por criterio e o resumo. Codigo de saida 0 so se tudo VERDE.
# Requisitos do ambiente: root (o PostgreSQL efemero roda como usuario pgtest), Java 21, gradle 8.14.3
# para o harness, PostgreSQL 16 em /usr/lib/postgresql/16/bin, python3 com cryptography, docker para
# os testes Testcontainers do proprio Executor. Ferramentas fixadas: acceptance/ferramentas.sh.
set -u
ACC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export ACC
source "$ACC/lib/comum.sh"
export TESTCONTAINERS_RYUK_DISABLED=true PYTHONDONTWRITEBYTECODE=1

FEATURES="F1 F2 F3 F4 F5 F6 F7 F8 F9 F10 F11 F12"
alvo="${1:-}"
case "$alvo" in
  all) lista=$FEATURES ;;
  regressao) lista=REG ;;
  F[0-9]|F1[0-2]) lista=$alvo ;;
  *) echo "uso: $0 F<n>|regressao|all" >&2; exit 2 ;;
esac

bash "$ACC/ferramentas.sh" >/dev/null 2>&1 || echo "aviso: ferramentas.sh falhou (criterios que dependem delas ficam VERMELHO)" >&2

TOTAL_V=0; TOTAL_R=0
for f in $lista; do
  CONT="$TMPA/.contagem-$f"; rm -f "$CONT"
  (
    N_VERDE=0; N_VERMELHO=0
    if [ "$f" = REG ]; then
      source "$ACC/F2/aceite.sh"; titulo="Regressao das baterias -r2 (parte de F2)"
      echo "== $titulo =="; LOGF="$TMPA/REG.log"; : >"$LOGF"
      aceite_regressao_somente
    else
      source "$ACC/$f/aceite.sh"
      echo "== $f: $TITULO =="
      LOGF="$TMPA/$f.log"; : >"$LOGF"
      aceite
    fi
    imprime_criterios
    echo "$N_VERDE $N_VERMELHO" >"$CONT"
  )
  if [ -f "$CONT" ]; then read -r v r <"$CONT"; else v=0; r=1; echo "VERMELHO  $f       execucao da feature abortou"; fi
  TOTAL_V=$((TOTAL_V+v)); TOTAL_R=$((TOTAL_R+r))
done
echo
echo "RESUMO: $TOTAL_V VERDE, $TOTAL_R VERMELHO"
[ "$TOTAL_R" -eq 0 ] && [ "$TOTAL_V" -gt 0 ]
