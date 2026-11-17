# shellcheck shell=bash
# F2: banco versionado (bootstrap + Flyway a partir do modelo v2), papel dono sem login, reversao testada,
# regressao das baterias -r2. Contrato: docs/fase2/spec.md, secao 3.2.
TITULO="Migracoes Flyway do modelo v2, papel dono sem login, reversao e regressao"
source "$ACC/regressao/regressao.sh"

_declara_f2() {
  declara F2.1 "infra/db/bootstrap.sql roda como superusuario num PostgreSQL 16 limpo e nao contem senha"
  declara F2.2 "Flyway real aplica db/migration como saas_migracao (sem superusuario); validate ok; segunda execucao aplica 0"
  declara F2.3 "papeis: saas_owner e saas_funcoes sem login; saas_app, saas_jobs, saas_auth, saas_migracao com login, nenhum superusuario nem BYPASSRLS de login"
  declara F2.4 "todo objeto do schema saas pertence a saas_owner (funcoes: saas_owner ou saas_funcoes); nenhum a papel com login"
  declara F2.5 "membros: so saas_migracao assume saas_owner e saas_funcoes (sem heranca, sem admin); papeis da aplicacao nao assumem nenhum"
  declara F2.6 "RLS ENABLE+FORCE em toda tabela de saas (exceto especialidade); jobs e auth sem privilegio em tabela; web sem DELETE/TRUNCATE; nada executavel por PUBLIC; SECURITY DEFINER com search_path fixo; rastreio desligado nos papeis de login; alerta de DDL ativo"
  declara F2.7 "o schema contem todas as tabelas, colunas (com tipo) e gatilhos do modelo v2"
  declara F2.8 "reversao: cada V<n> tem db/reversao/V<n>__*.sql; desfazer da ultima para a primeira reproduz exatamente o schema da versao anterior; migrar de novo funciona"
  declara F2.9 "regressao: baterias -r2 (rls, independente r1 e r2, sondas-r2, Red Team r1, r1-novas, r2) sem falha fora das sondas neutras de gate"
}

_f2_sql_vazio() { # db consulta : verde se a consulta nao devolve linhas (as linhas vao para o log)
  local out; out=$($PSU -d "$1" -At -c "$2" 2>&1); local rc=$?
  [ $rc -eq 0 ] && [ -z "$out" ] && return 0
  echo "$out" | head -20 >>"$LOGF"; MOTIVO="$(echo "$out" | head -3 | tr '\n' ';' | cut -c1-200)"; return 1
}

_dump_saas() { # db -> stdout (schema saas, sem comentarios de cabecalho)
  runuser -u pgtest -- "$PGBIN/pg_dump" -h "$PGDIR" -p "$PGPORTA" -U pgtest -s -n saas "$1" 2>/dev/null \
    | grep -v -E '^(--|SET |SELECT pg_catalog.set_config|\\restrict|\\unrestrict)' | sed '/^$/d'
}

_f2_reversao() {
  local versoes v arq rev
  [ -d "$MIGDIR" ] || { MOTIVO="sem $MIGDIR"; return 1; }
  versoes=$(ls "$MIGDIR" | sed -n 's/^V\([0-9][0-9._]*\)__.*\.sql$/\1/p' | sort -V)
  [ -n "$versoes" ] || { MOTIVO="nenhuma migracao V<n>__*.sql"; return 1; }
  for v in $versoes; do
    arq=$(ls "$MIGDIR" | grep -E "^V${v}__.*\.sql$" | head -1)
    [ -f "$REVDIR/$arq" ] || { MOTIVO="falta reversao $REVDIR/$arq"; return 1; }
  done
  $PSU -d postgres -c "create database rev template boot_tpl" >/dev/null || return 1
  flyway_migra rev >>"$LOGF" 2>&1 || { MOTIVO="migracao do banco de reversao falhou"; return 1; }
  local anteriores; anteriores=$(echo "$versoes" | tac)
  for v in $anteriores; do
    arq=$(ls "$MIGDIR" | grep -E "^V${v}__.*\.sql$" | head -1)
    PGPASSWORD="$PW_MIGRA" psql -X -q -h 127.0.0.1 -p "$PGPORTA" -U saas_migracao -d rev -v ON_ERROR_STOP=1 -f "$REVDIR/$arq" >>"$LOGF" 2>&1 \
      || { MOTIVO="reversao $arq falhou (saas_migracao)"; return 1; }
    $PSU -d rev -c "delete from migracao.flyway_schema_history where version = '$v'" >/dev/null
    local ant; ant=$(echo "$versoes" | awk -v v="$v" '$0==v{print p; exit} {p=$0}')
    $PSU -d postgres -c "drop database if exists alvo" >/dev/null; $PSU -d postgres -c "create database alvo template boot_tpl" >/dev/null
    if [ -n "$ant" ]; then flyway_migra alvo "$ant" >>"$LOGF" 2>&1 || { MOTIVO="migrar ate $ant falhou"; return 1; }; fi
    if ! diff <(_dump_saas rev) <(_dump_saas alvo) >"$TMPA/F2-reversao-$v.diff"; then
      MOTIVO="depois de desfazer V$v o schema difere da versao ${ant:-bootstrap} (ver $TMPA/F2-reversao-$v.diff)"; return 1
    fi
  done
  flyway_migra rev >>"$LOGF" 2>&1 || { MOTIVO="migrar de novo depois de desfazer tudo falhou"; return 1; }
}

