#!/usr/bin/env bash
# Gera os goldens normalizados das baterias impressas executando-as contra docs/arquitetura/modelo-v2.sql
# aplicado direto (forma da Fase 1). Rodado pelo Arquiteto ao criar os testes; o resultado tem checksum.
# Uso: bash acceptance/regressao/gera-golden.sh [diretorio_saida]   (padrao: acceptance/regressao/golden)
set -u
ACC="$(cd "$(dirname "$0")/.." && pwd)"; source "$ACC/lib/comum.sh"; source "$ACC/regressao/regressao.sh"
SAIDA=${1:-$ACC/regressao/golden}; mkdir -p "$SAIDA"
LOGF=/dev/null
pg_sobe golden || exit 1
trap pg_desce EXIT
$PSU -d postgres -c "create database ref" && $PSU -d ref -v ON_ERROR_STOP=1 -f "$RAIZ/docs/arquitetura/modelo-v2.sql" >/dev/null 2>&1 || { echo "modelo-v2 falhou"; exit 1; }
roda_regressao ref
for b in rtn rt2; do python3 "$REGPY" normaliza "$REG_LOG/$b.out" "$SAIDA/$b.norm"; done
for b in rls indep1 indep2 sondas_r2 rt1; do cut -f1 "$REG_LOG/$b.res" | awk '!v[$0]++' > "$SAIDA/$b.sondas"; done
$PSU -d ref -Atc "select distinct proname from pg_proc where pronamespace='saas'::regnamespace order by 1" > "$SAIDA/funcoes-modelo-v2.txt"
$PSU -d ref -Atc "select table_name||'|'||column_name||'|'||data_type from information_schema.columns where table_schema='saas' order by 1" > "$SAIDA/colunas-modelo-v2.txt"
$PSU -d ref -Atc "select c.relname||'|'||t.tgname from pg_trigger t join pg_class c on c.oid=t.tgrelid where c.relnamespace='saas'::regnamespace and not t.tgisinternal order by 1" > "$SAIDA/gatilhos-modelo-v2.txt"
for b in $REG_BATERIAS; do echo "$b: ${REG_RES[$b]}"; done
