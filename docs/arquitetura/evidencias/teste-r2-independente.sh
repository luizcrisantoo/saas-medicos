#!/usr/bin/env bash
# Testador, rodada 2. Cluster PostgreSQL 16 SEU: .pgtest3, porta 5493, usuario nao-root pgtest.
# Parte A: bateria completa do Executor (copia do runner da rodada 1 com DIR/PORTA trocados e o .sql -r2).
# Parte B: modelo-v2.sql do zero; (1) teste-rls-r2.sql; (2) teste-rls-r1.sql SEM ajuste; (3) teste-r1-independente.sql
#          ORIGINAL (rodada 1, nao adaptado) so para listar o que mudou; (4) teste-r2-independente.sql
#          (3 falhas originais na forma original + sondas novas N1..N3); (5) sondas-r2.sql do Executor;
#          (6) corrida real: prepara de envio x cancelamento em duas conexoes. Desliga ao fim.
# Uso (root): bash docs/arquitetura/evidencias/teste-r2-independente.sh  -> grava teste-r2-independente.log
set -u
RAIZ=/home/claude/saas-agenda; PGBIN=/usr/lib/postgresql/16/bin; DIR=$RAIZ/.pgtest3; PORTA=5493
EV=$RAIZ/docs/arquitetura/evidencias; SEG=$RAIZ/docs/seguranca/evidencias; LOG=$EV/teste-r2-independente.log
TMPD=$(mktemp -d)
getent passwd pgtest >/dev/null || useradd --system --no-create-home --shell /usr/sbin/nologin pgtest
PS="psql -X -h $DIR -p $PORTA"
para() { [ -f "$DIR/data/postmaster.pid" ] && runuser -u pgtest -- $PGBIN/pg_ctl -D "$DIR/data" -m fast -w stop >/dev/null 2>&1; true; }
novo() { para; rm -rf "$DIR"; mkdir -p "$DIR"; chown pgtest:pgtest "$DIR"; chmod 700 "$DIR"
  runuser -u pgtest -- $PGBIN/initdb -D "$DIR/data" -U pgtest --auth=trust -E UTF8 --locale=C.UTF-8 >/dev/null || exit 1
  runuser -u pgtest -- $PGBIN/pg_ctl -D "$DIR/data" -w -l "$DIR/pg.log" -o "-p $PORTA -k $DIR -c listen_addresses=''" start >/dev/null || exit 1; }
: > "$LOG"
echo "# teste-r2-independente $(date -u +%FT%TZ)" >> "$LOG"

echo "######## PARTE A: bateria do Executor (runner r1 + .sql -r2) no meu cluster ########" >> "$LOG"
para
sed -e "s#DIR=\$RAIZ/.pgtest2; PORTA=5496#DIR=\$RAIZ/.pgtest3; PORTA=$PORTA#" \
    -e "s#LOG=\$EV/teste-r1-independente.log#LOG=$TMPD/parteA.log#" \
    -e "s#-f \$EV/teste-r1-independente.sql#-f \$EV/teste-r1-independente-r2.sql#" \
    -e "s#-f \$EV/teste-rls-r1.sql#-f \$EV/teste-rls-r2.sql#" \
    $EV/teste-r1-independente.sh > "$TMPD/indep.sh"
python3 - "$TMPD/indep.sh" <<'PY'
import sys
p=sys.argv[1]; s=open(p).read()
s=s.replace("e1000000-0000-0000-0005-000000000004';\nselect 'T10","e1000000-0000-0000-0005-000000000002';\nselect 'T10") if False else s
a="update saas.encaminhamento set status='CANCELADO' where id='e1000000-0000-0000-0005-000000000004';"
c="where encaminhamento_id='e1000000-0000-0000-0005-000000000004' and status_novo='CANCELADO'"
s=s.replace(a,a.replace('0004','0002')).replace(c,c.replace('0004','0002'))
open(p,'w').write(s)
PY
bash "$TMPD/indep.sh" >/dev/null 2>&1
cat "$TMPD/parteA.log" >> "$LOG"

