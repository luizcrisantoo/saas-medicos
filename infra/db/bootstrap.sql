-- =====================================================================
-- infra/db/bootstrap.sql
-- Roda UMA vez por banco, como superusuario do cluster (no RDS, o administrador),
-- antes da primeira migracao Flyway. Idempotente: papeis sao do cluster e podem
-- ja existir (outro banco do mesmo cluster); tudo o mais usa IF NOT EXISTS.
--
-- Sem senha neste arquivo: a senha dos papeis de login vem do gerenciador de
-- segredos, definida fora do repositorio.
--
-- Fontes: docs/fase2/spec.md, secao 3.2; ADR-0024 (papeis web, jobs, auth);
-- ADR-0027 (dono NOLOGIN, migracao por papel de pipeline, alerta de DDL);
-- ADR-0026 item 7 (rastreio e parametros fora do log); ADR-0003 (Flyway).
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Papeis (ADR-0024, ADR-0027)
--  saas_owner    : NOLOGIN, dono das tabelas. Sujeito a FORCE RLS.
--  saas_funcoes  : NOLOGIN, BYPASSRLS, dono das funcoes SECURITY DEFINER.
--  saas_app      : LOGIN, aplicacao web.
--  saas_jobs     : LOGIN, jobs e listeners; so funcoes jobs_*.
--  saas_auth     : LOGIN, login OIDC da equipe; so sessao_equipe_abre.
--  saas_migracao : LOGIN, papel do pipeline. Membro de saas_owner e saas_funcoes
--                  SEM heranca e SEM admin: so age como dono por SET ROLE, dentro
--                  da migracao. Nao e superusuario e nao cria papel nem banco.
-- ---------------------------------------------------------------------
DO $$
DECLARE
  r record;
BEGIN
  FOR r IN SELECT * FROM (VALUES
      ('saas_owner',    'NOLOGIN NOSUPERUSER NOBYPASSRLS NOCREATEDB NOCREATEROLE NOREPLICATION INHERIT'),
      ('saas_funcoes',  'NOLOGIN NOSUPERUSER BYPASSRLS NOCREATEDB NOCREATEROLE NOREPLICATION NOINHERIT'),
      ('saas_app',      'LOGIN NOSUPERUSER NOBYPASSRLS NOCREATEDB NOCREATEROLE NOREPLICATION NOINHERIT'),
      ('saas_jobs',     'LOGIN NOSUPERUSER NOBYPASSRLS NOCREATEDB NOCREATEROLE NOREPLICATION NOINHERIT'),
      ('saas_auth',     'LOGIN NOSUPERUSER NOBYPASSRLS NOCREATEDB NOCREATEROLE NOREPLICATION NOINHERIT'),
      ('saas_migracao', 'LOGIN NOSUPERUSER NOBYPASSRLS NOCREATEDB NOCREATEROLE NOREPLICATION NOINHERIT')
    ) AS p(nome, atributos)
  LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = r.nome) THEN
      EXECUTE format('CREATE ROLE %I %s', r.nome, r.atributos);
    ELSE
      EXECUTE format('ALTER ROLE %I %s', r.nome, r.atributos);
    END IF;
  END LOOP;
END $$;

-- Pertencimento do pipeline aos papeis donos: SET sim, heranca nao, admin nao.
GRANT saas_owner   TO saas_migracao WITH INHERIT FALSE, SET TRUE, ADMIN FALSE;
GRANT saas_funcoes TO saas_migracao WITH INHERIT FALSE, SET TRUE, ADMIN FALSE;

-- ---------------------------------------------------------------------
-- 2. Parametros por papel de login (ADR-0026 item 7, Red Team I-20)
--  track_activities so o superusuario muda: por isso fica aqui e nao na migracao.
-- ---------------------------------------------------------------------
ALTER ROLE saas_app  SET search_path = saas;
ALTER ROLE saas_jobs SET search_path = saas;
ALTER ROLE saas_auth SET search_path = saas;
ALTER ROLE saas_app  SET track_activities = off;
ALTER ROLE saas_jobs SET track_activities = off;
ALTER ROLE saas_auth SET track_activities = off;
ALTER ROLE saas_app  SET log_parameter_max_length = 0;
ALTER ROLE saas_jobs SET log_parameter_max_length = 0;
ALTER ROLE saas_auth SET log_parameter_max_length = 0;
ALTER ROLE saas_app  SET log_parameter_max_length_on_error = 0;
ALTER ROLE saas_jobs SET log_parameter_max_length_on_error = 0;
ALTER ROLE saas_auth SET log_parameter_max_length_on_error = 0;

-- ---------------------------------------------------------------------
-- 3. Banco: extensao, schemas e privilegios padrao (por banco)
-- ---------------------------------------------------------------------
-- btree_gist: restricao de nao sobreposicao de horarios (EXCLUDE com uuid + tstzrange).
CREATE EXTENSION IF NOT EXISTS btree_gist;

-- O schema public nao serve a ninguem da aplicacao.
REVOKE ALL ON SCHEMA public FROM PUBLIC;

-- Schema da aplicacao, dono saas_owner.
CREATE SCHEMA IF NOT EXISTS saas AUTHORIZATION saas_owner;
ALTER SCHEMA saas OWNER TO saas_owner;
GRANT USAGE ON SCHEMA saas TO saas_app, saas_jobs, saas_auth, saas_funcoes;
GRANT CREATE ON SCHEMA saas TO saas_funcoes;

-- Schema do historico do Flyway, dono o papel do pipeline.
CREATE SCHEMA IF NOT EXISTS migracao AUTHORIZATION saas_migracao;
ALTER SCHEMA migracao OWNER TO saas_migracao;
REVOKE ALL ON SCHEMA migracao FROM PUBLIC;

