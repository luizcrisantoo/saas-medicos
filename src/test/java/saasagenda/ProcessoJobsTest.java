package saasagenda;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.SecureRandom;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;
import java.util.HexFormat;
import java.util.Map;
import java.util.TreeMap;
import javax.sql.DataSource;
import org.flywaydb.core.Flyway;
import org.junit.jupiter.api.AfterAll;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.Test;
import org.springframework.boot.builder.SpringApplicationBuilder;
import org.springframework.context.ConfigurableApplicationContext;
import org.springframework.security.oauth2.jwt.JwtDecoder;
import org.springframework.web.context.WebApplicationContext;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.utility.DockerImageName;
import saasagenda.identidade.ContextoBanco;
import saasagenda.identidade.FuncaoJobs;
import saasagenda.identidade.JobsApi;
import saasagenda.identidade.SessaoApi;

/**
 * F7.9 (E-09): o processo {@code SAAS_PROCESSO=jobs} sobe só com {@code SAAS_DB_JOBS_*}, sem
 * servidor HTTP, sem pool {@code saas_app}, sem {@code saas_auth} e sem configuração do Cognito;
 * conecta como {@code saas_jobs} e só chama funções {@code jobs_*}. Mesmo com as credenciais web e
 * auth presentes, nada delas é usado. Processo desconhecido não sobe. Dados fictícios.
 */
class ProcessoJobsTest {

    private static final DockerImageName IMAGEM = DockerImageName
            .parse("mirror.gcr.io/library/postgres:16-alpine")
            .asCompatibleSubstituteFor("postgres");
    static final PostgreSQLContainer<?> PG = new PostgreSQLContainer<>(IMAGEM);
    private static final String SENHA = senhaAleatoria();

    @BeforeAll
    static void prepara() throws Exception {
        PG.start();
        try (Connection c = superusuario(); Statement s = c.createStatement()) {
            s.execute(Files.readString(Path.of("infra/db/bootstrap.sql"), StandardCharsets.UTF_8));
            for (String papel : new String[] {"saas_migracao", "saas_app", "saas_jobs", "saas_auth"}) {
                s.execute("ALTER ROLE " + papel + " PASSWORD '" + SENHA + "'");
            }
        }
        Flyway.configure()
                .dataSource(PG.getJdbcUrl(), "saas_migracao", SENHA)
                .schemas("migracao").defaultSchema("migracao").createSchemas(false)
                .locations("classpath:db/migration")
                .load().migrate();
    }

    @AfterAll
    static void encerra() {
        PG.stop();
    }

    @Test
    void sobeSoComACredencialDeJobs() throws Exception {
        Map<String, Object> props = new TreeMap<>();
        props.put("SAAS_PROCESSO", "jobs");
        props.put("SAAS_DB_JOBS_URL", PG.getJdbcUrl());
        props.put("SAAS_DB_JOBS_USERNAME", "saas_jobs");
        props.put("SAAS_DB_JOBS_PASSWORD", SENHA);
        try (ConfigurableApplicationContext ctx = sobe(props)) {
            confereSoJobs(ctx);
        }
    }

    @Test
    void ignoraCredenciaisWebEAuthMesmoPresentes() throws Exception {
        Map<String, Object> props = new TreeMap<>();
        props.put("SAAS_PROCESSO", "jobs");
        props.put("SAAS_DB_JOBS_URL", PG.getJdbcUrl());
        props.put("SAAS_DB_JOBS_USERNAME", "saas_jobs");
        props.put("SAAS_DB_JOBS_PASSWORD", SENHA);
        props.put("spring.datasource.url", PG.getJdbcUrl());
        props.put("spring.datasource.username", "saas_app");
        props.put("spring.datasource.password", SENHA);
        props.put("SAAS_DB_AUTH_URL", PG.getJdbcUrl());
        props.put("SAAS_DB_AUTH_USERNAME", "saas_auth");
        props.put("SAAS_DB_AUTH_PASSWORD", SENHA);
        props.put("SAAS_AUTH_ISSUER", "https://cognito-idp.sa-east-1.amazonaws.com/sa-east-1_Ficticio");
        props.put("SAAS_AUTH_JWKS_URI", "http://127.0.0.1:9/jwks.json");
        props.put("SAAS_AUTH_CLIENT_IDS", "cliente-ficticio");
        try (ConfigurableApplicationContext ctx = sobe(props)) {
            confereSoJobs(ctx);
        }
    }

    @Test
    void credencialErradaOuProcessoDesconhecidoNaoSobe() {
        Map<String, Object> props = new TreeMap<>();
        props.put("SAAS_PROCESSO", "jobs");
        props.put("SAAS_DB_JOBS_URL", PG.getJdbcUrl());
        props.put("SAAS_DB_JOBS_USERNAME", "saas_app");
        props.put("SAAS_DB_JOBS_PASSWORD", SENHA);
        assertThatThrownBy(() -> sobe(props).close()).isInstanceOf(Exception.class);
        props.put("SAAS_DB_JOBS_USERNAME", "saas_jobs");
        props.put("SAAS_PROCESSO", "ambos");
        assertThatThrownBy(() -> sobe(props).close()).isInstanceOf(Exception.class);
        props.put("SAAS_PROCESSO", "jobs");
        props.put("SAAS_DB_JOBS_PASSWORD", "");
        assertThatThrownBy(() -> sobe(props).close()).isInstanceOf(Exception.class);
    }

