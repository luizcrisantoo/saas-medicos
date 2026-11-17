#!/usr/bin/env bash
# Sobe PostgreSQL 16 descartavel (usuario nao-root pgtest, porta 5498, socket em .pgtest),
# aplica modelo-v2.sql, roda teste-rls.sql com o papel saas_app e desliga o servidor.
# Uso (como root): bash docs/arquitetura/evidencias/teste-rls.sh   -> grava teste-rls.log
set -u
RAIZ=/home/claude/saas-agenda
PGBIN=/usr/lib/postgresql/16/bin
DIR=$RAIZ/.pgtest
PORTA=5498
EV=$RAIZ/docs/arquitetura/evidencias
LOG=$EV/teste-rls.log
getent passwd pgtest >/dev/null || useradd --system --no-create-home --shell /usr/sbin/nologin pgtest
rm -rf "$DIR"; mkdir -p "$DIR"; chown pgtest:pgtest "$DIR"; chmod 700 "$DIR"
PS="psql -X -h $DIR -p $PORTA"
{
echo "# teste-rls $(date -u +%FT%TZ)"
echo "# comando: bash docs/arquitetura/evidencias/teste-rls.sh"
runuser -u pgtest -- $PGBIN/initdb -D "$DIR/data" -U pgtest --auth=trust -E UTF8 --locale=C.UTF-8 >/dev/null || exit 1
runuser -u pgtest -- $PGBIN/pg_ctl -D "$DIR/data" -w -l "$DIR/pg.log" -o "-p $PORTA -k $DIR -c listen_addresses=''" start || exit 1
echo "# versao: $($PS -U pgtest -d postgres -Atc 'select version()')"
$PS -U pgtest -d postgres -c 'create database rls_teste' || exit 1
echo "## aplicando modelo-v2.sql"
$PS -U pgtest -d rls_teste -v ON_ERROR_STOP=1 -q -f $RAIZ/docs/arquitetura/modelo-v2.sql >/dev/null 2>"$DIR/aplica.err"; echo "modelo-v2.sql exit=$?"; grep -i -E 'error|erro' "$DIR/aplica.err" | head
echo "## teste-rls.sql (papel saas_app)"
$PS -U pgtest -d rls_teste -v ON_ERROR_STOP=1 -f $EV/teste-rls.sql 2>&1; echo "teste-rls.sql exit=$?"
echo "## (d) concorrencia: duas conexoes ao mesmo tempo, contexto local so na transacao da primeira"
cat > "$DIR/c1.sql" <<'SQL'
begin;
select set_config('app.clinica_id','aaaaaaaa-0000-0000-0000-000000000001',true), set_config('app.usuario','aaaaaaaa-0000-0000-0001-000000000001',true), set_config('app.papel','ADMIN',true) \gset
select 'conexao 1 (contexto A, transacao aberta) ve agendamentos: ' || (select count(*) from saas.agendamento);
select pg_sleep(4);
commit;
SQL
$PS -U saas_app -d rls_teste -At -f "$DIR/c1.sql" > "$DIR/c1.out" 2>&1 &
sleep 1.5
echo "conexao 2 (sem contexto, em paralelo) ve agendamentos: $($PS -U saas_app -d rls_teste -Atc 'select count(*) from saas.agendamento')"
wait; cat "$DIR/c1.out"
echo "## desligando"
runuser -u pgtest -- $PGBIN/pg_ctl -D "$DIR/data" -m fast -w stop
} 2>&1 | tee "$LOG"
