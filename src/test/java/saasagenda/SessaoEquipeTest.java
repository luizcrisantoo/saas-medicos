package saasagenda;

import static org.assertj.core.api.Assertions.assertThat;

import com.nimbusds.jose.JOSEObjectType;
import com.nimbusds.jose.JWSAlgorithm;
import com.nimbusds.jose.JWSHeader;
import com.nimbusds.jose.crypto.MACSigner;
import com.nimbusds.jose.crypto.RSASSASigner;
import com.nimbusds.jose.jwk.JWKSet;
import com.nimbusds.jose.jwk.RSAKey;
import com.nimbusds.jose.jwk.gen.RSAKeyGenerator;
import com.nimbusds.jwt.JWTClaimsSet;
import com.nimbusds.jwt.PlainJWT;
import com.nimbusds.jwt.SignedJWT;
import com.sun.net.httpserver.HttpServer;
import java.io.OutputStream;
import java.net.InetSocketAddress;
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
import java.util.Date;
import java.util.HexFormat;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.function.Consumer;
import org.flywaydb.core.Flyway;
import org.junit.jupiter.api.AfterAll;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.system.CapturedOutput;
import org.springframework.boot.test.system.OutputCaptureExtension;
import org.springframework.boot.test.web.server.LocalServerPort;
import org.springframework.context.ApplicationContext;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.utility.DockerImageName;

/**
 * F6: access token do Cognito (RS256 pela JWKS local) abre sessão de equipe no banco por
 * {@code saas_auth}; consulta e logout por {@code saas_app}; matriz de tokens inválidos não cria
 * sessão; cookie opaco, HttpOnly, Secure, SameSite=Strict; nada de JWT ou cookie no log.
 * Dados fictícios.
 */
