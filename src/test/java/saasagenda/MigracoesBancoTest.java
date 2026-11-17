package saasagenda;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.SecureRandom;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;
import java.util.ArrayList;
import java.util.HexFormat;
import java.util.List;
import org.flywaydb.core.Flyway;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.MethodOrderer;
import org.junit.jupiter.api.Order;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.TestMethodOrder;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;
import org.testcontainers.utility.DockerImageName;

/**
 * F2: bootstrap como superusuario, Flyway real como saas_migracao (papel de pipeline
 * sem superusuario, ADR-0027), regras gerais do schema e reversao versao a versao.
 * PostgreSQL 16 efemero em Testcontainers (imagem do mirror, spec 3.1).
 */
@Testcontainers
@TestMethodOrder(MethodOrderer.OrderAnnotation.class)
class MigracoesBancoTest {

    private static final DockerImageName IMAGEM = DockerImageName
            .parse("mirror.gcr.io/library/postgres:16-alpine")
            .asCompatibleSubstituteFor("postgres");

    @Container
    static final PostgreSQLContainer<?> PG = new PostgreSQLContainer<>(IMAGEM);

    private static final String SENHA_MIGRACAO = senhaAleatoria();
    private static final String SENHA_APP = senhaAleatoria();

    @BeforeAll
    static void bootstrap() throws Exception {
        String script = Files.readString(Path.of("infra/db/bootstrap.sql"), StandardCharsets.UTF_8);
        assertThat(script).doesNotContainIgnoringCase("PASSWORD");
        try (Connection c = superusuario(); Statement s = c.createStatement()) {
            s.execute(script);
            // Idempotente: segunda execucao no mesmo banco nao falha.
            s.execute(script);
            // A senha vem de fora do repositorio (aqui, aleatoria por execucao).
            s.execute("ALTER ROLE saas_migracao PASSWORD '" + SENHA_MIGRACAO + "'");
            s.execute("ALTER ROLE saas_app PASSWORD '" + SENHA_APP + "'");
        }
    }

    @Test
    @Order(1)
    void flywayAplicaComoPapelDePipelineEhIdempotente() throws Exception {
        assertThat(flyway().migrate().migrationsExecuted).isGreaterThan(0);
        flyway().validate();
        assertThat(flyway().migrate().migrationsExecuted).isZero();
        assertThat(umInteiro("SELECT count(*) FROM migracao.flyway_schema_history WHERE success"))
                .isEqualTo(versoes().size());
        // A migracao terminou com RESET ROLE: o historico foi gravado pelo proprio pipeline.
        assertThat(lista("SELECT DISTINCT installed_by FROM migracao.flyway_schema_history"))
                .containsExactly("saas_migracao");
    }

