#!/usr/bin/env bash
# Rodada de revisao 2 (Executor). Cluster PostgreSQL 16 do Executor: .pgexec2, porta 5494,
# usuario de SO nao-root pgtest. Cada bateria ganha um cluster NOVO (papeis sao do cluster).
# Baterias (nenhuma sonda removida ou enfraquecida; adaptacoes so de infraestrutura,
# listadas abaixo e no cabecalho dos arquivos -r2):
#  1. modelo-v2.sql do zero                         -> modelo-v2-execucao-r2.log
#  2. teste-rls-r2.sql (+ concorrencia)             -> teste-rls-r2.log (sem ajuste: teste-rls-r1-sem-ajuste-r2.log)
#  3. red-team-sondas-r1.sql                        -> red-team-sondas-r1-r2.log
#  4. red-team-sondas-r1-novas.sql                  -> red-team-sondas-r1-novas-r2.log
#     (copia temporaria com socket e porta trocados de .pgrt:5495 para .pgexec2:5494)
#  5. teste-r1-independente.sh do Testador          -> teste-r1-independente-r2.log
#     (copia temporaria com DIR/PORTA/LOG trocados e o .sql -r2, ver cabecalho dele)
#  6. sondas-r2.sql (itens 1 a 7 desta rodada)      -> sondas-r2.log
# Uso (como root): bash docs/arquitetura/evidencias/teste-r2.sh
set -u
RAIZ=/home/claude/saas-agenda
PGBIN=/usr/lib/postgresql/16/bin
DIR=$RAIZ/.pgexec2
PORTA=5494
EV=$RAIZ/docs/arquitetura/evidencias
SEG=$RAIZ/docs/seguranca/evidencias
TMPD=$(mktemp -d)
getent passwd pgtest >/dev/null || useradd --system --no-create-home --shell /usr/sbin/nologin pgtest
PS="psql -X -h $DIR -p $PORTA"
para() { [ -f "$DIR/data/postmaster.pid" ] && runuser -u pgtest -- $PGBIN/pg_ctl -D "$DIR/data" -m fast -w stop >/dev/null 2>&1; true; }
novo_cluster() {
  para
  rm -rf "$DIR"; mkdir -p "$DIR"; chown pgtest:pgtest "$DIR"; chmod 700 "$DIR"
  runuser -u pgtest -- $PGBIN/initdb -D "$DIR/data" -U pgtest --auth=trust -E UTF8 --locale=C.UTF-8 >/dev/null || exit 1
  runuser -u pgtest -- $PGBIN/pg_ctl -D "$DIR/data" -w -l "$DIR/pg.log" -o "-p $PORTA -k $DIR -c listen_addresses=''" start >/dev/null || exit 1
}
modelo() { $PS -U pgtest -d postgres -qc "create database $1" && $PS -U pgtest -d $1 -v ON_ERROR_STOP=1 -q -f $RAIZ/docs/arquitetura/modelo-v2.sql; }

# 1 + 2
novo_cluster
VERSAO=$($PS -U pgtest -d postgres -Atc 'select version()')
{
echo "# modelo-v2-execucao-r2 $(date -u +%FT%TZ)"
echo "# comando: psql -X -v ON_ERROR_STOP=1 -q -f docs/arquitetura/modelo-v2.sql (PostgreSQL 16 limpo, .pgexec2:$PORTA, superusuario pgtest)"
echo "# versao: $VERSAO"
modelo rls_teste 2>&1; echo "modelo-v2.sql exit=$?"
} > "$EV/modelo-v2-execucao-r2.log"
{
echo "# teste-rls-r2 $(date -u +%FT%TZ)  (bateria teste-rls-r2.sql = teste-rls-r1.sql + ajustes R2-A e R2-B do cabecalho)"
echo "# versao: $VERSAO"
echo "## modelo: $(tail -1 $EV/modelo-v2-execucao-r2.log)"
$PS -U pgtest -d rls_teste -v ON_ERROR_STOP=1 -f $EV/teste-rls-r2.sql 2>&1; echo "teste-rls-r2.sql exit=$?"
echo "## (d) concorrencia: duas conexoes ao mesmo tempo, sessao local so na transacao da primeira"
cat > "$TMPD/c1.sql" <<'SQL'
begin;
select set_config('app.clinica_id','aaaaaaaa-0000-0000-0000-000000000001',true), set_config('app.papel','ADMIN',true), set_config('app.sessao', md5('sessao-uA'), true) \gset
select 'conexao 1 (sessao de A, transacao aberta) ve agendamentos: ' || (select count(*) from saas.agendamento);
select pg_sleep(4);
commit;
SQL
$PS -U saas_app -d rls_teste -At -f "$TMPD/c1.sql" > "$TMPD/c1.out" 2>&1 &
sleep 1.5
echo "conexao 2 (sem contexto, em paralelo) ve agendamentos: $($PS -U saas_app -d rls_teste -Atc 'select count(*) from saas.agendamento')"
wait; cat "$TMPD/c1.out"
} > "$EV/teste-rls-r2.log" 2>&1

