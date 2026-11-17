package saasagenda;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
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
import java.util.Collections;
import java.util.HexFormat;
import java.util.List;
import java.util.Set;
import java.util.TreeSet;
import java.util.UUID;
import java.util.concurrent.Callable;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import javax.sql.DataSource;
import org.flywaydb.core.Flyway;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.server.LocalServerPort;
import org.springframework.context.ApplicationContext;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.utility.DockerImageName;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.context.annotation.Bean;
import org.springframework.transaction.annotation.Transactional;
import com.zaxxer.hikari.HikariDataSource;
import saasagenda.identidade.ConsultaContexto;
import saasagenda.identidade.ContextoAcesso;
import saasagenda.identidade.ContextoBanco;
import saasagenda.identidade.JobsApi;

/**
 * F7 no processo web: contexto por transação ({@code set_config(..., ?, true)}), pool de 1 conexão
 * sem herança de contexto entre requisições alternadas e concorrentes de clínicas diferentes,
 * I-20 (nenhum token no log com {@code log_statement=all} nem em {@code pg_stat_statements}) e E-09
 * (com a credencial de jobs no ambiente, o processo web nunca conecta como {@code saas_jobs}).
 * Se alguém interpolar o token no SQL, {@link #i20NenhumTokenNoLogNemEmPgStatStatements()} reprova
 * (o log do servidor passa a conter o token) junto com {@link ContextoArquiteturaTest}.
 * Dados fictícios.
 */