    @Test
    @Order(2)
    void papeisEPertencimento() throws Exception {
        assertThat(lista("SELECT rolname FROM pg_roles WHERE rolname LIKE 'saas%' AND rolcanlogin ORDER BY 1"))
                .containsExactly("saas_app", "saas_auth", "saas_jobs", "saas_migracao");
        assertThat(lista("SELECT rolname FROM pg_roles WHERE rolname LIKE 'saas%' AND NOT rolcanlogin ORDER BY 1"))
                .containsExactly("saas_funcoes", "saas_owner");
        assertThat(umInteiro("SELECT count(*) FROM pg_roles WHERE rolname LIKE 'saas%' AND (rolsuper OR rolcreaterole OR rolcreatedb)"))
                .isZero();
        assertThat(lista("SELECT rolname FROM pg_roles WHERE rolname LIKE 'saas%' AND rolbypassrls"))
                .containsExactly("saas_funcoes");
        // So saas_migracao assume os papeis donos, sem heranca e sem admin.
        assertThat(lista("""
                SELECT r.rolname || '>' || m.rolname || ':' || a.inherit_option || a.admin_option || a.set_option
                  FROM pg_auth_members a JOIN pg_roles r ON r.oid = a.roleid JOIN pg_roles m ON m.oid = a.member
                 WHERE r.rolname IN ('saas_owner','saas_funcoes','saas_app','saas_jobs','saas_auth','saas_migracao')
                    OR m.rolname IN ('saas_owner','saas_funcoes','saas_app','saas_jobs','saas_auth')
                 ORDER BY 1"""))
                .containsExactly("saas_funcoes>saas_migracao:falsefalsetrue", "saas_owner>saas_migracao:falsefalsetrue");
        // Sem heranca: o pipeline, fora do SET ROLE, nao le tabela nem cria objeto em saas.
        try (Connection c = conecta("saas_migracao", SENHA_MIGRACAO); Statement s = c.createStatement()) {
            assertThatThrownBy(() -> s.executeQuery("SELECT 1 FROM saas.paciente")).isInstanceOf(SQLException.class);
            assertThatThrownBy(() -> s.execute("CREATE TABLE saas.intrusa (x int)")).isInstanceOf(SQLException.class);
        }
        // A aplicacao nao assume o dono.
        try (Connection c = conecta("saas_app", SENHA_APP); Statement s = c.createStatement()) {
            assertThatThrownBy(() -> s.execute("SET ROLE saas_owner")).isInstanceOf(SQLException.class);
            assertThatThrownBy(() -> s.execute("SET ROLE saas_funcoes")).isInstanceOf(SQLException.class);
        }
        // Rastreio e parametros fora do log nos papeis de login da aplicacao.
        assertThat(umInteiro("""
                SELECT count(*) FROM pg_db_role_setting d JOIN pg_roles r ON r.oid = d.setrole
                 WHERE r.rolname IN ('saas_app','saas_jobs','saas_auth')
                   AND d.setconfig @> ARRAY['track_activities=off','log_parameter_max_length=0',
                                            'log_parameter_max_length_on_error=0']""")).isEqualTo(3);
    }

    @Test
    @Order(3)
    void regrasGeraisDoSchema() throws Exception {
        assertThat(umInteiro("SELECT count(*) FROM pg_tables WHERE schemaname = 'saas'")).isEqualTo(24);
        assertThat(lista("SELECT DISTINCT tableowner FROM pg_tables WHERE schemaname = 'saas'"))
                .containsExactly("saas_owner");
        assertThat(lista("SELECT DISTINCT pg_get_userbyid(proowner) FROM pg_proc WHERE pronamespace = 'saas'::regnamespace"))
                .containsExactly("saas_funcoes");
        assertThat(lista("""
                SELECT relname FROM pg_class WHERE relnamespace = 'saas'::regnamespace AND relkind = 'r'
                   AND NOT (relrowsecurity AND relforcerowsecurity) ORDER BY 1"""))
                .containsExactly("especialidade");
        assertThat(umInteiro("""
                SELECT count(*) FROM pg_class c CROSS JOIN (VALUES ('saas_jobs'),('saas_auth')) p(r)
                 WHERE c.relnamespace = 'saas'::regnamespace AND c.relkind IN ('r','v','m','p','S')
                   AND has_table_privilege(p.r, c.oid, 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')"""))
                .isZero();
        assertThat(umInteiro("""
                SELECT count(*) FROM pg_class c WHERE c.relnamespace = 'saas'::regnamespace AND c.relkind IN ('r','p')
                   AND has_table_privilege('saas_app', c.oid, 'DELETE,TRUNCATE')""")).isZero();
        assertThat(umInteiro("""
                SELECT count(*) FROM pg_proc p WHERE p.pronamespace = 'saas'::regnamespace
                   AND EXISTS (SELECT 1 FROM aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
                                WHERE a.grantee = 0 AND a.privilege_type = 'EXECUTE')""")).isZero();
        assertThat(umInteiro("""
                SELECT count(*) FROM pg_proc WHERE pronamespace = 'saas'::regnamespace AND prosecdef
                   AND NOT EXISTS (SELECT 1 FROM unnest(proconfig) c WHERE c LIKE 'search_path=%')""")).isZero();
        assertThat(umInteiro("""
                SELECT count(*) FROM pg_proc WHERE pronamespace = 'saas'::regnamespace
                   AND has_function_privilege('saas_jobs', oid, 'EXECUTE')""")).isEqualTo(8);
        assertThat(umInteiro("""
                SELECT count(*) FROM pg_proc WHERE pronamespace = 'saas'::regnamespace AND proname LIKE 'jobs\\_%'
                   AND has_function_privilege('saas_app', oid, 'EXECUTE')""")).isZero();
        assertThat(lista("""
                SELECT p.proname FROM pg_proc p WHERE p.pronamespace = 'saas'::regnamespace
                   AND has_function_privilege('saas_auth', p.oid, 'EXECUTE')"""))
                .containsExactly("sessao_equipe_abre");
        assertThat(lista("SELECT evtname || ':' || evtenabled::text FROM pg_event_trigger ORDER BY 1"))
                .containsExactly("saas_alerta_ddl_drop:O", "saas_alerta_ddl_fim:O");
    }