@ExtendWith(OutputCaptureExtension.class)
// Processo web fixo: o SAAS_PROCESSO do ambiente de quem roda a suíte não muda o teste.
@ActiveProfiles("web")
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class SessaoEquipeTest {

    private static final DockerImageName IMAGEM = DockerImageName
            .parse("mirror.gcr.io/library/postgres:16-alpine")
            .asCompatibleSubstituteFor("postgres");
    static final PostgreSQLContainer<?> PG = new PostgreSQLContainer<>(IMAGEM);

    private static final String SENHA = senhaAleatoria();
    private static final String ISSUER = "https://cognito-idp.sa-east-1.amazonaws.com/sa-east-1_Ficticio";
    private static final String CLIENTE = "cliente-ficticio-1";
    private static final String SUB_ATIVO = "11111111-1111-4111-8111-111111111111";
    private static final String SUB_INATIVO = "22222222-2222-4222-8222-222222222222";
    private static final String SUB_INEXISTENTE = "33333333-3333-4333-8333-333333333333";

    private static RSAKey chave;
    private static RSAKey outraChave;
    private static HttpServer jwks;

    @LocalServerPort
    int porta;

    @Autowired
    ApplicationContext contexto;

    private final HttpClient http = HttpClient.newHttpClient();

    @DynamicPropertySource
    static void ambiente(DynamicPropertyRegistry r) throws Exception {
        PG.start();
        prepara();
        r.add("spring.datasource.url", PG::getJdbcUrl);
        r.add("spring.datasource.username", () -> "saas_app");
        r.add("spring.datasource.password", () -> SENHA);
        r.add("saas.db.auth.url", PG::getJdbcUrl);
        r.add("saas.db.auth.username", () -> "saas_auth");
        r.add("saas.db.auth.password", () -> SENHA);
        r.add("saas.auth.issuer", () -> ISSUER);
        r.add("saas.auth.jwks-uri", () -> "http://127.0.0.1:" + jwks.getAddress().getPort() + "/jwks.json");
        r.add("saas.auth.client-ids", () -> "outro-cliente, " + CLIENTE);
    }

    private static void prepara() throws Exception {
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
        try (Connection c = superusuario(); Statement s = c.createStatement()) {
            s.execute("INSERT INTO saas.usuario(sub_oidc, nome, email, ativo) VALUES "
                    + "('" + SUB_ATIVO + "', 'Recepcao Ficticia', 'rec@exemplo.invalid', true), "
                    + "('" + SUB_INATIVO + "', 'Inativo Ficticio', 'ina@exemplo.invalid', false)");
        }
        chave = new RSAKeyGenerator(2048).keyID("chave-1").generate();
        outraChave = new RSAKeyGenerator(2048).keyID("chave-2").generate();
        RSAKey desconhecida = new RSAKeyGenerator(2048).keyID("chave-x").generate();
        assertThat(desconhecida.getKeyID()).isNotIn(chave.getKeyID(), outraChave.getKeyID());
        byte[] corpo = new JWKSet(List.of(chave.toPublicJWK(), outraChave.toPublicJWK())).toString()
                .getBytes(StandardCharsets.UTF_8);
        jwks = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
        jwks.createContext("/jwks.json", ex -> {
            ex.getResponseHeaders().add("Content-Type", "application/json");
            ex.sendResponseHeaders(200, corpo.length);
            try (OutputStream o = ex.getResponseBody()) {
                o.write(corpo);
            }
        });
        jwks.start();
    }

    @AfterAll
    static void encerra() {
        if (jwks != null) {
            jwks.stop(0);
        }
    }

    // ------------------------------------------------------------- F6.1 / F6.2

    @Test
    void sobeEHealthResponde() throws Exception {
        assertThat(contexto.getBean(Aplicacao.class)).isNotNull();
        assertThat(http.send(get("/actuator/health").build(), HttpResponse.BodyHandlers.ofString()).statusCode())
                .isEqualTo(200);
    }

    @Test
    void tokenValidoAbreSessaoComCookieSeguroEOpaco(CapturedOutput saida) throws Exception {
        String jwt = assina(chave, claims(SUB_ATIVO, c -> { }));
        int antes = sessoes();
        HttpResponse<String> r = abre(jwt);
        assertThat(r.statusCode()).isIn(200, 201, 204);
        String setCookie = r.headers().firstValue("Set-Cookie").orElseThrow();
        String token = valorCookie(setCookie);
        assertThat(token).matches("[0-9a-f]{64}").isNotEqualTo(jwt);
        assertThat(setCookie).contains("HttpOnly").contains("Secure").contains("SameSite=Strict").contains("Path=/");
        assertThat(sessoes()).isEqualTo(antes + 1);
        assertThat(texto("SELECT count(*)::text FROM saas.sessao WHERE token_hash = sha256(decode('" + token
                + "', 'hex')) AND tipo = 'EQUIPE' AND encerrada_em IS NULL")).isEqualTo("1");

        HttpResponse<String> consulta = consulta(token);
        assertThat(consulta.statusCode()).isEqualTo(200);
        assertThat(consulta.body()).isEqualTo("{\"tipo\":\"EQUIPE\"}");

        assertThat(saida.getAll()).doesNotContain(jwt).doesNotContain(token).doesNotContain(SUB_ATIVO);
    }

    // ------------------------------------------------------------- F6.3

    @Test
    void matrizDeTokensInvalidosNaoCriaSessao(CapturedOutput saida) throws Exception {
        RSAKey desconhecida = new RSAKeyGenerator(2048).keyID("chave-x").generate();
        RSAKey outraComKidDaPrimeira = new RSAKeyGenerator(2048).keyID(chave.getKeyID()).generate();
        long agora = System.currentTimeMillis();
        Map<String, String> casos = new LinkedHashMap<>();
        casos.put("assinatura errada", assina(outraComKidDaPrimeira, claims(SUB_ATIVO, c -> { })));
        casos.put("kid desconhecido", assina(desconhecida, claims(SUB_ATIVO, c -> { })));
        casos.put("chave de outro kid", assinaComKid(outraChave, chave.getKeyID(), claims(SUB_ATIVO, c -> { })));
        casos.put("sem kid", assinaComKid(chave, null, claims(SUB_ATIVO, c -> { })));
        casos.put("iss errado", assina(chave, claims(SUB_ATIVO, c -> c.issuer("https://outro.exemplo.invalid"))));
        casos.put("iss com sufixo", assina(chave, claims(SUB_ATIVO, c -> c.issuer(ISSUER + "x"))));
        casos.put("iss com barra", assina(chave, claims(SUB_ATIVO, c -> c.issuer(ISSUER + "/"))));
        casos.put("client_id errado", assina(chave, claims(SUB_ATIVO, c -> c.claim("client_id", "intruso"))));
        casos.put("sem client_id", assina(chave, claims(SUB_ATIVO, c -> c.claim("client_id", null))));
        casos.put("aud alheio", assina(chave, claims(SUB_ATIVO, c -> c.audience("intruso"))));
        casos.put("expirado", assina(chave, claims(SUB_ATIVO, c -> c.expirationTime(new Date(agora - 120_000)))));
        casos.put("sem exp", assina(chave, claims(SUB_ATIVO, c -> c.expirationTime(null))));
        casos.put("nbf no futuro", assina(chave, claims(SUB_ATIVO, c -> c.notBeforeTime(new Date(agora + 600_000)))));
        casos.put("token_use=id", assina(chave, claims(SUB_ATIVO, c -> c.claim("token_use", "id"))));
        casos.put("sem token_use", assina(chave, claims(SUB_ATIVO, c -> c.claim("token_use", null))));
        casos.put("sem sub", assina(chave, claims(null, c -> { })));
        casos.put("alg none", new PlainJWT(claims(SUB_ATIVO, c -> { })).serialize());
        casos.put("HS256", hs256(claims(SUB_ATIVO, c -> { })));
        casos.put("malformado", "abc.def.ghi");
        casos.put("vazio", "");
        casos.put("usuario inexistente", assina(chave, claims(SUB_INEXISTENTE, c -> { })));
        casos.put("usuario inativo", assina(chave, claims(SUB_INATIVO, c -> { })));

        int antes = sessoes();
        List<String> aceitos = new ArrayList<>();
        for (Map.Entry<String, String> caso : casos.entrySet()) {
            HttpResponse<String> r = abre(caso.getValue());
            if (!(r.statusCode() == 401 || r.statusCode() == 403) || r.headers().firstValue("Set-Cookie").isPresent()) {
                aceitos.add(caso.getKey() + " -> " + r.statusCode());
            }
            assertThat(r.body()).doesNotContainIgnoringCase("exception").doesNotContain("saas.");
        }
        HttpResponse<String> semCabecalho = http.send(post("/api/sessao/equipe").build(), HttpResponse.BodyHandlers.ofString());
        assertThat(semCabecalho.statusCode()).isEqualTo(401);
        assertThat(aceitos).isEmpty();
        assertThat(sessoes()).isEqualTo(antes);

        // Controle positivo no mesmo critério: o mesmo emissor e chave com claims certas abre.
        assertThat(abre(assina(chave, claims(SUB_ATIVO, c -> { }))).statusCode()).isIn(200, 201, 204);
        assertThat(abre(assina(outraChave, claims(SUB_ATIVO, c -> c.claim("client_id", "outro-cliente"))))
                .statusCode()).isIn(200, 201, 204);
        assertThat(sessoes()).isEqualTo(antes + 2);
        for (String jwt : casos.values()) {
            if (!jwt.isEmpty()) {
                assertThat(saida.getAll()).doesNotContain(jwt);
            }
        }
    }

    // ------------------------------------------------------------- F6.4 / F6.5

    @Test
    void cookieInvalidoDa401SemDetalhe() throws Exception {
        for (String cookie : new String[] {null, "ab".repeat(32), "zz".repeat(32), "'; select 1; --", ""}) {
            HttpRequest.Builder b = get("/api/sessao");
            if (cookie != null) {
                b.header("Cookie", "SESSAO=" + cookie);
            }
            HttpResponse<String> r = http.send(b.build(), HttpResponse.BodyHandlers.ofString());
            assertThat(r.statusCode()).as(String.valueOf(cookie)).isEqualTo(401);
            assertThat(r.body()).doesNotContainIgnoringCase("exception").doesNotContain("saas").doesNotContain("sql");
        }
        String token = valorCookie(abre(assina(chave, claims(SUB_ATIVO, c -> { }))).headers()
                .firstValue("Set-Cookie").orElseThrow());
        assertThat(consulta(token).statusCode()).isEqualTo(200);
    }

    @Test
    void logoutEncerraNoBanco() throws Exception {
        String token = valorCookie(abre(assina(chave, claims(SUB_ATIVO, c -> { }))).headers()
                .firstValue("Set-Cookie").orElseThrow());
        String outro = valorCookie(abre(assina(chave, claims(SUB_ATIVO, c -> { }))).headers()
                .firstValue("Set-Cookie").orElseThrow());
        assertThat(consulta(token).statusCode()).isEqualTo(200);
        HttpResponse<String> r = http.send(get("/api/sessao").DELETE().header("Cookie", "SESSAO=" + token).build(),
                HttpResponse.BodyHandlers.ofString());
        assertThat(r.statusCode()).isIn(200, 204);
        assertThat(r.headers().firstValue("Set-Cookie").orElseThrow()).contains("Max-Age=0");
        assertThat(texto("SELECT (encerrada_em IS NOT NULL)::text FROM saas.sessao WHERE token_hash = sha256(decode('"
                + token + "', 'hex'))")).isEqualTo("true");
        assertThat(consulta(token).statusCode()).isEqualTo(401);
        assertThat(consulta(outro).statusCode()).isEqualTo(200);
    }

    // ------------------------------------------------------------- F6.7

    @Test
    void papeisDeBancoSeparados() throws Exception {
        String token = valorCookie(abre(assina(chave, claims(SUB_ATIVO, c -> { }))).headers()
                .firstValue("Set-Cookie").orElseThrow());
        assertThat(consulta(token).statusCode()).isEqualTo(200);
        assertThat(texto("SELECT string_agg(DISTINCT usename, ',' ORDER BY usename) FROM pg_stat_activity "
                + "WHERE application_name = 'PostgreSQL JDBC Driver' AND usename IN ('saas_app', 'saas_auth', 'saas_jobs')"))
                .isEqualTo("saas_app,saas_auth");
        // saas_auth não consulta a sessão; saas_app não abre sessão.
        try (Connection c = DriverManager.getConnection(PG.getJdbcUrl(), "saas_app", SENHA); Statement s = c.createStatement()) {
            org.assertj.core.api.Assertions.assertThatThrownBy(
                    () -> s.executeQuery("SELECT saas.sessao_equipe_abre('" + SUB_ATIVO + "')"))
                    .isInstanceOf(SQLException.class);
        }
        try (Connection c = DriverManager.getConnection(PG.getJdbcUrl(), "saas_auth", SENHA); Statement s = c.createStatement()) {
            org.assertj.core.api.Assertions.assertThatThrownBy(() -> s.executeQuery("SELECT saas.ator_tipo()"))
                    .isInstanceOf(SQLException.class);
        }
    }

    // ------------------------------------------------------------- apoio

    private static JWTClaimsSet claims(String sub, Consumer<JWTClaimsSet.Builder> ajuste) {
        long agora = System.currentTimeMillis();
        JWTClaimsSet.Builder b = new JWTClaimsSet.Builder()
                .issuer(ISSUER)
                .subject(sub)
                .claim("client_id", CLIENTE)
                .claim("token_use", "access")
                .claim("scope", "aws.cognito.signin.user.admin")
                .issueTime(new Date(agora - 1000))
                .expirationTime(new Date(agora + 600_000));
        ajuste.accept(b);
        return b.build();
    }

    private static String assina(RSAKey k, JWTClaimsSet c) throws Exception {
        return assinaComKid(k, k.getKeyID(), c);
    }

    private static String assinaComKid(RSAKey k, String kid, JWTClaimsSet c) throws Exception {
        JWSHeader.Builder h = new JWSHeader.Builder(JWSAlgorithm.RS256);
        if (kid != null) {
            h.keyID(kid);
        }
        SignedJWT jwt = new SignedJWT(h.build(), c);
        jwt.sign(new RSASSASigner(k));
        return jwt.serialize();
    }

    private static String hs256(JWTClaimsSet c) throws Exception {
        byte[] segredo = new byte[32];
        new SecureRandom().nextBytes(segredo);
        SignedJWT jwt = new SignedJWT(new JWSHeader.Builder(JWSAlgorithm.HS256).keyID(chave.getKeyID())
                .type(JOSEObjectType.JWT).build(), c);
        jwt.sign(new MACSigner(segredo));
        return jwt.serialize();
    }

    private HttpResponse<String> abre(String jwt) throws Exception {
        return http.send(post("/api/sessao/equipe").header("Authorization", "Bearer " + jwt).build(),
                HttpResponse.BodyHandlers.ofString());
    }

    private HttpResponse<String> consulta(String token) throws Exception {
        return http.send(get("/api/sessao").header("Cookie", "SESSAO=" + token).build(),
                HttpResponse.BodyHandlers.ofString());
    }

    private HttpRequest.Builder get(String rota) {
        return HttpRequest.newBuilder(URI.create("http://127.0.0.1:" + porta + rota));
    }

    private HttpRequest.Builder post(String rota) {
        return get(rota).POST(HttpRequest.BodyPublishers.noBody());
    }

    private static String valorCookie(String setCookie) {
        assertThat(setCookie).startsWith("SESSAO=");
        return setCookie.substring("SESSAO=".length(), setCookie.indexOf(';'));
    }

    private static int sessoes() throws SQLException {
        return Integer.parseInt(texto("SELECT count(*)::text FROM saas.sessao"));
    }

    private static String texto(String sql) throws SQLException {
        try (Connection c = superusuario(); Statement s = c.createStatement(); ResultSet rs = s.executeQuery(sql)) {
            rs.next();
            return rs.getString(1);
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