-- Funcao nova nunca nasce executavel por PUBLIC (o padrao do PostgreSQL e conceder).
ALTER DEFAULT PRIVILEGES FOR ROLE saas_funcoes REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;
ALTER DEFAULT PRIVILEGES FOR ROLE saas_owner   REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;

-- ---------------------------------------------------------------------
-- 4. Alerta de DDL no log do servidor (Red Team R-07 e R-08, ADR-0027, ADR-0039)
--  Gatilho de evento so o superusuario cria; o dono das tabelas nao o desliga.
--  A linha ALERTA_DDL_SAAS vira alarme fora do banco. Nunca traz contato, token
--  ou codigo: so a etiqueta do comando, a identidade (ou o tipo) do objeto e os papeis.
--  O log nao participa do ROLLBACK. Comportamento do PostgreSQL 16, conferido no
--  servidor (ADR-0039, item 1):
--   - politica, gatilho e regra: schema nulo; vale a TABELA ALVO (pg_policy.polrelid,
--     pg_trigger.tgrelid, pg_rewrite.ev_class, lidos direto no catalogo: o gatilho roda
--     com o papel de quem faz o DDL, sem funcao auxiliar) e a identidade "x on saas.t";
--   - GRANT, REVOKE e ALTER DEFAULT PRIVILEGES: schema, identidade e objeto nulos. Sem
--     identidade resolvivel o comando ALERTA, seja qual for a etiqueta;
--   - ALTER ... SET SCHEMA: informa o schema NOVO. Cobre-se por quem executa (papeis do
--     schema saas) e pelo dono do objeto (tabela, funcao ou tipo de saas_owner ou
--     saas_funcoes continua deles fora de saas);
--   - ALTER SCHEMA (RENAME, OWNER), COMMENT ON SCHEMA: tipo schema, identidade com o nome
--     (o novo, no RENAME). Todo comando sobre schema alerta.
--  Quem executa: todo DDL feito como saas_owner, saas_funcoes ou pelos papeis de login
--  (saas_migracao, saas_app, saas_jobs, saas_auth) alerta, sem lista de etiquetas.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.saas_alerta_ddl() RETURNS event_trigger LANGUAGE plpgsql
  SET search_path = pg_catalog, pg_temp AS
$$ DECLARE r record; pelo_papel boolean;
BEGIN
  pelo_papel := current_user::text IN ('saas_owner','saas_funcoes','saas_migracao','saas_app','saas_jobs','saas_auth')
             OR session_user::text IN ('saas_migracao','saas_app','saas_jobs','saas_auth');
  IF TG_EVENT = 'sql_drop' THEN
    FOR r IN SELECT * FROM pg_event_trigger_dropped_objects()
              WHERE pelo_papel
                 OR schema_name = 'saas'
                 OR address_names[1] = 'saas'
                 OR object_type = 'schema'
                 OR object_identity IS NULL
                 OR object_identity LIKE '% on saas.%' LOOP
      RAISE LOG 'ALERTA_DDL_SAAS: DROP % % por session_user=% current_user=%',
        r.object_type, coalesce(r.object_identity, '(sem identidade)'), session_user, current_user;
    END LOOP;
  ELSE
    FOR r IN SELECT * FROM pg_event_trigger_ddl_commands()
              WHERE pelo_papel
                 OR object_identity IS NULL
                 OR objid IS NULL
                 OR schema_name = 'saas'
                 OR lower(object_type) = 'schema'
                 OR object_identity LIKE '% on saas.%'
                 OR EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
                             WHERE n.nspname = 'saas'
                               AND c.oid = CASE classid
                                 WHEN 'pg_catalog.pg_policy'::regclass  THEN (SELECT p.polrelid FROM pg_policy p WHERE p.oid = objid)
                                 WHEN 'pg_catalog.pg_trigger'::regclass THEN (SELECT t.tgrelid FROM pg_trigger t WHERE t.oid = objid)
                                 WHEN 'pg_catalog.pg_rewrite'::regclass THEN (SELECT w.ev_class FROM pg_rewrite w WHERE w.oid = objid)
                               END)
                 OR (CASE classid
                       WHEN 'pg_catalog.pg_class'::regclass THEN (SELECT c.relowner FROM pg_class c WHERE c.oid = objid)
                       WHEN 'pg_catalog.pg_proc'::regclass  THEN (SELECT f.proowner FROM pg_proc f WHERE f.oid = objid)
                       WHEN 'pg_catalog.pg_type'::regclass  THEN (SELECT y.typowner FROM pg_type y WHERE y.oid = objid)
                     END) IN (SELECT o.oid FROM pg_roles o WHERE o.rolname IN ('saas_owner','saas_funcoes')) LOOP
      RAISE LOG 'ALERTA_DDL_SAAS: % % por session_user=% current_user=%',
        r.command_tag, coalesce(r.object_identity, '(sem identidade, tipo ' || coalesce(r.object_type, '?') || ')'),
        session_user, current_user;
    END LOOP;
  END IF;
END $$;
REVOKE EXECUTE ON FUNCTION public.saas_alerta_ddl() FROM PUBLIC;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_event_trigger WHERE evtname = 'saas_alerta_ddl_fim') THEN
    CREATE EVENT TRIGGER saas_alerta_ddl_fim ON ddl_command_end EXECUTE FUNCTION public.saas_alerta_ddl();
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_event_trigger WHERE evtname = 'saas_alerta_ddl_drop') THEN
    CREATE EVENT TRIGGER saas_alerta_ddl_drop ON sql_drop EXECUTE FUNCTION public.saas_alerta_ddl();
  END IF;
END $$;
ALTER EVENT TRIGGER saas_alerta_ddl_fim ENABLE;
ALTER EVENT TRIGGER saas_alerta_ddl_drop ENABLE;