    @Test
    @Order(4)
    void reversaoVersaoAVersaoVoltaAoEstadoAnterior() throws Exception {
        List<String> versoes = versoes();
        // Estado do schema a cada versao, aplicando uma de cada vez.
        reverteTudo(versoes);
        List<String> estados = new ArrayList<>();
        estados.add(estadoDoSchema());
        for (String v : versoes) {
            flywayAte(v).migrate();
            estados.add(estadoDoSchema());
        }
        // Desfaz da ultima para a primeira e compara com o estado da versao anterior.
        for (int i = versoes.size() - 1; i >= 0; i--) {
            executaReversao(versoes.get(i));
            assertThat(estadoDoSchema()).as("reversao de V" + versoes.get(i)).isEqualTo(estados.get(i));
        }
        assertThat(umInteiro("SELECT count(*) FROM pg_class WHERE relnamespace = 'saas'::regnamespace")).isZero();
        assertThat(umInteiro("SELECT count(*) FROM pg_proc WHERE pronamespace = 'saas'::regnamespace")).isZero();
        assertThat(umInteiro("SELECT count(*) FROM migracao.flyway_schema_history WHERE version IS NOT NULL")).isZero();
        // Migrar de novo funciona e chega ao mesmo estado final.
        flyway().migrate();
        flyway().validate();
        assertThat(estadoDoSchema()).isEqualTo(estados.get(estados.size() - 1));
    }

    // ------------------------------------------------------------------

    private static void reverteTudo(List<String> versoes) throws Exception {
        for (int i = versoes.size() - 1; i >= 0; i--) {
            executaReversao(versoes.get(i));
        }
    }

    private static void executaReversao(String versao) throws Exception {
        String nome = arquivoDaVersao(versao);
        String sql;
        try (InputStream in = MigracoesBancoTest.class.getResourceAsStream("/db/reversao/" + nome)) {
            assertThat(in).as("reversao de " + nome).isNotNull();
            sql = new String(in.readAllBytes(), StandardCharsets.UTF_8);
        }
        try (Connection c = conecta("saas_migracao", SENHA_MIGRACAO); Statement s = c.createStatement()) {
            c.setAutoCommit(false);
            s.execute(sql);
            c.commit();
        }
    }

