#!/usr/bin/env bash
# Testador, rodada 1. Cluster PostgreSQL 16 SEU: .pgtest2, porta 5496, usuario nao-root pgtest.
# 1) modelo-v2.sql do zero; 2) reexecuta teste-rls-r1.sql e red-team-sondas(-r1).sql;
# 3) compara sondas da rodada 0 x r1 (nenhuma removida/enfraquecida?); 4) roda teste-r1-independente.sql
# (casos novos) como saas_app/saas_jobs/saas_auth + concorrencia no mesmo pool. Desliga ao fim.
# Uso (root): bash docs/arquitetura/evidencias/teste-r1-independente.sh  -> grava teste-r1-independente.log
set -u
RAIZ=/home/claude/saas-agenda; PGBIN=/usr/lib/postgresql/16/bin; DIR=$RAIZ/.pgtest2; PORTA=5496
EV=$RAIZ/docs/arquitetura/evidencias; SEG=$RAIZ/docs/seguranca/evidencias; LOG=$EV/teste-r1-independente.log
getent passwd pgtest >/dev/null || useradd --system --no-create-home --shell /usr/sbin/nologin pgtest
rm -rf "$DIR"; mkdir -p "$DIR"; chown pgtest:pgtest "$DIR"; chmod 700 "$DIR"
PS="psql -X -h $DIR -p $PORTA"
{
echo "# teste-r1-independente $(date -u +%FT%TZ)"
runuser -u pgtest -- $PGBIN/initdb -D "$DIR/data" -U pgtest --auth=trust -E UTF8 --locale=C.UTF-8 >/dev/null || exit 1
runuser -u pgtest -- $PGBIN/pg_ctl -D "$DIR/data" -w -l "$DIR/pg.log" -o "-p $PORTA -k $DIR -c listen_addresses=''" start >/dev/null || exit 1
echo "# versao: $($PS -U pgtest -d postgres -Atc 'select version()')"
$PS -U pgtest -d postgres -qc 'create database tpl'
$PS -U pgtest -d tpl -v ON_ERROR_STOP=1 -q -f $RAIZ/docs/arquitetura/modelo-v2.sql >"$DIR/modelo.out" 2>&1; echo "## modelo-v2.sql do zero: exit=$?"
for b in r1 rt1 rt0 novo; do $PS -U pgtest -d postgres -qc "create database $b template tpl"; done

echo; echo "## [1a] teste-rls-r1.sql (Executor) - resumo"
$PS -U pgtest -d r1 -v ON_ERROR_STOP=1 -f $EV/teste-rls-r1.sql > "$DIR/r1.out" 2>&1; echo "exit=$?"
sed -n '/RESUMO POR SECAO/,/FALHAS (esperado/p' "$DIR/r1.out" | cut -c1-120
sed -n '/FALHAS (esperado/,/INFO (so/p' "$DIR/r1.out" | cut -c1-200
grep -E "tabelas alteradas" "$DIR/r1.out"
echo; echo "## [1b] red-team-sondas-r1.sql (Executor) - resumo"
$PS -U pgtest -d rt1 -f $SEG/red-team-sondas-r1.sql > "$DIR/rt1.out" 2>&1; echo "exit=$?"
grep -A3 "sondas_de_ataque" "$DIR/rt1.out"; grep -E "^ *[0-9]+ \| RT.*\| (ABERTA)" "$DIR/rt1.out" | cut -c1-200
echo; echo "## [1c] red-team-sondas.sql ORIGINAL (rodada 0, intocado) contra o modelo r1"
$PS -U pgtest -d rt0 -f $SEG/red-team-sondas.sql > "$DIR/rt0.out" 2>&1; echo "exit=$?"
grep -E "ABERTA" "$DIR/rt0.out" | cut -c1-220 | head -30; grep -A3 "sondas_de_ataque" "$DIR/rt0.out"

echo; echo "## [2] diff de sondas rodada 0 (teste-rls.log) x r1 (teste-rls-r1.log): nome+esperado"
python3 - <<'PY'
import re
def le(p):
    d={}
    for l in open(p,errors='ignore'):
        c=[x.strip() for x in l.split('|')]
        if len(c)>=7 and c[0].isdigit() and c[2] in('PASSOU','FALHOU','INFO'):
            d[(c[1],c[3])]=(c[5],c[2])
    return d
ev='/home/claude/saas-agenda/docs/arquitetura/evidencias/'
a=le(ev+'teste-rls.log'); b=le(ev+'teste-rls-r1.log')
print("sondas r0:",len(a),"r1:",len(b))
bn={}
for (s,n),v in b.items(): bn.setdefault(n,[]).append((s,v))
falta=[(k,v) for k,v in a.items() if k not in b]
print("r0 sem par exato (secao,nome) em r1:",len(falta))
for (s,n),v in falta:
    print("  ",s,"|",n[:80],"| esperado r0:",v[0],"| em r1 (outra secao/nome?):",bn.get(n,'AUSENTE')[:1])
mud=[(k,a[k][0],b[k][0]) for k in a if k in b and a[k][0]!=b[k][0]]
print("esperado mudou:",len(mud))
for k,x,y in mud: print("  ",k[0],"|",k[1][:70],"|",x,"->",y)
PY
echo; echo "## [3] teste-r1-independente.sql (casos novos)"
$PS -U pgtest -d novo -v ON_ERROR_STOP=1 -f $EV/teste-r1-independente.sql 2>&1; echo "exit=$?"

echo; echo "## [4] com LOGIN REAL (nao via SET ROLE de superusuario): escalada de papel, ator_tecnico, jobs e concorrencia no mesmo pool"
RAIZ_T() { echo; echo "-- $1"; }
tk() { $PS -U pgtest -d novo -Atc "select t.tok('$1')"; }
TA=$(tk admA); TB=$(tk admB); TP=$(tk pacP); TQ=$(tk pacQ)
CA=aaaaaaaa-0000-0000-0000-000000000001; CB=bbbbbbbb-0000-0000-0000-000000000001
for r in saas_app saas_jobs saas_auth; do
  for c in "set role saas_funcoes" "set role saas_owner" "set role pgtest" "set session authorization saas_funcoes" "create table public.x(i int)" "create schema evil" "alter role $r superuser" "set session_replication_role = replica" "copy saas.paciente to program 'id'"; do
    out=$($PS -U $r -d novo -Atc "$c" 2>&1 | head -1); echo "$r | $c => ${out:-OK sem erro}"
  done
done
RAIZ_T "[4a] ator_tecnico real no historico de T10 (login saas_app) e no de T8 (login saas_jobs)"
$PS -U saas_app -d novo -At <<SQL
begin;
select set_config('app.sessao','$TP',true) \gset
update saas.encaminhamento set status='CANCELADO' where id='e1000000-0000-0000-0005-000000000004';
select 'T10 historico: ' || transicao || ' ator_tecnico=' || ator_tecnico || ' ator_tipo=' || ator_tipo || ' ator_id=' || ator_id from saas.historico_status_encaminhamento where encaminhamento_id='e1000000-0000-0000-0005-000000000004' and status_novo='CANCELADO';
rollback;
SQL
RAIZ_T "[4b] pool: UMA conexao saas_app reaproveitada por clinica A, clinica B e sem contexto, em ordem aleatoria (pgbench -M prepared); falha = divisao por zero se vazar"
mk() { # nome token clinica papel pc agend enc clin
cat > "$DIR/$1.sql" <<SQL
BEGIN;
SELECT set_config('app.sessao','$2',true), set_config('app.clinica_id','$3',true), set_config('app.papel','$4',true);
SELECT 1/(CASE WHEN (SELECT count(*) FROM saas.paciente_clinica)=$5 AND (SELECT count(*) FROM saas.agendamento)=$6 AND (SELECT count(*) FROM saas.encaminhamento)=$7 AND (SELECT count(*) FROM saas.clinica)=$8 THEN 1 ELSE 0 END);
COMMIT;
SQL
}
mk a "$TA" $CA ADMIN 2 3 6 1
mk b "$TB" $CB ADMIN 1 0 0 1
mk c "" "" "" 0 0 0 0
mk x "$TA" $CA ADMIN 1 0 0 1    # CONTROLE NEGATIVO: espera os numeros de B com o contexto de A; tem que falhar
run_pgb() { out=$($PGBIN/pgbench -n -M prepared -h $DIR -p $PORTA -U saas_app -d novo "$@" 2>&1); echo "$out" | grep -E "number of transactions actually processed|number of failed|aborted|division by zero" | head -4; }
echo "pgbench A+B+sem contexto, 1 conexao, 6000 transacoes:"; run_pgb -c 1 -t 6000 -f $DIR/a.sql -f $DIR/b.sql -f $DIR/c.sql
echo "pgbench A+B+sem contexto, 8 conexoes paralelas, 8s:"; run_pgb -c 8 -j 4 -T 8 -f $DIR/a.sql -f $DIR/b.sql -f $DIR/c.sql
echo "CONTROLE NEGATIVO (deve abortar):"; run_pgb -c 1 -t 50 -f $DIR/x.sql
RAIZ_T "[4c] corrida: dois pacientes/duas clinicas tentando o mesmo T3 ao mesmo tempo (FOR UPDATE)"
( $PS -U saas_app -d novo -At -c "begin" -c "select set_config('app.sessao','$TP',true)" -c "select saas.paciente_solicita('e1000000-0000-0000-0005-000000000002','$CA',null,'t','v1')" -c "select pg_sleep(3)" -c "commit" 2>&1 | sed 's/^/sessao1: /' ) &
sleep 1
$PS -U saas_app -d novo -At -c "begin" -c "select set_config('app.sessao','$TP',true)" -c "select saas.paciente_solicita('e1000000-0000-0000-0005-000000000002','$CB',null,'t','v1')" -c "commit" 2>&1 | sed 's/^/sessao2: /' | head -3
wait
$PS -U pgtest -d novo -At -c "select 'estado final: destino=' || coalesce(clinica_destino_id::text,'nulo') || ' status=' || status || ' consentimentos=' || (select count(*) from saas.consentimento c where c.encaminhamento_id=e.id) || ' consentimento_na_clinica_destino=' || (select count(*) from saas.consentimento c where c.encaminhamento_id=e.id and c.clinica_id=e.clinica_destino_id) from saas.encaminhamento e where id='e1000000-0000-0000-0005-000000000002'"
echo "## desligando"
runuser -u pgtest -- $PGBIN/pg_ctl -D "$DIR/data" -m fast -w stop
} 2>&1 | tee "$LOG"