// Processo web fixo: o SAAS_PROCESSO do ambiente de quem roda a suíte não muda o teste.
@ActiveProfiles("web")
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class ContextoPoolTest {

    private static final DockerImageName IMAGEM = DockerImageName
            .parse("mirror.gcr.io/library/postgres:16-alpine")
            .asCompatibleSubstituteFor("postgres");
    static final PostgreSQLContainer<?> PG = new PostgreSQLContainer<>(IMAGEM)
            .withCommand("postgres", "-c", "log_statement=all", "-c", "shared_preload_libraries=pg_stat_statements",
                    "-c", "pg_stat_statements.track=all", "-c", "pg_stat_statements.track_utility=on");

    private static final String SENHA = senhaAleatoria();
    private static final UUID CLINICA_A = UUID.randomUUID();
    private static final UUID CLINICA_B = UUID.randomUUID();
    private static final String ADMIN_A = token();
    private static final String ADMIN_B = token();
    private static final String RECEPCAO_A = token();
    private static final String ENCERRADA = token();
    private static final String INEXISTENTE = token();
    private static final Set<String> EVENTOS_A = new TreeSet<>();
    private static final Set<String> EVENTOS_B = new TreeSet<>();

    @LocalServerPort
    int porta;

    @Autowired
    ApplicationContext contexto;

    @Autowired
    JdbcTemplate app;

    @Autowired
    DataSource dataSource;

    @Autowired
    ContextoBanco contextoBanco;

    @Autowired
    ServicoComum servicoComum;

    /** Um serviço qualquer com {@code @Transactional} e o {@code JdbcTemplate} padrão, sem contexto. */
    static class ServicoComum {
        private final JdbcTemplate jdbc;

        ServicoComum(JdbcTemplate jdbc) {
            this.jdbc = jdbc;
        }

        @Transactional
        public Integer contaEventos() {
            return jdbc.queryForObject("SELECT count(*) FROM saas.evento_auditoria", Integer.class);
        }

        @Transactional
        public String sessaoAtual() {
            return jdbc.queryForObject("SELECT session_user::text", String.class);
        }
    }

    @TestConfiguration
    static class Config {
        @Bean
        ServicoComum servicoComum(JdbcTemplate jdbc) {
            return new ServicoComum(jdbc);
        }
    }

    private final HttpClient http = HttpClient.newHttpClient();

    @DynamicPropertySource
    static void ambiente(DynamicPropertyRegistry r) throws Exception {
        PG.start();
        prepara();
        r.add("spring.datasource.url", PG::getJdbcUrl);
        r.add("spring.datasource.username", () -> "saas_app");
        r.add("spring.datasource.password", () -> SENHA);
        r.add("spring.datasource.hikari.maximum-pool-size", () -> "1");
        r.add("spring.datasource.hikari.minimum-idle", () -> "1");
        r.add("saas.db.auth.url", PG::getJdbcUrl);
        r.add("saas.db.auth.username", () -> "saas_auth");
        r.add("saas.db.auth.password", () -> SENHA);
        r.add("saas.auth.issuer", () -> "https://cognito-idp.sa-east-1.amazonaws.com/sa-east-1_Ficticio");
        r.add("saas.auth.jwks-uri", () -> "http://127.0.0.1:9/jwks.json");
        r.add("saas.auth.client-ids", () -> "cliente-ficticio");
        // E-09: a credencial de jobs presente no ambiente do processo web é ignorada.
        r.add("SAAS_DB_JOBS_URL", PG::getJdbcUrl);
        r.add("SAAS_DB_JOBS_USERNAME", () -> "saas_jobs");
        r.add("SAAS_DB_JOBS_PASSWORD", () -> SENHA);
        r.add("saas.db.jobs.url", PG::getJdbcUrl);
        r.add("saas.db.jobs.username", () -> "saas_jobs");
        r.add("saas.db.jobs.password", () -> SENHA);
    }

    private static void prepara() throws Exception {
        try (Connection c = superusuario(); Statement s = c.createStatement()) {
            s.execute(Files.readString(Path.of("infra/db/bootstrap.sql"), StandardCharsets.UTF_8));
            for (String papel : new String[] {"saas_migracao", "saas_app", "saas_jobs", "saas_auth"}) {
                s.execute("ALTER ROLE " + papel + " PASSWORD '" + SENHA + "'");
            }
            s.execute("CREATE EXTENSION IF NOT EXISTS pg_stat_statements");
        }
        Flyway.configure()
                .dataSource(PG.getJdbcUrl(), "saas_migracao", SENHA)
                .schemas("migracao").defaultSchema("migracao").createSchemas(false)
                .locations("classpath:db/migration")
                .load().migrate();
        UUID adminA = UUID.randomUUID();
        UUID adminB = UUID.randomUUID();
        UUID recA = UUID.randomUUID();
        try (Connection c = superusuario(); Statement s = c.createStatement()) {
            s.execute("INSERT INTO saas.clinica(id, nome) VALUES ('" + CLINICA_A + "', 'Clinica Ficticia A'), ('"
                    + CLINICA_B + "', 'Clinica Ficticia B')");
            s.execute("INSERT INTO saas.usuario(id, sub_oidc, nome, email) VALUES "
                    + "('" + adminA + "', 'sub-admin-a', 'Admin A', 'a@exemplo.invalid'), "
                    + "('" + adminB + "', 'sub-admin-b', 'Admin B', 'b@exemplo.invalid'), "
                    + "('" + recA + "', 'sub-rec-a', 'Recepcao A', 'r@exemplo.invalid')");
            s.execute("INSERT INTO saas.usuario_clinica(usuario_id, clinica_id, papel) VALUES "
                    + "('" + adminA + "', '" + CLINICA_A + "', 'ADMIN'), ('" + adminB + "', '" + CLINICA_B + "', 'ADMIN'), "
                    + "('" + recA + "', '" + CLINICA_A + "', 'RECEPCAO')");
            sessao(s, ADMIN_A, adminA, false);
            sessao(s, ADMIN_B, adminB, false);
            sessao(s, RECEPCAO_A, recA, false);
            sessao(s, ENCERRADA, adminA, true);
            for (int i = 0; i < 3; i++) {
                EVENTOS_A.add(evento(s, CLINICA_A));
            }
            for (int i = 0; i < 2; i++) {
                EVENTOS_B.add(evento(s, CLINICA_B));
            }
            s.execute("SELECT pg_stat_statements_reset()");
        }
    }

    private static void sessao(Statement s, String token, UUID usuario, boolean encerrada) throws SQLException {
        s.execute("INSERT INTO saas.sessao(token_hash, tipo, usuario_id, expira_em, encerrada_em) VALUES "
                + "(decode('" + sha256(token) + "', 'hex'), 'EQUIPE', '" + usuario + "', now() + interval '2 hours', "
                + (encerrada ? "now()" : "NULL") + ")");
    }

    private static String evento(Statement s, UUID clinica) throws SQLException {
        try (ResultSet rs = s.executeQuery("INSERT INTO saas.evento_auditoria(ator_papel, clinica_id, acao, recurso_tipo) "
                + "VALUES ('ADMIN', '" + clinica + "', 'LEITURA', 'ENCAMINHAMENTO') RETURNING id::text")) {
            rs.next();
            return rs.getString(1);
        }
    }

    // ------------------------------------------------------------- F7.1 / F7.2

    @Test
    void adminVeSoAAuditoriaDaPropriaClinica() throws Exception {
        assertThat(ids(auditoria(ADMIN_A, CLINICA_A, "ADMIN"))).isEqualTo(EVENTOS_A);
        assertThat(ids(auditoria(ADMIN_B, CLINICA_B, "ADMIN"))).isEqualTo(EVENTOS_B);
    }

    @Test
    void semVinculoClinicaAlheiaOuSemSessaoNaoVeNada() throws Exception {
        assertThat(auditoria(ADMIN_A, CLINICA_B, "ADMIN")).satisfies(r -> semEventos(r));
        assertThat(auditoria(RECEPCAO_A, CLINICA_A, "ADMIN")).satisfies(r -> semEventos(r));
        assertThat(auditoria(RECEPCAO_A, CLINICA_A, "RECEPCAO")).satisfies(r -> semEventos(r));
        assertThat(auditoria(ADMIN_A, CLINICA_A, "MEDICO")).satisfies(r -> semEventos(r));
        assertThat(auditoria(ADMIN_A, null, "ADMIN").statusCode()).isIn(401, 403);
        assertThat(auditoria(ADMIN_A, CLINICA_A, null).statusCode()).isIn(401, 403);
        assertThat(auditoria(ADMIN_A, CLINICA_A, "SISTEMA").statusCode()).isIn(401, 403);
        assertThat(auditoria(null, CLINICA_A, "ADMIN").statusCode()).isEqualTo(401);
        assertThat(auditoria(INEXISTENTE, CLINICA_A, "ADMIN").statusCode()).isEqualTo(401);
        assertThat(auditoria(ENCERRADA, CLINICA_A, "ADMIN").statusCode()).isEqualTo(401);
        assertThat(auditoria("'; select 1; --", CLINICA_A, "ADMIN").statusCode()).isEqualTo(401);
        HttpResponse<String> r = auditoria(ADMIN_A, CLINICA_A, "ADMIN");
        assertThat(r.headers().firstValue("Cache-Control").orElse("")).contains("no-store");
    }

    // ------------------------------------------------------------- F7.3

    @Test
    void poolDeUmaConexaoAlternadoNuncaHerdaContexto() throws Exception {
        assertThat(contexto.getBeanNamesForType(HikariDataSource.class)).isEmpty();
        assertThat(cru().getMaximumPoolSize()).isEqualTo(1);
        List<String> falhas = new ArrayList<>();
        for (int i = 0; i < 40; i++) {
            confere(i % 5, falhas);
        }
        assertThat(falhas).isEmpty();
        assertThat(contextoDaConexaoForaDeTransacao()).isEqualTo("||");
    }

    @Test
    void poolDeUmaConexaoConcorrenteNuncaHerdaContexto() throws Exception {
        ExecutorService exec = Executors.newFixedThreadPool(6);
        List<String> falhas = Collections.synchronizedList(new ArrayList<>());
        try {
            List<Future<?>> fs = new ArrayList<>();
            for (int t = 0; t < 6; t++) {
                int fio = t;
                fs.add(exec.submit((Callable<Void>) () -> {
                    for (int i = 0; i < 20; i++) {
                        confere((fio + i) % 5, falhas);
                    }
                    return null;
                }));
            }
            for (Future<?> f : fs) {
                f.get();
            }
        } finally {
            exec.shutdownNow();
        }
        assertThat(falhas).isEmpty();
        assertThat(contextoDaConexaoForaDeTransacao()).isEqualTo("||");
    }

    @Test
    void conexaoSujaEhDescartadaDoPoolENaoSoRecusada() throws Exception {
        // Simula um SET de sessão que vazou na única conexão do pool (o código nunca faz isso),
        // pela conexão crua do Hikari: pelo pool guardado nem isso é possível sem contexto.
        int pidSujo;
        try (Connection c = cru().getConnection(); Statement s = c.createStatement()) {
            s.execute("SELECT set_config('app.sessao', 'residuo', false), "
                    + "set_config('app.clinica_id', '" + CLINICA_A + "', false), set_config('app.papel', 'ADMIN', false)");
            try (ResultSet rs = s.executeQuery("SELECT pg_backend_pid()")) {
                rs.next();
                pidSujo = rs.getInt(1);
            }
        }
        HttpResponse<String> r = auditoria(ADMIN_B, CLINICA_B, "ADMIN");
        assertThat(r.statusCode()).isIn(401, 403);
        assertThat(r.body()).doesNotContain(EVENTOS_A.iterator().next());
        // Sem limpeza manual: a conexão suja saiu do pool e a seguinte já vem limpa.
        assertThat(ids(auditoria(ADMIN_A, CLINICA_A, "ADMIN"))).isEqualTo(EVENTOS_A);
        assertThat(ids(auditoria(ADMIN_B, CLINICA_B, "ADMIN"))).isEqualTo(EVENTOS_B);
        assertThat(contextoDaConexaoForaDeTransacao()).isEqualTo("||");
        int pidNovo = new JdbcTemplate(cru()).queryForObject("SELECT pg_backend_pid()", Integer.class);
        assertThat(pidNovo).isNotEqualTo(pidSujo);
        boolean fechou = false;
        for (int i = 0; i < 50 && !fechou; i++) {
            try (Connection c = superusuario(); Statement s = c.createStatement();
                    ResultSet rs = s.executeQuery("SELECT count(*) FROM pg_stat_activity WHERE pid = " + pidSujo)) {
                rs.next();
                fechou = rs.getInt(1) == 0;
            }
            if (!fechou) {
                Thread.sleep(100);
            }
        }
        assertThat(fechou).as("conexao suja fechada no servidor").isTrue();
    }

    @Test
    void transactionalComumSemContextoNaoConsegueConsultar() {
        // Falha fechada: SQL por saas_app fora do executor do ContextoBanco é recusado pelo pool.
        assertThatThrownBy(() -> servicoComum.contaEventos())
                .rootCause().isInstanceOf(SQLException.class)
                .satisfies(e -> assertThat(((SQLException) e).getSQLState()).isEqualTo("42501"));
        assertThatThrownBy(() -> servicoComum.sessaoAtual()).rootCause().isInstanceOf(SQLException.class);
        assertThatThrownBy(() -> app.queryForObject("SELECT 1", Integer.class)).rootCause().isInstanceOf(SQLException.class);
        assertThatThrownBy(() -> {
            try (Connection c = dataSource.getConnection(); Statement s = c.createStatement()) {
                s.executeQuery("SELECT 1").close();
            }
        }).isInstanceOf(SQLException.class);
        assertThatThrownBy(() -> dataSource.unwrap(HikariDataSource.class)).isInstanceOf(SQLException.class);
        assertThatThrownBy(() -> {
            try (Connection c = dataSource.getConnection()) {
                c.unwrap(Connection.class);
            }
        }).isInstanceOf(SQLException.class);
        // Nem dentro da transação com contexto: só o executor entregue a ela consulta.
        assertThatThrownBy(() -> contextoBanco.emTransacao(ContextoAcesso.daEquipe(ADMIN_A, CLINICA_A, "ADMIN"),
                consulta -> app.queryForObject("SELECT count(*) FROM saas.evento_auditoria", Integer.class)))
                .rootCause().isInstanceOf(SQLException.class);
        // O token não vale fora da transação em que nasceu, nem em outra transação.
        ConsultaContexto[] vazado = new ConsultaContexto[1];
        contextoBanco.emTransacao(ContextoAcesso.daEquipe(ADMIN_A, CLINICA_A, "ADMIN"), consulta -> {
            vazado[0] = consulta;
            return null;
        });
        assertThatThrownBy(() -> vazado[0].tipoAtor()).isInstanceOf(IllegalStateException.class);
        assertThatThrownBy(() -> contextoBanco.emTransacao(ContextoAcesso.daEquipe(ADMIN_B, CLINICA_B, "ADMIN"),
                consulta -> vazado[0].queryForList("SELECT id FROM saas.evento_auditoria", String.class)))
                .isInstanceOf(IllegalStateException.class);
        // Controle positivo: pelo executor da própria transação a consulta passa.
        Integer n = contextoBanco.emTransacao(ContextoAcesso.daEquipe(ADMIN_A, CLINICA_A, "ADMIN"),
                consulta -> consulta.queryForObject("SELECT count(*)::int FROM saas.evento_auditoria", Integer.class));
        assertThat(n).isEqualTo(EVENTOS_A.size());
    }

    @Test
    void auditoriaPaginaComLimiteConfiguravelECursor() throws Exception {
        HttpResponse<String> p1 = auditoria(ADMIN_A, CLINICA_A, "ADMIN", "?limite=2");
        assertThat(ids(p1)).hasSize(2);
        String cursor = p1.headers().firstValue("X-Proxima-Pagina").orElseThrow();
        HttpResponse<String> p2 = auditoria(ADMIN_A, CLINICA_A, "ADMIN", "?limite=2&depoisDe=" + cursor);
        assertThat(ids(p2)).hasSize(1);
        assertThat(p2.headers().firstValue("X-Proxima-Pagina")).isEmpty();
        Set<String> todos = new TreeSet<>(ids(p1));
        todos.addAll(ids(p2));
        assertThat(todos).isEqualTo(EVENTOS_A);
        // Acima do teto é reduzido ao teto; sem parâmetro, a primeira página do contrato.
        assertThat(ids(auditoria(ADMIN_A, CLINICA_A, "ADMIN", "?limite=100000"))).isEqualTo(EVENTOS_A);
        assertThat(auditoria(ADMIN_A, CLINICA_A, "ADMIN").headers().firstValue("X-Proxima-Pagina")).isEmpty();
        for (String ruim : List.of("?limite=0", "?limite=-1", "?limite=abc", "?depoisDe=x'%3B--")) {
            assertThat(auditoria(ADMIN_A, CLINICA_A, "ADMIN", ruim).statusCode()).as(ruim).isEqualTo(400);
        }
        // Cursor de outra clínica não vaza nada.
        String alheio = EVENTOS_B.iterator().next();
        assertThat(ids(auditoria(ADMIN_A, CLINICA_A, "ADMIN", "?depoisDe=" + alheio))).isEmpty();
    }

    @Test
    void saudeResponde200ComPoolGuardado() throws Exception {
        HttpResponse<String> r = http.send(HttpRequest.newBuilder(
                URI.create("http://127.0.0.1:" + porta + "/actuator/health")).GET().build(),
                HttpResponse.BodyHandlers.ofString());
        assertThat(r.statusCode()).isEqualTo(200);
        assertThat(r.body()).contains("UP");
    }

    @Test
    void contextoEhUmPorTransacaoEExigeSessao() {
        assertThatThrownBy(() -> contextoBanco.emTransacao(ContextoAcesso.daSessao(INEXISTENTE), c -> "x"))
                .isInstanceOf(ContextoBanco.SemSessaoException.class);
        String tipo = contextoBanco.emTransacao(ContextoAcesso.daEquipe(ADMIN_A, CLINICA_A, "ADMIN"), consulta -> {
            assertThatThrownBy(() -> contextoBanco.emTransacao(ContextoAcesso.daSessao(ADMIN_B), c -> "aninhado"))
                    .isInstanceOf(IllegalStateException.class);
            assertThat(consulta.queryForObject("SELECT current_setting('app.clinica_id', true)", String.class))
                    .isEqualTo(CLINICA_A.toString());
            return consulta.tipoAtor();
        });
        assertThat(tipo).isEqualTo("EQUIPE");
        assertThat(contextoDaConexaoForaDeTransacao()).isEqualTo("||");
        assertThat(ContextoAcesso.daEquipe(ADMIN_A, CLINICA_A, "ADMIN").toString()).doesNotContain(ADMIN_A);
        assertThatThrownBy(() -> ContextoAcesso.daSessao("'; drop table x; --")).isInstanceOf(IllegalArgumentException.class);
    }

    // ------------------------------------------------------------- F7.4 / F7.5 (I-20)

    @Test
    void i20NenhumTokenNoLogNemEmPgStatStatements() throws Exception {
        assertThat(auditoria(ADMIN_A, CLINICA_A, "ADMIN").statusCode()).isEqualTo(200);
        assertThat(auditoria(ADMIN_B, CLINICA_B, "ADMIN").statusCode()).isEqualTo(200);
        assertThat(auditoria(RECEPCAO_A, CLINICA_A, "RECEPCAO").statusCode()).isEqualTo(200);
        assertThat(auditoria(INEXISTENTE, CLINICA_A, "ADMIN").statusCode()).isEqualTo(401);
        String log = PG.getLogs();
        // Controle positivo: o log do servidor registra os comandos de saas_app, com o marcador $1.
        Pattern aplica = Pattern.compile("set_config\\('app\\.sessao', \\$1, true\\), "
                + "set_config\\('app\\.clinica_id', \\$2, true\\), set_config\\('app\\.papel', \\$3, true\\)");
        assertThat(aplica.matcher(log).find()).as("log_statement=all registra o set_config parametrizado").isTrue();
        for (String t : List.of(ADMIN_A, ADMIN_B, RECEPCAO_A, INEXISTENTE)) {
            assertThat(log).doesNotContain(t);
        }
        // Nenhum set_config no log com literal no lugar do parâmetro, nem com false.
        Matcher m = Pattern.compile("set_config\\(('app\\.[^)]*)\\)").matcher(log);
        List<String> ruins = new ArrayList<>();
        while (m.find()) {
            if (!m.group(1).matches("'app\\.(sessao|clinica_id|papel)', \\$\\d+, true")
                    && !m.group(1).contains(", false")) {
                ruins.add(m.group());
            }
        }
        assertThat(ruins).isEmpty();
        assertThat(log).doesNotContainPattern("(?i)\\bSET\\s+(LOCAL\\s+)?app\\.");

        List<String> consultas = new ArrayList<>();
        try (Connection c = superusuario(); Statement s = c.createStatement();
                ResultSet rs = s.executeQuery("SELECT query FROM pg_stat_statements")) {
            while (rs.next()) {
                consultas.add(rs.getString(1));
            }
        }
        // pg_stat_statements normaliza literais em $n: a prova aqui é só a ausência do token.
        assertThat(consultas).anyMatch(q -> q.contains("set_config("));
        for (String q : consultas) {
            for (String t : List.of(ADMIN_A, ADMIN_B, RECEPCAO_A, INEXISTENTE)) {
                assertThat(q).doesNotContain(t);
            }
        }
    }

    // ------------------------------------------------------------- F7.8 (E-09)

    @Test
    void processoWebIgnoraCredencialDeJobs() throws Exception {
        assertThat(contexto.getBeanNamesForType(JobsApi.class)).isEmpty();
        assertThat(auditoria(ADMIN_A, CLINICA_A, "ADMIN").statusCode()).isEqualTo(200);
        try (Connection c = superusuario(); Statement s = c.createStatement();
                ResultSet rs = s.executeQuery("SELECT count(*) FROM pg_stat_activity WHERE usename = 'saas_jobs'")) {
            rs.next();
            assertThat(rs.getInt(1)).isZero();
        }
        assertThat(new JdbcTemplate(cru()).queryForObject("SELECT session_user::text", String.class)).isEqualTo("saas_app");
    }

    // ------------------------------------------------------------- apoio

    private void confere(int caso, List<String> falhas) throws Exception {
        HttpResponse<String> r;
        switch (caso) {
            case 0 -> {
                r = auditoria(ADMIN_A, CLINICA_A, "ADMIN");
                if (r.statusCode() != 200 || !ids(r).equals(EVENTOS_A)) {
                    falhas.add("A:" + r.statusCode() + ":" + r.body());
                }
            }
            case 1 -> {
                r = auditoria(ADMIN_B, CLINICA_B, "ADMIN");
                if (r.statusCode() != 200 || !ids(r).equals(EVENTOS_B)) {
                    falhas.add("B:" + r.statusCode() + ":" + r.body());
                }
            }
            case 2 -> {
                r = auditoria(RECEPCAO_A, CLINICA_A, "ADMIN");
                if (!(r.statusCode() == 200 && ids(r).isEmpty()) && r.statusCode() != 401 && r.statusCode() != 403) {
                    falhas.add("papel falso:" + r.statusCode() + ":" + r.body());
                }
            }
            case 3 -> {
                r = auditoria(null, CLINICA_A, "ADMIN");
                if (r.statusCode() != 401) {
                    falhas.add("sem sessao:" + r.statusCode());
                }
            }
            default -> {
                r = auditoria(INEXISTENTE, CLINICA_B, "ADMIN");
                if (r.statusCode() != 401) {
                    falhas.add("inexistente:" + r.statusCode());
                }
            }
        }
    }

    /** O Hikari cru por trás do pool guardado (só o teste chega a ele, por reflexão). */
    private HikariDataSource cru() {
        try {
            java.lang.reflect.Field f = dataSource.getClass().getDeclaredField("pool");
            f.setAccessible(true);
            return (HikariDataSource) f.get(dataSource);
        } catch (ReflectiveOperationException e) {
            throw new IllegalStateException(e);
        }
    }

    private String contextoDaConexaoForaDeTransacao() {
        return new JdbcTemplate(cru()).queryForObject("SELECT coalesce(current_setting('app.sessao', true), '') || '|' "
                + "|| coalesce(current_setting('app.clinica_id', true), '') || '|' "
                + "|| coalesce(current_setting('app.papel', true), '')", String.class);
    }

    private static void semEventos(HttpResponse<String> r) {
        if (r.statusCode() == 200) {
            assertThat(ids(r)).isEmpty();
        } else {
            assertThat(r.statusCode()).isIn(401, 403);
        }
        for (String id : EVENTOS_A) {
            assertThat(r.body()).doesNotContain(id);
        }
        for (String id : EVENTOS_B) {
            assertThat(r.body()).doesNotContain(id);
        }
    }

    private HttpResponse<String> auditoria(String token, UUID clinica, String papel) throws Exception {
        return auditoria(token, clinica, papel, "");
    }

    private HttpResponse<String> auditoria(String token, UUID clinica, String papel, String consulta) throws Exception {
        HttpRequest.Builder b = HttpRequest.newBuilder(URI.create("http://127.0.0.1:" + porta + "/api/auditoria" + consulta));
        if (token != null) {
            b.header("Cookie", "SESSAO=" + token);
        }
        if (clinica != null) {
            b.header("X-Clinica-Id", clinica.toString());
        }
        if (papel != null) {
            b.header("X-Papel", papel);
        }
        return http.send(b.GET().build(), HttpResponse.BodyHandlers.ofString());
    }

    private static Set<String> ids(HttpResponse<String> r) {
        assertThat(r.statusCode()).isEqualTo(200);
        assertThat(r.body()).startsWith("[").endsWith("]");
        Set<String> ids = new TreeSet<>();
        Matcher m = Pattern.compile("\\{\"id\":\"([0-9a-f-]{36})\"}").matcher(r.body());
        while (m.find()) {
            ids.add(m.group(1));
        }
        return ids;
    }

    /** O token nunca vai ao texto do SQL nem do teste (o log do servidor é conferido): só o hash. */
    private static String sha256(String tokenHex) {
        try {
            return HexFormat.of().formatHex(java.security.MessageDigest.getInstance("SHA-256")
                    .digest(HexFormat.of().parseHex(tokenHex)));
        } catch (java.security.NoSuchAlgorithmException e) {
            throw new IllegalStateException(e);
        }
    }

    private static Connection superusuario() throws SQLException {
        return DriverManager.getConnection(PG.getJdbcUrl(), PG.getUsername(), PG.getPassword());
    }

    private static String token() {
        byte[] b = new byte[32];
        new SecureRandom().nextBytes(b);
        return HexFormat.of().formatHex(b);
    }

    private static String senhaAleatoria() {
        byte[] b = new byte[24];
        new SecureRandom().nextBytes(b);
        return HexFormat.of().formatHex(b);
    }
}