# 2b: a bateria r1 SEM os ajustes R2-A e R2-B, para registro
novo_cluster
{
echo "# teste-rls-r1.sql SEM ajuste contra o modelo r2 $(date -u +%FT%TZ)"
modelo rls_r1 >/dev/null 2>&1; echo "modelo-v2.sql exit=$?"
$PS -U pgtest -d rls_r1 -v ON_ERROR_STOP=1 -f $EV/teste-rls-r1.sql 2>&1; echo "teste-rls-r1.sql exit=$?"
} > "$EV/teste-rls-r1-sem-ajuste-r2.log" 2>&1

# 3
novo_cluster
{
echo "# red-team-sondas-r1 contra o modelo r2 $(date -u +%FT%TZ)"
echo "# versao: $VERSAO"
modelo rt_r1 >/dev/null 2>&1; echo "modelo-v2.sql exit=$?"
$PS -U pgtest -d rt_r1 -f $SEG/red-team-sondas-r1.sql 2>&1; echo "red-team-sondas-r1.sql exit=$?"
} > "$SEG/red-team-sondas-r1-r2.log" 2>&1

# 4
novo_cluster
sed -e "s#/home/claude/saas-agenda/.pgrt#$DIR#g" -e "s#-p 5495#-p $PORTA#g" $SEG/red-team-sondas-r1-novas.sql > "$TMPD/novas.sql"
{
echo "# red-team-sondas-r1-novas contra o modelo r2 $(date -u +%FT%TZ)"
echo "# versao: $VERSAO"
echo "# unica diferenca da copia executada: socket/porta do psql dos \\! (diff abaixo)"
diff $SEG/red-team-sondas-r1-novas.sql "$TMPD/novas.sql"
modelo rt >/dev/null 2>&1; echo "modelo-v2.sql exit=$?"
: > "$DIR/pg.log.marca"; LINHAS0=$(wc -l < "$DIR/pg.log")
$PS -U pgtest -d rt -f "$TMPD/novas.sql" 2>&1; echo "red-team-sondas-r1-novas.sql exit=$?"
echo "## r2-6: alertas de DDL no log do servidor durante as sondas (N5b/N5c foram desfeitos por ROLLBACK)"
tail -n +$((LINHAS0+1)) "$DIR/pg.log" | grep -E "ALERTA_DDL_SAAS" | sed -E 's/^[0-9-]+ [0-9:.]+ [A-Z]+ \[[0-9]+\] //' | head -20
} > "$SEG/red-team-sondas-r1-novas-r2.log" 2>&1

# 5 (o script do Testador sobe e desliga o proprio cluster)
para
sed -e "s#DIR=\$RAIZ/.pgtest2; PORTA=5496#DIR=\$RAIZ/.pgexec2; PORTA=$PORTA#" \
    -e "s#LOG=\$EV/teste-r1-independente.log#LOG=\$EV/teste-r1-independente-r2.log#" \
    -e "s#-f \$EV/teste-r1-independente.sql#-f \$EV/teste-r1-independente-r2.sql#" \
    -e "s#-f \$EV/teste-rls-r1.sql#-f \$EV/teste-rls-r2.sql#" \
    $EV/teste-r1-independente.sh > "$TMPD/indep.sh"
python3 - "$TMPD/indep.sh" <<'PY'
import sys
p=sys.argv[1]; s=open(p).read()
# [4a]: a sessao de PAC_P e do caso e1..0002 (I-19); T10 informativo passa a usar o caso da sessao
a="update saas.encaminhamento set status='CANCELADO' where id='e1000000-0000-0000-0005-000000000004';"
b="update saas.encaminhamento set status='CANCELADO' where id='e1000000-0000-0000-0005-000000000002';"
c="where encaminhamento_id='e1000000-0000-0000-0005-000000000004' and status_novo='CANCELADO'"
d="where encaminhamento_id='e1000000-0000-0000-0005-000000000002' and status_novo='CANCELADO'"
assert s.count(a)==1 and s.count(c)==1
s=s.replace(a,b).replace(c,d)
open(p,'w').write(s)
PY
{ echo "# diff do runner do Testador executado (infra + [4a] no caso da sessao, ver teste-r1-independente-r2.sql)"; diff $EV/teste-r1-independente.sh "$TMPD/indep.sh"; } > "$TMPD/indep.diff"
bash "$TMPD/indep.sh" >/dev/null 2>&1
{ cat "$TMPD/indep.diff"; cat "$EV/teste-r1-independente-r2.log"; } > "$TMPD/indep.log"; mv "$TMPD/indep.log" "$EV/teste-r1-independente-r2.log"

# 6
novo_cluster
{
echo "# sondas-r2 $(date -u +%FT%TZ)"
echo "# versao: $VERSAO"
modelo r2 >/dev/null 2>&1; echo "modelo-v2.sql exit=$?"
LINHAS0=$(wc -l < "$DIR/pg.log")
PGHOST=$DIR PGPORT=$PORTA $PS -U pgtest -d r2 -v dir="$DIR" -v porta="$PORTA" -f $EV/sondas-r2.sql 2>&1; echo "sondas-r2.sql exit=$?"
echo "## log do servidor: alertas de DDL (r2-6)"
tail -n +$((LINHAS0+1)) "$DIR/pg.log" | grep -E "ALERTA_DDL_SAAS" | sed -E 's/^[0-9-]+ [0-9:.]+ [A-Z]+ \[[0-9]+\] //'
} > "$EV/sondas-r2.log" 2>&1

para; rm -rf "$TMPD"
echo "servidor desligado"
