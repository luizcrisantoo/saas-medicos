package saasagenda;

import static org.assertj.core.api.Assertions.assertThat;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.MessageDigest;
import java.security.SecureRandom;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;
import java.time.Instant;
import java.util.HexFormat;
import java.util.Map;
import java.util.UUID;
import org.flywaydb.core.Flyway;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.system.CapturedOutput;
import org.springframework.boot.test.system.OutputCaptureExtension;
import org.springframework.boot.test.web.server.LocalServerPort;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.utility.DockerImageName;
import saasagenda.arquivos.storage.AssinadorS3Test;

/**
 * F8 pela API: upload registra o anexo e devolve URL PUT SigV4 (sa-east-1, bucket do ambiente,
 * chave opaca do banco, SSE-KMS assinado, até 5 min); tipo e tamanho inválidos recusados sem
 * registro; caso alheio ou sem sessão recusado; download só de anexo LIMPO, com um EventoAuditoria
 * por URL emitida; auditoria falhando, nenhuma URL; nenhuma URL, chave ou credencial no log.
 * Assinatura recalculada sem nuvem ({@link AssinadorS3Test#confereAssinatura}). Dados fictícios.
 */
@ExtendWith(OutputCaptureExtension.class)
@ActiveProfiles("web")
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class AnexosTest {

    private static final DockerImageName IMAGEM = DockerImageName
            .parse("mirror.gcr.io/library/postgres:16-alpine")
            .asCompatibleSubstituteFor("postgres");
    static final PostgreSQLContainer<?> PG = new PostgreSQLContainer<>(IMAGEM);

    private static final String SENHA = aleatorio(24);
    private static final String BUCKET = "anexos-ficticio-teste";
    private static final String KMS = "arn:aws:kms:sa-east-1:000000000000:key/aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee";
    private static final UUID CLINICA_A = UUID.randomUUID();
    private static final UUID ESPECIALIDADE = UUID.randomUUID();
    private static final UUID MEDICO_1 = UUID.randomUUID();
    private static final UUID MEDICO_2 = UUID.randomUUID();
    private static final UUID CASO_1 = UUID.randomUUID();
    private static final UUID CASO_2 = UUID.randomUUID();
    private static final String ENC_1 = aleatorio(32);
    private static final String ENC_2 = aleatorio(32);
    private static final String ADMIN_A = aleatorio(32);
    private static final String HASH = HexFormat.of().formatHex(sha256("exame ficticio".getBytes(StandardCharsets.UTF_8)));

    static {
        // Credenciais fictícias pela cadeia padrão do SDK (o contrato usa as variáveis de ambiente).
        System.setProperty("aws.accessKeyId", AssinadorS3Test.ID);
        System.setProperty("aws.secretAccessKey", AssinadorS3Test.SEGREDO);
    }

    @LocalServerPort
    int porta;

    private final HttpClient http = HttpClient.newHttpClient();
    private final ObjectMapper json = new ObjectMapper();

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
        r.add("saas.auth.issuer", () -> "https://cognito-idp.sa-east-1.amazonaws.com/sa-east-1_Ficticio");
        r.add("saas.auth.jwks-uri", () -> "http://127.0.0.1:9/jwks.json");
        r.add("saas.auth.client-ids", () -> "cliente-ficticio");
        r.add("saas.s3.bucket", () -> BUCKET);
        r.add("saas.s3.kms-key-id", () -> KMS);
        r.add("saas.s3.regiao", () -> "sa-east-1");
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
        UUID admin = UUID.randomUUID();
        UUID paciente = UUID.randomUUID();
        try (Connection c = superusuario(); Statement s = c.createStatement()) {
            s.execute("INSERT INTO saas.clinica(id, nome) VALUES ('" + CLINICA_A + "', 'Clinica Ficticia A')");
            s.execute("INSERT INTO saas.especialidade(id, nome) VALUES ('" + ESPECIALIDADE + "', 'Especialidade Ficticia F8')");
            s.execute("INSERT INTO saas.usuario(id, sub_oidc, nome, email) VALUES "
                    + "('" + admin + "', 'sub-admin-f8', 'Admin Ficticio', 'adm@exemplo.invalid')");
            s.execute("INSERT INTO saas.usuario_clinica(usuario_id, clinica_id, papel) VALUES "
                    + "('" + admin + "', '" + CLINICA_A + "', 'ADMIN')");
            s.execute("INSERT INTO saas.profissional(id, crm, crm_uf, nome, canal_verificado_em) VALUES "
                    + "('" + MEDICO_1 + "', '900001', 'PE', 'Dr Ficticio Um', now()), "
                    + "('" + MEDICO_2 + "', '900002', 'PE', 'Dra Ficticia Dois', now())");
            s.execute("INSERT INTO saas.paciente(id, nome, telefone) VALUES ('" + paciente
                    + "', 'Paciente Ficticio', '+5581900000801')");
            s.execute("INSERT INTO saas.encaminhamento(id, profissional_origem_id, paciente_id, especialidade_destino_id, "
                    + "clinica_destino_id, motivo_cifrado, urgencia, expira_em) VALUES "
                    + "('" + CASO_1 + "', '" + MEDICO_1 + "', '" + paciente + "', '" + ESPECIALIDADE + "', '" + CLINICA_A
                    + "', '\\x00', 'ROTINA', now() + interval '10 days'), "
                    + "('" + CASO_2 + "', '" + MEDICO_2 + "', '" + paciente + "', '" + ESPECIALIDADE + "', NULL"
                    + ", '\\x00', 'ROTINA', now() + interval '10 days')");
            s.execute("INSERT INTO saas.sessao(token_hash, tipo, profissional_id, expira_em) VALUES "
                    + "(decode('" + hashToken(ENC_1) + "', 'hex'), 'ENCAMINHADOR', '" + MEDICO_1 + "', now() + interval '2 hours'), "
                    + "(decode('" + hashToken(ENC_2) + "', 'hex'), 'ENCAMINHADOR', '" + MEDICO_2 + "', now() + interval '2 hours')");
            s.execute("INSERT INTO saas.sessao(token_hash, tipo, usuario_id, expira_em) VALUES "
                    + "(decode('" + hashToken(ADMIN_A) + "', 'hex'), 'EQUIPE', '" + admin + "', now() + interval '2 hours')");
        }
    }

    // ------------------------------------------------------------- F8.1

    @Test
    void uploadValidoRegistraEAssinaPutComSseKms() throws Exception {
        Instant antes = Instant.now();
        HttpResponse<String> r = upload(ENC_1, CASO_1, "application/pdf", "1234", '"' + HASH + '"');
        assertThat(r.statusCode()).isIn(200, 201);
        assertThat(r.headers().firstValue("Cache-Control").orElse("")).contains("no-store");
        JsonNode b = json.readTree(r.body());
        UUID anexo = UUID.fromString(b.get("anexoId").asText());
        Map<String, String> anexoBanco = linha("SELECT chave_storage, status_varredura, tipo_mime, tamanho_bytes::text, "
                + "encode(sha256, 'hex'), enviado_por_tipo, enviado_por_id::text, encaminhamento_id::text "
                + "FROM saas.anexo_encaminhamento WHERE id = ?", anexo);
        String chave = anexoBanco.get("1");
        assertThat(chave).matches("[0-9a-f-]{36}");
        assertThat(anexoBanco).containsEntry("2", "PENDENTE").containsEntry("3", "application/pdf")
                .containsEntry("4", "1234").containsEntry("5", HASH).containsEntry("6", "PROFISSIONAL")
                .containsEntry("7", MEDICO_1.toString()).containsEntry("8", CASO_1.toString());
        URI url = URI.create(b.get("url").asText());
        assertThat(url.getHost()).isEqualTo(BUCKET + ".s3.sa-east-1.amazonaws.com");
        assertThat(url.getRawPath()).isEqualTo("/" + chave);
        Map<String, String> q = AssinadorS3Test.query(url);
        assertThat(Long.parseLong(q.get("X-Amz-Expires"))).isBetween(1L, 300L);
        assertThat(q.get("X-Amz-Credential")).endsWith("/sa-east-1/s3/aws4_request");
        Map<String, String> cab = json.convertValue(b.get("cabecalhos"),
                json.getTypeFactory().constructMapType(Map.class, String.class, String.class));
        assertThat(cab).containsEntry("x-amz-server-side-encryption", "aws:kms")
                .containsEntry("x-amz-server-side-encryption-aws-kms-key-id", KMS)
                .containsEntry("content-type", "application/pdf")
                .containsEntry("content-length", "1234");
        AssinadorS3Test.confereAssinatura("PUT", url, cab);
        Instant expira = Instant.parse(b.get("expiraEm").asText());
        assertThat(expira).isAfter(antes).isBefore(antes.plusSeconds(301));
    }

    // ------------------------------------------------------------- F8.2 / F8.3

    @Test
    void tipoForaDaListaRecusadoSemRegistro() throws Exception {
        long antes = anexos();
        for (String tipo : new String[] {"image/svg+xml", "application/pdf; charset=utf-8", "APPLICATION/PDF",
                "text/html", "image/gif", "application/octet-stream", "", " application/pdf"}) {
            HttpResponse<String> r = upload(ENC_1, CASO_1, json.writeValueAsString(tipo), "100", '"' + HASH + '"', true);
            assertThat(r.statusCode()).as(tipo).isBetween(400, 499);
            assertThat(r.body()).as(tipo).doesNotContain("amazonaws");
        }
        assertThat(anexos()).isEqualTo(antes);
    }

    @Test
    void tamanhoForaDosLimitesRecusadoELimitesAceitos() throws Exception {
        long antes = anexos();
        for (String t : new String[] {"0", "-1", "20971521", "99999999999999999999", "1.5", "\"10\"", "null"}) {
            HttpResponse<String> r = upload(ENC_1, CASO_1, "application/pdf", t, '"' + HASH + '"');
            assertThat(r.statusCode()).as(t).isBetween(400, 499);
        }
        assertThat(upload(ENC_1, CASO_1, "image/png", "1", '"' + HASH + '"').statusCode()).isIn(200, 201);
        assertThat(upload(ENC_1, CASO_1, "image/jpeg", "20971520", '"' + HASH + '"').statusCode()).isIn(200, 201);
        assertThat(upload(ENC_1, CASO_1, "image/jpeg", "10", "\"nao-e-hash\"").statusCode()).isBetween(400, 499);
        assertThat(anexos()).isEqualTo(antes + 2);
    }

    // ------------------------------------------------------------- F8.4

    @Test
    void uploadEmCasoQueOAtorNaoVeOuSemSessaoRecusado() throws Exception {
        long antes = anexos();
        assertThat(upload(ENC_2, CASO_1, "application/pdf", "100", '"' + HASH + '"').statusCode()).isIn(403, 404);
        assertThat(upload(null, CASO_1, "application/pdf", "100", '"' + HASH + '"').statusCode()).isEqualTo(401);
        assertThat(upload(aleatorio(32), CASO_1, "application/pdf", "100", '"' + HASH + '"').statusCode()).isEqualTo(401);
        assertThat(upload(ENC_1, UUID.randomUUID(), "application/pdf", "100", '"' + HASH + '"').statusCode()).isIn(403, 404);
        // Equipe da clínica destino sem consentimento não vê o caso.
        HttpRequest.Builder b = HttpRequest.newBuilder(URI.create(base() + "/api/encaminhamentos/" + CASO_1 + "/anexos"))
                .header("Cookie", "SESSAO=" + ADMIN_A).header("X-Clinica-Id", CLINICA_A.toString())
                .header("X-Papel", "ADMIN").header("Content-Type", "application/json")
                .POST(HttpRequest.BodyPublishers.ofString("{\"tipoMime\":\"application/pdf\",\"tamanhoBytes\":100,"
                        + "\"sha256\":\"" + HASH + "\"}"));
        assertThat(http.send(b.build(), HttpResponse.BodyHandlers.ofString()).statusCode()).isIn(403, 404);
        assertThat(anexos()).isEqualTo(antes);
    }

    // ------------------------------------------------------------- F8.5 a F8.9

    @Test
    void downloadSoDeLimpoComUmEventoPorUrlEAuditoriaObrigatoria(CapturedOutput saida) throws Exception {
        UUID pendente = novoAnexo();
        UUID limpo = novoAnexo();
        UUID infectado = novoAnexo();
        varre(limpo, "LIMPO");
        varre(infectado, "INFECTADO");

        for (UUID a : new UUID[] {pendente, infectado}) {
            HttpResponse<String> r = download(ENC_1, a);
            assertThat(r.statusCode()).isBetween(400, 499);
            assertThat(r.body()).doesNotContain("amazonaws");
        }
        assertThat(download(ENC_2, limpo).statusCode()).isIn(403, 404);
        assertThat(download(null, limpo).statusCode()).isEqualTo(401);
        assertThat(download(ENC_1, UUID.randomUUID()).statusCode()).isIn(403, 404);
        assertThat(eventos(limpo)).isZero();

        String chave = linha("SELECT chave_storage FROM saas.anexo_encaminhamento WHERE id = ?", limpo).get("1");
        Instant antes = Instant.now();
        HttpResponse<String> r = download(ENC_1, limpo);
        assertThat(r.statusCode()).isEqualTo(200);
        assertThat(r.headers().firstValue("Cache-Control").orElse("")).contains("no-store");
        JsonNode b = json.readTree(r.body());
        URI url = URI.create(b.get("url").asText());
        assertThat(url.getHost()).isEqualTo(BUCKET + ".s3.sa-east-1.amazonaws.com");
        assertThat(url.getRawPath()).isEqualTo("/" + chave);
        assertThat(Long.parseLong(AssinadorS3Test.query(url).get("X-Amz-Expires"))).isBetween(1L, 300L);
        AssinadorS3Test.confereAssinatura("GET", url, Map.of());
        assertThat(Instant.parse(b.get("expiraEm").asText())).isBefore(antes.plusSeconds(301));
        assertThat(eventos(limpo)).isEqualTo(1);
        assertThat(linha("SELECT ator_papel, ator_id::text, acao FROM saas.evento_auditoria WHERE recurso_id = ?", limpo))
                .containsEntry("1", "ENCAMINHADOR").containsEntry("2", MEDICO_1.toString())
                .containsEntry("3", "DOWNLOAD_ANEXO");
        assertThat(download(ENC_1, limpo).statusCode()).isEqualTo(200);
        assertThat(eventos(limpo)).isEqualTo(2);

        // Auditoria falhando: nenhuma URL e nenhum evento.
        try (Connection c = superusuario(); Statement s = c.createStatement()) {
            s.execute("CREATE FUNCTION public.falha_f8() RETURNS trigger LANGUAGE plpgsql AS "
                    + "$$ BEGIN RAISE EXCEPTION 'falha de auditoria simulada'; END $$");
            s.execute("CREATE TRIGGER falha_f8 BEFORE INSERT ON saas.evento_auditoria "
                    + "FOR EACH ROW EXECUTE FUNCTION public.falha_f8()");
        }
        try {
            HttpResponse<String> falha = download(ENC_1, limpo);
            assertThat(falha.statusCode()).isBetween(400, 599).isNotEqualTo(200);
            assertThat(falha.body()).doesNotContain("amazonaws").doesNotContain("X-Amz").doesNotContain("falha de auditoria");
        } finally {
            try (Connection c = superusuario(); Statement s = c.createStatement()) {
                s.execute("DROP TRIGGER falha_f8 ON saas.evento_auditoria");
                s.execute("DROP FUNCTION public.falha_f8()");
            }
        }
        assertThat(eventos(limpo)).isEqualTo(2);

        // Nada de URL assinada, chave do objeto ou credencial no log.
        String log = saida.getAll();
        assertThat(log).doesNotContain("X-Amz-Signature").doesNotContain("amazonaws.com/")
                .doesNotContain(chave).doesNotContain(AssinadorS3Test.SEGREDO).doesNotContain(ENC_1);
    }

    // ------------------------------------------------------------- apoio

    private UUID novoAnexo() throws Exception {
        HttpResponse<String> r = upload(ENC_1, CASO_1, "application/pdf", "2048", '"' + HASH + '"');
        assertThat(r.statusCode()).isIn(200, 201);
        return UUID.fromString(json.readTree(r.body()).get("anexoId").asText());
    }

    private static void varre(UUID anexo, String resultado) throws SQLException {
        try (Connection c = superusuario();
                PreparedStatement p = c.prepareStatement("SELECT saas.jobs_anexo_varredura(?, ?)")) {
            p.setObject(1, anexo);
            p.setString(2, resultado);
            p.execute();
        }
    }

    private HttpResponse<String> upload(String token, UUID caso, String tipo, String tamanho, String hash) throws Exception {
        return upload(token, caso, '"' + tipo + '"', tamanho, hash, true);
    }

    private HttpResponse<String> upload(String token, UUID caso, String tipoJson, String tamanho, String hash, boolean x)
            throws Exception {
        HttpRequest.Builder b = HttpRequest.newBuilder(URI.create(base() + "/api/encaminhamentos/" + caso + "/anexos"))
                .header("Content-Type", "application/json")
                .POST(HttpRequest.BodyPublishers.ofString("{\"tipoMime\":" + tipoJson + ",\"tamanhoBytes\":" + tamanho
                        + ",\"sha256\":" + hash + "}"));
        if (token != null) {
            b.header("Cookie", "SESSAO=" + token);
        }
        return http.send(b.build(), HttpResponse.BodyHandlers.ofString());
    }

    private HttpResponse<String> download(String token, UUID anexo) throws Exception {
        HttpRequest.Builder b = HttpRequest.newBuilder(URI.create(base() + "/api/anexos/" + anexo + "/download")).GET();
        if (token != null) {
            b.header("Cookie", "SESSAO=" + token);
        }
        return http.send(b.build(), HttpResponse.BodyHandlers.ofString());
    }

    private String base() {
        return "http://127.0.0.1:" + porta;
    }

    private static long anexos() throws SQLException {
        return Long.parseLong(linha("SELECT count(*)::text FROM saas.anexo_encaminhamento WHERE encaminhamento_id = ?",
                CASO_1).get("1"));
    }

    private static long eventos(UUID anexo) throws SQLException {
        return Long.parseLong(linha("SELECT count(*)::text FROM saas.evento_auditoria WHERE recurso_id = ?", anexo).get("1"));
    }

    private static Map<String, String> linha(String sql, Object param) throws SQLException {
        try (Connection c = superusuario(); PreparedStatement p = c.prepareStatement(sql)) {
            p.setObject(1, param);
            try (ResultSet rs = p.executeQuery()) {
                Map<String, String> r = new java.util.TreeMap<>();
                if (rs.next()) {
                    for (int i = 1; i <= rs.getMetaData().getColumnCount(); i++) {
                        r.put(String.valueOf(i), rs.getString(i));
                    }
                }
                return r;
            }
        }
    }

    private static Connection superusuario() throws SQLException {
        return DriverManager.getConnection(PG.getJdbcUrl(), PG.getUsername(), PG.getPassword());
    }

    private static byte[] sha256(byte[] b) {
        try {
            return MessageDigest.getInstance("SHA-256").digest(b);
        } catch (java.security.NoSuchAlgorithmException e) {
            throw new IllegalStateException(e);
        }
    }

    private static String hashToken(String tokenHex) {
        return HexFormat.of().formatHex(sha256(HexFormat.of().parseHex(tokenHex)));
    }

    private static String aleatorio(int bytes) {
        byte[] b = new byte[bytes];
        new SecureRandom().nextBytes(b);
        return HexFormat.of().formatHex(b);
    }
}