_f2_regressao() {
  roda_regressao modelo
  local b ruins=""
  for b in $REG_BATERIAS; do [ "${REG_RES[$b]:-nao rodou}" = ok ] || ruins="$ruins $b: ${REG_RES[$b]:-nao rodou};"; done
  [ -z "$ruins" ] && return 0
  MOTIVO="$(echo "$ruins" | cut -c1-400)"; return 1
}

_f2_prepara() { # sobe o cluster, bootstrap (template boot_tpl) e migracao (template modelo)
  pg_sobe f2 || { pendentes_vermelhos "PostgreSQL efemero nao subiu"; return 1; }
  trap 'pg_desce' EXIT
  if [ ! -f "$BOOT" ]; then pendentes_vermelhos "pre-requisito ausente: $BOOT"; return 1; fi
  if banco_bootstrap boot_tpl >>"$LOGF" 2>&1 && ! grep -qiE "password[[:space:]]+'" "$BOOT"; then verde F2.1
  else vermelho F2.1 "bootstrap falhou ou contem senha literal (ver $LOGF)"; pendentes_vermelhos "bootstrap falhou"; return 1; fi
  $PSU -d postgres -c "create database modelo template boot_tpl" >/dev/null
  if [ ! -d "$MIGDIR" ]; then pendentes_vermelhos "pre-requisito ausente: $MIGDIR"; return 1; fi
  local o1 o2
  o1=$(flyway_migra modelo 2>&1); echo "$o1" >>"$LOGF"
  o2=$(flyway_migra modelo 2>&1); echo "$o2" >>"$LOGF"
  if echo "$o1" | grep -q MIGRATE_OK && echo "$o2" | grep -q "MIGRATE_OK aplicadas=0" && flyway_migra modelo validate 2>&1 | grep -q VALIDATE_OK; then verde F2.2
  else vermelho F2.2 "Flyway falhou (ver $LOGF)"; pendentes_vermelhos "migracao Flyway falhou"; return 1; fi
}

