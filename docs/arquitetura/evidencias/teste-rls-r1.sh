#!/usr/bin/env bash
# Rodada de revisao 1. Sobe PostgreSQL 16 descartavel (usuario nao-root pgtest, porta 5497,
# socket e dados em .pgexec), aplica modelo-v2.sql (log modelo-v2-execucao-r1.log),
# roda teste-rls-r1.sql como saas_app, saas_jobs e saas_auth (log teste-rls-r1.log),
# depois aplica o modelo num banco novo e roda as sondas do Red Team adaptadas
# (docs/seguranca/evidencias/red-team-sondas-r1.sql, log red-team-sondas-r1.log). Desliga ao fim.
# Uso (como root): bash docs/arquitetura/evidencias/teste-rls-r1.sh
set -u
RAIZ=/home/claude/saas-agenda
PGBIN=/usr/lib/postgresql/16/bin
DIR=$RAIZ/.pgexec
PORTA=5497
EV=$RAIZ/docs/arquitetura/evidencias
SEG=$RAIZ/docs/seguranca/evidencias
getent passwd pgtest >/dev/null || useradd --system --no-create-home --shell /usr/sbin/nologin pgtest
PS="psql -X -h $DIR -p $PORTA"
# Papeis sao do cluster inteiro: cada bateria ganha um cluster novo.
novo_cluster() {
  [ -f "$DIR/data/postmaster.pid" ] && runuser -u pgtest -- $PGBIN/pg_ctl -D "$DIR/data" -m fast -w stop >/dev/null 2>&1
  rm -rf "$DIR"; mkdir -p "$DIR"; chown pgtest:pgtest "$DIR"; chmod 700 "$DIR"
  runuser -u pgtest -- $PGBIN/initdb -D "$DIR/data" -U pgtest --auth=trust -E UTF8 --locale=C.UTF-8 >/dev/null || exit 1
  runuser -u pgtest -- $PGBIN/pg_ctl -D "$DIR/data" -w -l "$DIR/pg.log" -o "-p $PORTA -k $DIR -c listen_addresses=''" start >/dev/null || exit 1
}

novo_cluster
VERSAO=$($PS -U pgtest -d postgres -Atc 'select version()')
$PS -U pgtest -d postgres -qc 'create database rls_teste'
{
echo "# modelo-v2-execucao-r1 $(date -u +%FT%TZ)"
echo "# comando: psql -X -v ON_ERROR_STOP=1 -q -f docs/arquitetura/modelo-v2.sql (PostgreSQL 16 limpo, superusuario pgtest, porta $PORTA)"
echo "# versao: $VERSAO"
$PS -U pgtest -d rls_teste -v ON_ERROR_STOP=1 -q -f $RAIZ/docs/arquitetura/modelo-v2.sql 2>&1; echo "modelo-v2.sql exit=$?"
} > "$EV/modelo-v2-execucao-r1.log"

{
echo "# teste-rls-r1 $(date -u +%FT%TZ)"
echo "# comando: bash docs/arquitetura/evidencias/teste-rls-r1.sh"
echo "# versao: $VERSAO"
echo "## modelo-v2.sql aplicado no banco rls_teste: $(tail -1 $EV/modelo-v2-execucao-r1.log) (saida em modelo-v2-execucao-r1.log)"
echo "## teste-rls-r1.sql (papeis saas_app, saas_jobs, saas_auth)"
$PS -U pgtest -d rls_teste -v ON_ERROR_STOP=1 -f $EV/teste-rls-r1.sql 2>&1; echo "teste-rls-r1.sql exit=$?"
echo "## (d) concorrencia: duas conexoes ao mesmo tempo, sessao local so na transacao da primeira"
cat > "$DIR/c1.sql" <<'SQL'
begin;
select set_config('app.clinica_id','aaaaaaaa-0000-0000-0000-000000000001',true), set_config('app.papel','ADMIN',true), set_config('app.sessao', md5('sessao-uA'), true) \gset
select 'conexao 1 (sessao de A, transacao aberta) ve agendamentos: ' || (select count(*) from saas.agendamento);
select pg_sleep(4);
commit;
SQL
$PS -U saas_app -d rls_teste -At -f "$DIR/c1.sql" > "$DIR/c1.out" 2>&1 &
sleep 1.5
echo "conexao 2 (sem contexto, em paralelo) ve agendamentos: $($PS -U saas_app -d rls_teste -Atc 'select count(*) from saas.agendamento')"
wait; cat "$DIR/c1.out"
echo "## desligando"
} > "$EV/teste-rls-r1.log" 2>&1

novo_cluster
{
echo "# red-team-sondas-r1 $(date -u +%FT%TZ)"
echo "# comando: bash docs/arquitetura/evidencias/teste-rls-r1.sh (cluster novo, modelo-v2.sql aplicado, sondas como superusuario + SET LOCAL ROLE)"
echo "# versao: $VERSAO"
$PS -U pgtest -d postgres -qc 'create database rt_r1'
$PS -U pgtest -d rt_r1 -v ON_ERROR_STOP=1 -q -f $RAIZ/docs/arquitetura/modelo-v2.sql >/dev/null 2>&1; echo "modelo-v2.sql exit=$?"
$PS -U pgtest -d rt_r1 -f $SEG/red-team-sondas-r1.sql 2>&1; echo "red-team-sondas-r1.sql exit=$?"
} > "$SEG/red-team-sondas-r1.log" 2>&1

runuser -u pgtest -- $PGBIN/pg_ctl -D "$DIR/data" -m fast -w stop >/dev/null
echo "servidor desligado"