    @Test
    void credencialDeJobsEhListaPositiva() {
        for (String ruim : new String[] {"postgres", "saas_owner", "saas_funcoes", "saas_migracao", "saas_auth", "outro"}) {
            Map<String, Object> props = jobs();
            props.put("SAAS_DB_JOBS_USERNAME", ruim);
            assertThatThrownBy(() -> sobe(props).close()).as(ruim).isInstanceOf(Exception.class);
        }
    }

    @Test
    void poolEBatimentoSaoConfiguracaoNomeadaComPadrao() throws Exception {
        try (ConfigurableApplicationContext ctx = sobe(jobs())) {
            assertThat(poolMaximo(ctx)).isEqualTo(2);
            assertThat(ctx.getEnvironment().getProperty("saas.jobs.batimento-segundos")).isEqualTo("30");
        }
        Map<String, Object> props = jobs();
        props.put("saas.jobs.pool.maximo", "3");
        props.put("saas.jobs.batimento-segundos", "5");
        try (ConfigurableApplicationContext ctx = sobe(props)) {
            assertThat(poolMaximo(ctx)).isEqualTo(3);
        }
        for (String[] ruim : new String[][] {{"saas.jobs.pool.maximo", "0"}, {"saas.jobs.pool.maximo", "11"},
                {"saas.jobs.batimento-segundos", "4"}, {"saas.jobs.batimento-segundos", "301"}}) {
            Map<String, Object> p = jobs();
            p.put(ruim[0], ruim[1]);
            assertThatThrownBy(() -> sobe(p).close()).as(ruim[0] + "=" + ruim[1]).isInstanceOf(Exception.class);
        }
    }

    private static Map<String, Object> jobs() {
        Map<String, Object> props = new TreeMap<>();
        props.put("SAAS_PROCESSO", "jobs");
        props.put("SAAS_DB_JOBS_URL", PG.getJdbcUrl());
        props.put("SAAS_DB_JOBS_USERNAME", "saas_jobs");
        props.put("SAAS_DB_JOBS_PASSWORD", SENHA);
        return props;
    }

    private static int poolMaximo(ConfigurableApplicationContext ctx) throws Exception {
        Object banco = ctx.getBean(JobsApi.class);
        java.lang.reflect.Field f = banco.getClass().getDeclaredField("jobs");
        f.setAccessible(true);
        return ((com.zaxxer.hikari.HikariDataSource) f.get(banco)).getMaximumPoolSize();
    }

    private static void confereSoJobs(ConfigurableApplicationContext ctx) throws Exception {
        assertThat(ctx).isNotInstanceOf(WebApplicationContext.class);
        assertThat(ctx.getBeanNamesForType(DataSource.class)).isEmpty();
        assertThat(ctx.getBeanNamesForType(SessaoApi.class)).isEmpty();
        assertThat(ctx.getBeanNamesForType(ContextoBanco.class)).isEmpty();
        assertThat(ctx.getBeanNamesForType(JwtDecoder.class)).isEmpty();
        JobsApi jobs = ctx.getBean(JobsApi.class);
        assertThat(conexoes("saas_jobs")).isPositive();
        assertThat(conexoes("saas_app")).isZero();
        assertThat(conexoes("saas_auth")).isZero();
        // Só funções jobs_*: a fila vazia responde, pela credencial de jobs.
        Integer linhas = jobs.chamar(FuncaoJobs.ENVIOS_PENDENTES, rs -> {
            int n = 0;
            while (rs.next()) {
                n++;
            }
            return n;
        }, 10);
        assertThat(linhas).isZero();
        Integer expirados = jobs.chamar(FuncaoJobs.EXPIRAR_ENCAMINHAMENTOS, rs -> rs.next() ? rs.getInt(1) : -1);
        assertThat(expirados).isZero();
        assertThatThrownBy(() -> jobs.chamar(FuncaoJobs.ENVIO_PREPARA, rs -> null))
                .isInstanceOf(IllegalArgumentException.class);
    }

    private static ConfigurableApplicationContext sobe(Map<String, Object> entrada) {
        // Argumentos de linha de comando vencem o ambiente do runner; as chaves em minúsculas
        // também, porque o Spring liga SAAS_DB_JOBS_URL do ambiente direto a saas.db.jobs.url.
        Map<String, Object> props = new TreeMap<>(entrada);
        for (Map.Entry<String, Object> e : entrada.entrySet()) {
            if (e.getKey().startsWith("SAAS_DB_") || e.getKey().startsWith("SAAS_AUTH_")) {
                props.put(e.getKey().toLowerCase(java.util.Locale.ROOT).replace('_', '.')
                        .replace("jwks.uri", "jwks-uri").replace("client.ids", "client-ids"), e.getValue());
            }
        }
        String[] args = props.entrySet().stream().map(e -> "--" + e.getKey() + "=" + e.getValue()).toArray(String[]::new);
        return new SpringApplicationBuilder(Aplicacao.class)
                .properties("spring.main.keep-alive=false")
                .run(args);
    }

    private static int conexoes(String papel) throws SQLException {
        try (Connection c = superusuario(); Statement s = c.createStatement();
                ResultSet rs = s.executeQuery("SELECT count(*) FROM pg_stat_activity WHERE usename = '" + papel + "'")) {
            rs.next();
            return rs.getInt(1);
        }
    }

    private static Connection superusuario() throws SQLException {
        return DriverManager.getConnection(PG.getJdbcUrl(), PG.getUsername(), PG.getPassword());
    }

    private static String senhaAleatoria() {
        byte[] b = new byte[24];
        new SecureRandom().nextBytes(b);
        return HexFormat.of().formatHex(b);
    }
}