aceite() {
  _declara_f2
  _f2_prepara || return 0
  MOTIVO="atributos de papel divergentes"
  confere F2.3 _f2_sql_vazio modelo "
    with esp(r, login) as (values ('saas_owner',false),('saas_funcoes',false),('saas_app',true),('saas_jobs',true),('saas_auth',true),('saas_migracao',true))
    select e.r||' ausente ou login errado' from esp e left join pg_roles r on r.rolname = e.r where r.oid is null or r.rolcanlogin <> e.login
    union all select rolname||' superusuario/createrole/createdb' from pg_roles where rolname like 'saas\_%' and (rolsuper or rolcreaterole or rolcreatedb)
    union all select rolname||' com BYPASSRLS' from pg_roles where rolname like 'saas\_%' and rolbypassrls and (rolcanlogin or rolname = 'saas_owner')"
  MOTIVO="objeto de saas com dono indevido"
  confere F2.4 _f2_sql_vazio modelo "
    select c.relname||' dono '||pg_get_userbyid(c.relowner) from pg_class c where c.relnamespace='saas'::regnamespace
       and c.relkind in ('r','p','S','v','m','f') and pg_get_userbyid(c.relowner) <> 'saas_owner'
    union all select p.proname||' dono '||pg_get_userbyid(p.proowner) from pg_proc p where p.pronamespace='saas'::regnamespace
       and pg_get_userbyid(p.proowner) not in ('saas_owner','saas_funcoes')
    union all select 'schema saas dono '||pg_get_userbyid(nspowner) from pg_namespace where nspname='saas' and pg_get_userbyid(nspowner) <> 'saas_owner'
    union all select t.typname||' dono '||pg_get_userbyid(t.typowner) from pg_type t where t.typnamespace='saas'::regnamespace and t.typtype in ('d','e','c')
       and t.typrelid = 0 and pg_get_userbyid(t.typowner) <> 'saas_owner'"
  MOTIVO="pertinencia a papel indevida"
  confere F2.5 _f2_sql_vazio modelo "
    select m.rolname||' -> '||g.rolname from pg_auth_members am join pg_roles m on m.oid=am.member join pg_roles g on g.oid=am.roleid
     where (m.rolname like 'saas\_%' or g.rolname like 'saas\_%')
       and not (m.rolname = 'saas_migracao' and g.rolname in ('saas_owner','saas_funcoes') and not am.inherit_option and not am.admin_option)
    union all select 'saas_migracao nao assume '||x from (values ('saas_owner'),('saas_funcoes')) v(x)
     where not exists (select 1 from pg_auth_members am join pg_roles m on m.oid=am.member join pg_roles g on g.oid=am.roleid
                        where m.rolname='saas_migracao' and g.rolname=v.x)"
  MOTIVO="regra geral de seguranca violada"
  confere F2.6 _f2_sql_vazio modelo "
    select 'sem RLS forcada: '||relname from pg_class where relnamespace='saas'::regnamespace and relkind in ('r','p')
       and relname <> 'especialidade' and not (relrowsecurity and relforcerowsecurity)
    union all select r||' tem privilegio em '||c.relname from pg_class c, (values ('saas_jobs'),('saas_auth')) v(r)
       where c.relnamespace='saas'::regnamespace and c.relkind in ('r','p','v')
         and (has_table_privilege(r, c.oid, 'SELECT') or has_table_privilege(r, c.oid, 'INSERT') or has_table_privilege(r, c.oid, 'UPDATE')
              or has_table_privilege(r, c.oid, 'DELETE') or has_table_privilege(r, c.oid, 'TRUNCATE') or has_any_column_privilege(r, c.oid, 'SELECT'))
    union all select 'saas_app com DELETE/TRUNCATE em '||c.relname from pg_class c where c.relnamespace='saas'::regnamespace and c.relkind in ('r','p')
       and (has_table_privilege('saas_app', c.oid, 'DELETE') or has_table_privilege('saas_app', c.oid, 'TRUNCATE'))
    union all select 'PUBLIC executa '||p.proname from pg_proc p where p.pronamespace='saas'::regnamespace
       and exists (select 1 from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a where a.grantee = 0 and a.privilege_type = 'EXECUTE')
    union all select 'SECURITY DEFINER sem search_path: '||p.proname from pg_proc p where p.pronamespace='saas'::regnamespace and p.prosecdef
       and not exists (select 1 from unnest(coalesce(p.proconfig, '{}')) c where c like 'search_path=%')
    union all select 'funcao jobs_* executavel por '||r||': '||p.proname from pg_proc p, (values ('saas_app'),('saas_auth')) v(r)
       where p.pronamespace='saas'::regnamespace and p.proname like 'jobs\_%' and has_function_privilege(r, p.oid, 'EXECUTE')
    union all select r||' sem '||k from (values ('saas_app'),('saas_jobs'),('saas_auth')) v(r),
       (values ('track_activities=off'),('log_parameter_max_length=0'),('log_parameter_max_length_on_error=0')) w(k)
       where not exists (select 1 from pg_db_role_setting s join pg_roles ro on ro.oid = s.setrole
                          where ro.rolname = r and s.setdatabase = 0 and k = any(s.setconfig))
    union all select 'tabela sem politica com privilegio para '||r||': '||c.relname from pg_class c, (values ('saas_app'),('saas_jobs'),('saas_auth')) v(r)
       where c.relnamespace='saas'::regnamespace and c.relkind in ('r','p') and c.relrowsecurity
         and not exists (select 1 from pg_policy p where p.polrelid = c.oid)
         and (has_table_privilege(r, c.oid, 'SELECT') or has_table_privilege(r, c.oid, 'INSERT') or has_table_privilege(r, c.oid, 'UPDATE')
              or has_any_column_privilege(r, c.oid, 'SELECT') or has_any_column_privilege(r, c.oid, 'INSERT') or has_any_column_privilege(r, c.oid, 'UPDATE'))
    union all select 'sem gatilho de evento ativo em '||e from (values ('ddl_command_end'),('sql_drop')) v(e)
       where not exists (select 1 from pg_event_trigger where evtevent = e and evtenabled <> 'D')"
  # F2.7: superconjunto do modelo v2
  local col gat
  col=$($PSU -d modelo -Atc "select table_name||'|'||column_name||'|'||data_type from information_schema.columns where table_schema='saas'")
  gat=$($PSU -d modelo -Atc "select c.relname||'|'||t.tgname from pg_trigger t join pg_class c on c.oid=t.tgrelid where c.relnamespace='saas'::regnamespace and not t.tgisinternal")
  local faltam; faltam=$( { comm -23 <(sort -u "$GOLD/colunas-modelo-v2.txt") <(echo "$col" | sort -u); comm -23 <(sort -u "$GOLD/gatilhos-modelo-v2.txt") <(echo "$gat" | sort -u); } )
  if [ -z "$faltam" ]; then verde F2.7; else echo "$faltam" >>"$LOGF"; vermelho F2.7 "faltam: $(echo "$faltam" | head -4 | tr '\n' ' ')"; fi
  confere F2.8 _f2_reversao
  confere F2.9 _f2_regressao
}

aceite_regressao_somente() {
  declara F2.9 "regressao: baterias -r2 sem falha fora das sondas neutras de gate"
  pg_sobe reg || { pendentes_vermelhos "PostgreSQL efemero nao subiu"; return 0; }
  trap 'pg_desce' EXIT
  if banco_migrado modelo >>"$LOGF" 2>&1; then confere F2.9 _f2_regressao; else pendentes_vermelhos "bootstrap ou migracao falhou"; fi
}