    /** Descricao estavel do schema saas: objetos, colunas, ACLs, politicas, gatilhos e corpos. */
    private static String estadoDoSchema() throws SQLException {
        return String.join("\n", lista("""
                SELECT 'rel ' || c.relname || ' ' || c.relkind::text || ' ' || pg_get_userbyid(c.relowner) || ' '
                       || c.relrowsecurity || c.relforcerowsecurity || ' ' || coalesce(c.relacl::text, '')
                  FROM pg_class c WHERE c.relnamespace = 'saas'::regnamespace
                UNION ALL
                SELECT 'col ' || c.relname || '.' || a.attname || ' ' || format_type(a.atttypid, a.atttypmod)
                       || ' ' || a.attnotnull || ' ' || coalesce(pg_get_expr(d.adbin, d.adrelid), '')
                       || ' ' || coalesce(a.attacl::text, '')
                  FROM pg_attribute a JOIN pg_class c ON c.oid = a.attrelid
                  LEFT JOIN pg_attrdef d ON d.adrelid = a.attrelid AND d.adnum = a.attnum
                 WHERE c.relnamespace = 'saas'::regnamespace AND a.attnum > 0 AND NOT a.attisdropped
                UNION ALL
                SELECT 'con ' || conrelid::regclass || ' ' || conname || ' ' || pg_get_constraintdef(oid)
                  FROM pg_constraint WHERE connamespace = 'saas'::regnamespace
                UNION ALL
                SELECT 'fun ' || p.oid::regprocedure || ' ' || pg_get_userbyid(p.proowner) || ' '
                       || coalesce(p.proacl::text, '') || ' ' || md5(pg_get_functiondef(p.oid))
                  FROM pg_proc p WHERE p.pronamespace = 'saas'::regnamespace
                UNION ALL
                SELECT 'pol ' || tablename || ' ' || policyname || ' ' || cmd::text || ' ' || coalesce(qual, '')
                       || ' ' || coalesce(with_check, '')
                  FROM pg_policies WHERE schemaname = 'saas'
                UNION ALL
                SELECT 'trg ' || pg_get_triggerdef(t.oid) || ' ' || t.tgenabled::text
                  FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid
                 WHERE c.relnamespace = 'saas'::regnamespace AND NOT t.tgisinternal
                UNION ALL
                SELECT 'ns ' || nspname || ' ' || pg_get_userbyid(nspowner) || ' ' || coalesce(nspacl::text, '')
                  FROM pg_namespace WHERE nspname = 'saas'
                ORDER BY 1"""));
    }

    private static List<String> versoes() throws IOException {
        try (var arquivos = Files.list(Path.of("src/main/resources/db/migration"))) {
            return arquivos.map(p -> p.getFileName().toString())
                    .filter(n -> n.matches("V\\d+__.+\\.sql"))
                    .map(n -> n.substring(1, n.indexOf("__")))
                    .sorted((a, b) -> Integer.compare(Integer.parseInt(a), Integer.parseInt(b)))
                    .toList();
        }
    }

    private static String arquivoDaVersao(String versao) throws IOException {
        try (var arquivos = Files.list(Path.of("src/main/resources/db/migration"))) {
            return arquivos.map(p -> p.getFileName().toString())
                    .filter(n -> n.startsWith("V" + versao + "__"))
                    .findFirst().orElseThrow();
        }
    }

    private static Flyway flyway() {
        return configuracao().load();
    }

    private static Flyway flywayAte(String versao) {
        return configuracao().target(versao).load();
    }

    private static org.flywaydb.core.api.configuration.FluentConfiguration configuracao() {
        return Flyway.configure()
                .dataSource(PG.getJdbcUrl(), "saas_migracao", SENHA_MIGRACAO)
                .schemas("migracao")
                .defaultSchema("migracao")
                .createSchemas(false)
                .cleanDisabled(true)
                .locations("classpath:db/migration");
    }

    private static Connection superusuario() throws SQLException {
        return DriverManager.getConnection(PG.getJdbcUrl(), PG.getUsername(), PG.getPassword());
    }

    private static Connection conecta(String usuario, String senha) throws SQLException {
        return DriverManager.getConnection(PG.getJdbcUrl(), usuario, senha);
    }

    private static long umInteiro(String sql) throws SQLException {
        try (Connection c = superusuario(); Statement s = c.createStatement(); ResultSet r = s.executeQuery(sql)) {
            r.next();
            return r.getLong(1);
        }
    }

    private static List<String> lista(String sql) throws SQLException {
        List<String> saida = new ArrayList<>();
        try (Connection c = superusuario(); Statement s = c.createStatement(); ResultSet r = s.executeQuery(sql)) {
            while (r.next()) {
                saida.add(r.getString(1));
            }
        }
        return saida;
    }

    private static String senhaAleatoria() {
        byte[] b = new byte[24];
        new SecureRandom().nextBytes(b);
        return HexFormat.of().formatHex(b);
    }
}