echo; echo "######## PARTE B ########" >> "$LOG"
novo
{
echo "# versao: $($PS -U pgtest -d postgres -Atc 'select version()')"
$PS -U pgtest -d postgres -qc 'create database tpl'
$PS -U pgtest -d tpl -v ON_ERROR_STOP=1 -q -f $RAIZ/docs/arquitetura/modelo-v2.sql >"$TMPD/modelo.out" 2>&1; echo "## modelo-v2.sql do zero: exit=$?"
for b in rls1 rls2 orig0 orig sr2 rtn; do $PS -U pgtest -d postgres -qc "create database $b template tpl"; done

echo; echo "## [B1] teste-rls-r2.sql (Executor): resumo e falhas"
$PS -U pgtest -d rls2 -v ON_ERROR_STOP=1 -f $EV/teste-rls-r2.sql > "$TMPD/rls2.out" 2>&1; echo "exit=$?"
sed -n '/RESUMO POR SECAO/,/INFO (so/p' "$TMPD/rls2.out" | cut -c1-200
echo; echo "## [B2] teste-rls-r1.sql SEM os ajustes R2-A/R2-B: falhas (so devem ser os 2 controles)"
$PS -U pgtest -d rls1 -v ON_ERROR_STOP=1 -f $EV/teste-rls-r1.sql > "$TMPD/rls1.out" 2>&1; echo "exit=$?"
sed -n '/FALHAS (esperado/,/INFO (so/p' "$TMPD/rls1.out" | cut -c1-260

echo; echo "## [B3] teste-r1-independente.sql ORIGINAL (rodada 1, sem A1..A6; ON_ERROR_STOP desligado) contra o modelo r2: o que falha"
sed 's/^\\set ON_ERROR_STOP on/\\set ON_ERROR_STOP off/' $EV/teste-r1-independente.sql > "$TMPD/orig_off.sql"
$PS -U pgtest -d orig0 -f "$TMPD/orig_off.sql" > "$TMPD/orig0.out" 2>&1; echo "exit=$?"
grep -E "^psql:.*ERROR" "$TMPD/orig0.out" | cut -c1-200 | head
sed -n '/RESUMO POR SECAO/,/INFO (so/p' "$TMPD/orig0.out" | cut -c1-330

echo; echo "## [B4] teste-r2-independente.sql: falhas originais na forma original + sondas novas"
$PS -U pgtest -d orig -f $EV/teste-r2-independente.sql > "$TMPD/orig.out" 2>&1; echo "exit=$?"
cat "$TMPD/orig.out" | cut -c1-420

echo; echo "## [B5] sondas-r2.sql (Executor) no meu cluster"
PGHOST=$DIR PGPORT=$PORTA $PS -U pgtest -d sr2 -v dir="$DIR" -v porta="$PORTA" -f $EV/sondas-r2.sql > "$TMPD/sr2.out" 2>&1; echo "exit=$?"
grep -ciE "FALHOU|ABERTA" "$TMPD/sr2.out"; grep -E "FALHOU|ABERTA|^ *[0-9]+ \|.*\| f" "$TMPD/sr2.out" | cut -c1-200 | head; tail -25 "$TMPD/sr2.out" | cut -c1-200
} >> "$LOG" 2>&1

{
echo; echo "## [B6] corrida real: jobs_envio_prepara (conexao 1, segura o lock do envio) x cancelamento T9 (conexao 2)"
$PS -U pgtest -d postgres -qc "create database corrida template orig" 
Q="$PS -U pgtest -d corrida -At"
E1=e1000000-0000-0000-0005-000000000001
ENV=$($Q -c "begin; set local role saas_jobs; select saas.jobs_envio_link_paciente('$E1'); commit;" | grep -E '^[0-9a-f-]{36}$' | head -1)
echo "envio PENDENTE de link: $ENV (encaminhamento $E1 CRIADO)"
cat > "$TMPD/c1.sql" <<SQL
begin;
set local role saas_jobs;
select 'c1 prepara: ' || coalesce(segredo,'NULL') || ' contato=' || coalesce(contato,'NULL') from saas.jobs_envio_prepara('$ENV');
reset role;
select pg_sleep(4);
commit;
SQL
$PS -U pgtest -d corrida -At -f "$TMPD/c1.sql" > "$TMPD/c1.out" 2>&1 &
sleep 1.5
$PS -U pgtest -d corrida -At <<SQL > "$TMPD/c2.out" 2>&1
begin;
set local role saas_app;
select set_config('app.sessao', '$(echo -n tok-encO | md5sum | cut -d' ' -f1)', true);
update saas.encaminhamento set status='CANCELADO' where id='$E1';
commit;
SQL
wait
echo "--- conexao 1:"; cat "$TMPD/c1.out"; echo "--- conexao 2 (cancelamento; bloqueia ate a conexao 1 confirmar):"; cat "$TMPD/c2.out"
TOK=$(sed -n 's/^c1 prepara: \([0-9a-f]*\) contato.*/\1/p' "$TMPD/c1.out")
echo "--- estado final:"
$Q -c "select 'encaminhamento=' || status from saas.encaminhamento where id='$E1'"
$Q -c "select 'links vivos no banco para o caso=' || count(*) from saas.link_paciente where encaminhamento_id='$E1' and usado_em is null and revogado_em is null and expira_em>now()"
$Q -c "select 'envio=' || status from saas.envio_notificacao where id='$ENV'"
echo "--- o token entregue na janela da corrida funciona? (saas_app sem sessao)"
$PS -U pgtest -d corrida -At <<SQL
set role saas_app;
select 'link_consulta linhas=' || count(*) from saas.link_consulta('$TOK');
select 'paciente_pede_codigo=' || saas.paciente_pede_codigo('$TOK');
select 'paciente_confirma_codigo=' || coalesce(saas.paciente_confirma_codigo('$TOK','000000'),'NULL');
SQL
} >> "$LOG" 2>&1
para; rm -rf "$TMPD"
echo "## servidor desligado" >> "$LOG"
echo "servidor desligado"
