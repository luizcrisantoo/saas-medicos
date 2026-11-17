# shellcheck shell=bash
# Regressao da Fase 1 contra o banco migrado pelo Flyway (bootstrap + db/migration do Executor).
# Baterias: as versoes -r2 atuais (docs/fase1-resumo.md, secao 5 e 6). Nenhuma e alterada:
# as unicas adaptacoes sao de infraestrutura (socket/porta/nome do banco, como na Fase 1), a
# semente I-22 (_reg_semente: so acrescenta telefone_contato aos casos da semente de rls, indep1 e
# indep2; nenhuma sonda muda, conferido por regressao.py) e a lista de sondas NEUTRAS abaixo, cujo resultado depende de um gate da Fase 2 (o gate e conferido
# pelas sondas novas de F3/F4, com esperado invertido). Fonte das sondas neutras: docs/fase2/spec.md, secao 6.
#
# Uso (fonte): roda_regressao TEMPLATE  -> define REG_RES[bateria]=ok|motivo e REG_LOG
EV="$RAIZ/docs/arquitetura/evidencias"
SEG="$RAIZ/docs/seguranca/evidencias"
REGPY="$ACC/regressao/regressao.py"
GOLD="$ACC/regressao/golden"

# Sondas neutras das baterias de tabela: golden/<bateria>.neutras (uma por linha, com o motivo em comentario).
# blocos das baterias impressas (golden), por gate: E-10 (N3c,N3e), I-21 (N11a), O3 (N11d),
# T-20 (R2N1, R2N3), I-22 (R2N2), I-23 (R2N5), R-08 (R2N9).
# N1f (membros de papeis saas_*): o papel de pipeline saas_migracao precisa assumir saas_owner e
# saas_funcoes (ADR-0027, "papel de pipeline que assume saas_owner so durante a migracao"); a
# regra que N1f protegia (nenhum papel de LOGIN da aplicacao assume outro) e conferida em F2.5.
# N1e (lista nominal das funcoes SECURITY DEFINER executaveis pela web): muda com qualquer funcao nova
# ou com I-21; as regras gerais (search_path fixo, nada para PUBLIC) estao em N1a, N1c e F2.6.
# N11c (transicao_cancelamento com linha forjada): a linha literal depende do numero de colunas de
# encaminhamento (I-22 pode acrescentar coluna); a mesma sonda com linha real esta em F4.2.
NEUTROS_RTN="N1e,N1f,N3c,N3e,N11a,N11c,N11d"
NEUTROS_RT2="R2N1,R2N2,R2N3,R2N5,R2N9"

declare -A REG_RES=()
REG_BATERIAS="rls indep1 indep2 sondas_r2 rt1 rtn rt2"

_reg_db() { # nome template
  $PSU -d postgres -c "drop database if exists $1" >/dev/null 2>&1
  $PSU -d postgres -c "create database $1 template $2" >/dev/null
}
_reg_falhas_tabela() { # db consulta(chave<TAB>ok) bateria -> sondas esperadas (golden) ausentes ou com falha, exceto neutras
  local db=$1 q=$2 bat=$3
  $PSU -d "$db" -At -F $'\t' -c "$q" >"$REG_LOG/$bat.res" 2>/dev/null
  python3 "$REGPY" tabela "$GOLD/$bat.sondas" "$GOLD/$bat.neutras" "$REG_LOG/$bat.res" "$GOLD/funcoes-modelo-v2.txt" "$REG_LOG/tabelas-novas.txt"
}

_reg_copia_sem_stop() { # arquivo destino : mesma bateria com \set ON_ERROR_STOP off (uma sonda que muda de
  # comportamento por gate nao derruba as demais; sonda que deixa de rodar aparece como AUSENTE)
  sed -e 's/^\\set ON_ERROR_STOP on/\\set ON_ERROR_STOP off/' "$1" >"$2"
}
_reg_semente() { # bateria arquivo(adaptado no lugar) : semente I-22 (telefone_contato do caso), docs/fase2/spec.md secao 6.
  # So acrescimo, nunca em sonda: regressao.py recusa outra coisa; o diff fica em $REG_LOG/<bateria>.semente.diff.
  python3 "$REGPY" semente "$1" "$2" "$2.sem" "$REG_LOG/$1.semente.diff" && mv "$2.sem" "$2"
}

