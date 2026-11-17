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
        assertThat(r.saida()).contains("CREATE POLICY", "CREATE TRIGGER", "ALTER POLICY");
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
            -- Migracao limpa: tabela nova com RLS, indice, coluna e GRANT.
            -- (este comentario cita DISABLE TRIGGER e DROP POLICY e nao conta)
            /* nem este: CREATE POLICY p ON saas.x USING (true) */
            SET ROLE saas_owner;
            SET search_path = saas;
            CREATE TABLE saas.nota (
              id uuid PRIMARY KEY,
              clinica_id uuid NOT NULL REFERENCES saas.clinica (id),
              texto text NOT NULL CHECK (texto <> ''),
              criado_em timestamptz NOT NULL DEFAULT now()
            );
            ALTER TABLE saas.nota ENABLE ROW LEVEL SECURITY;
            ALTER TABLE saas.nota FORCE ROW LEVEL SECURITY;
            CREATE INDEX nota_clinica_idx ON saas.nota (clinica_id);
            ALTER TABLE saas.paciente ADD COLUMN apelido text;
            GRANT SELECT, INSERT ON saas.nota TO saas_app;
            REVOKE ALL ON saas.nota FROM PUBLIC;
            CREATE FUNCTION saas.nota_conta() RETURNS bigint LANGUAGE sql STABLE SECURITY DEFINER
              SET search_path = saas, pg_temp AS $$ SELECT count(*) FROM saas.nota $$;
            REVOKE EXECUTE ON FUNCTION saas.nota_conta() FROM PUBLIC;
            GRANT EXECUTE ON FUNCTION saas.nota_conta() TO saas_app;
            DROP TABLE IF EXISTS saas.rascunho;
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