roda_regressao() { # template
  local tpl=$1 out falhas rc sf
  REG_LOG="$TMPA/regressao"; mkdir -p "$REG_LOG"
  comm -23 <($PSU -d "$tpl" -Atc "select relname from pg_class where relnamespace='saas'::regnamespace and relkind in ('r','p')" | sort -u) \
           <(cut -d'|' -f1 "$GOLD/colunas-modelo-v2.txt" | sort -u) >"$REG_LOG/tabelas-novas.txt"
  # 1. teste-rls-r2.sql (Executor, inclui a matriz de 392 sondas)
  _reg_db rls "$tpl"; out="$REG_LOG/rls.out"
  _reg_copia_sem_stop "$EV/teste-rls-r2.sql" "$REG_LOG/rls.sql"; sf=$(_reg_semente rls "$REG_LOG/rls.sql") || sf="semente recusada: ${sf:-erro}"; $PSU -d rls -f "$REG_LOG/rls.sql" >"$out" 2>&1; rc=$?
  falhas=$(_reg_falhas_tabela rls "select secao||': '||nome||' ['||coalesce(ctx,'')||']', coalesce(ok,true) from teste_aux.res order by n" rls)
  if [ -n "$sf" ]; then REG_RES[rls]="$sf"
  elif [ $rc -ne 0 ]; then REG_RES[rls]="psql exit=$rc (ver $out)"
  elif [ -n "$falhas" ]; then REG_RES[rls]="falhas: $(echo "$falhas" | head -3 | tr '\n' ';')"
  elif ! grep -q "tabelas alteradas apos todas as sondas: 0" "$out"; then REG_RES[rls]="integridade: sondas persistiram mudanca"
  else REG_RES[rls]=ok; fi
  # 2. teste-r1-independente-r2.sql (Testador r1, copia r2)
  _reg_db indep1 "$tpl"; out="$REG_LOG/indep1.out"
  _reg_copia_sem_stop "$EV/teste-r1-independente-r2.sql" "$REG_LOG/indep1.sql"; sf=$(_reg_semente indep1 "$REG_LOG/indep1.sql") || sf="semente recusada: ${sf:-erro}"; $PSU -d indep1 -f "$REG_LOG/indep1.sql" >"$out" 2>&1; rc=$?
  falhas=$(_reg_falhas_tabela indep1 "select secao||': '||nome||' ['||coalesce(ctx,'')||']', coalesce(ok,true) from t.res order by n" indep1)
  if [ -n "$sf" ]; then REG_RES[indep1]="$sf"
  elif [ $rc -ne 0 ]; then REG_RES[indep1]="psql exit=$rc (ver $out)"
  elif [ -n "$falhas" ]; then REG_RES[indep1]="falhas: $(echo "$falhas" | head -3 | tr '\n' ';')"
  else REG_RES[indep1]=ok; fi
  # 3. teste-r2-independente.sql (Testador r2)
  _reg_db indep2 "$tpl"; out="$REG_LOG/indep2.out"
  _reg_copia_sem_stop "$EV/teste-r2-independente.sql" "$REG_LOG/indep2.sql"; sf=$(_reg_semente indep2 "$REG_LOG/indep2.sql") || sf="semente recusada: ${sf:-erro}"; $PSU -d indep2 -f "$REG_LOG/indep2.sql" >"$out" 2>&1; rc=$?
  falhas=$(_reg_falhas_tabela indep2 "select secao||': '||nome||' ['||coalesce(ctx,'')||']', coalesce(ok,true) from t.res order by n" indep2)
  if [ -n "$sf" ]; then REG_RES[indep2]="$sf"
  elif [ $rc -ne 0 ]; then REG_RES[indep2]="psql exit=$rc (ver $out)"
  elif [ -n "$falhas" ]; then REG_RES[indep2]="falhas: $(echo "$falhas" | head -3 | tr '\n' ';')"
  else REG_RES[indep2]=ok; fi
  # 4. sondas-r2.sql (Executor r2: R2-1 a R2-7)
  _reg_db r2 "$tpl"; out="$REG_LOG/sondas_r2.out"
  _reg_copia_sem_stop "$EV/sondas-r2.sql" "$REG_LOG/sondas_r2.sql"; PGHOST=$PGDIR PGPORT=$PGPORTA $PSU -d r2 -v dir="$PGDIR" -v porta="$PGPORTA" -f "$REG_LOG/sondas_r2.sql" >"$out" 2>&1; rc=$?
  falhas=$(_reg_falhas_tabela r2 "select id||' '||descricao||' ['||coalesce(papel,'')||']', coalesce(ok,true) from r2.res order by n" sondas_r2)
  if [ $rc -ne 0 ]; then REG_RES[sondas_r2]="psql exit=$rc (ver $out)"
  elif [ -n "$falhas" ]; then REG_RES[sondas_r2]="falhas: $(echo "$falhas" | head -3 | tr '\n' ';')"
  else REG_RES[sondas_r2]=ok; fi
  $PSU -d postgres -c "drop database if exists r2" >/dev/null 2>&1
  # 5. red-team-sondas-r1.sql (RT1 a RT10)
  _reg_db rt1 "$tpl"; out="$REG_LOG/rt1.out"
  $PSU -d rt1 -f "$SEG/red-team-sondas-r1.sql" >"$out" 2>&1; rc=$?
  falhas=$(_reg_falhas_tabela rt1 "select id||' '||descricao||' ['||coalesce(papel,'')||']', ((id like 'CTRL%') <> negado) from rt_aux.res order by n" rt1)
  local nres; nres=$($PSU -d rt1 -Atc "select count(*) from rt_aux.res" 2>/dev/null || echo 0)
  if [ $rc -ne 0 ]; then REG_RES[rt1]="psql exit=$rc (ver $out)"
  elif [ "${nres:-0}" -lt 28 ]; then REG_RES[rt1]="bateria incompleta: $nres de 28 sondas"
  elif [ -n "$falhas" ]; then REG_RES[rt1]="falhas: $(echo "$falhas" | head -3 | tr '\n' ';')"
  else REG_RES[rt1]=ok; fi
  # 6. red-team-sondas-r1-novas.sql (N1 a N12), comparada ao golden do modelo-v2
  _reg_db rt "$tpl"; out="$REG_LOG/rtn.out"
  sed -e "s#/home/claude/saas-agenda/.pgrt#$PGDIR#g" -e "s#-p 5495#-p $PGPORTA#g" "$SEG/red-team-sondas-r1-novas.sql" >"$REG_LOG/novas.sql"
  $PSU -d rt -f "$REG_LOG/novas.sql" >"$out" 2>&1; rc=$?
  python3 "$REGPY" normaliza "$out" "$out.norm"
  if [ $rc -ne 0 ]; then REG_RES[rtn]="psql exit=$rc (ver $out)"
  elif ! python3 "$REGPY" compara "$GOLD/rtn.norm" "$out.norm" "$NEUTROS_RTN" >"$out.diff" 2>&1; then REG_RES[rtn]="saida difere do modelo-v2 fora dos blocos de gate (ver $out.diff)"
  else REG_RES[rtn]=ok; fi
  $PSU -d postgres -c "drop database if exists rt" >/dev/null 2>&1
  # 7. red-team-sondas-r2.sql (R2N1 a R2N9), comparada ao golden do modelo-v2
  _reg_db r2 "$tpl"; out="$REG_LOG/rt2.out"
  $PSU -d r2 -f "$SEG/red-team-sondas-r2.sql" >"$out" 2>&1; rc=$?
  python3 "$REGPY" normaliza "$out" "$out.norm"
  if [ $rc -ne 0 ]; then REG_RES[rt2]="psql exit=$rc (ver $out)"
  elif ! python3 "$REGPY" compara "$GOLD/rt2.norm" "$out.norm" "$NEUTROS_RT2" >"$out.diff" 2>&1; then REG_RES[rt2]="saida difere do modelo-v2 fora dos blocos de gate (ver $out.diff)"
  else REG_RES[rt2]=ok; fi
  $PSU -d postgres -c "drop database if exists r2" >/dev/null 2>&1
  true
}
