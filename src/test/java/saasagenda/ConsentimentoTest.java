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
import java.time.Duration;
import java.time.Instant;
import java.util.HexFormat;
import java.util.Map;
import java.util.TreeMap;
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

/**
 * F9 pela API: texto versionado; concessão com paciente, caso, texto, canal e data do servidor
 * (campos forjados no corpo ignorados); recusas de finalidade, versão, caso e clínica; listagem do
 * caso da sessão; revogação idempotente que não toca consentimento alheio; clínica destino só vê o
 * caso com COMPARTILHAR_CASO ativo (ADR-0022). Dados fictícios.
 */
@ExtendWith(OutputCaptureExtension.class)
@ActiveProfiles("web")
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class ConsentimentoTest {

    private static final DockerImageName IMAGEM = DockerImageName
            .parse("mirror.gcr.io/library/postgres:16-alpine")
            .asCompatibleSubstituteFor("postgres");
    static final PostgreSQLContainer<?> PG = new PostgreSQLContainer<>(IMAGEM);

    private static final String SENHA = aleatorio(24);
    private static final UUID CLINICA_A = UUID.randomUUID();
    private static final UUID CLINICA_B = UUID.randomUUID();
    private static final UUID ESPECIALIDADE = UUID.randomUUID();
    private static final UUID MEDICO = UUID.randomUUID();
    private static final UUID PACIENTE_1 = UUID.randomUUID();
    private static final UUID PACIENTE_2 = UUID.randomUUID();
    /** Caso do paciente 1 com destino A (sessão PAC_1). */
    private static final UUID CASO_1 = UUID.randomUUID();
    /** Outro caso do mesmo paciente 1, destino A (sessão PAC_1B). */
    private static final UUID CASO_1B = UUID.randomUUID();
    /** Caso do paciente 2, destino A (sessão PAC_2). */
    private static final UUID CASO_2 = UUID.randomUUID();
    /** Caso do paciente 2 sem destino escolhido (sessão PAC_2S). */
    private static final UUID CASO_2S = UUID.randomUUID();
    private static final String PAC_1 = aleatorio(32);
    private static final String PAC_1B = aleatorio(32);
    private static final String PAC_2 = aleatorio(32);
    private static final String PAC_2S = aleatorio(32);
    private static final String ADMIN_A = aleatorio(32);
    private static final String ENC = aleatorio(32);

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
        try (Connection c = superusuario(); Statement s = c.createStatement()) {
            s.execute("INSERT INTO saas.clinica(id, nome) VALUES ('" + CLINICA_A + "', 'Clinica Ficticia A'), ('"
                    + CLINICA_B + "', 'Clinica Ficticia B')");
            s.execute("INSERT INTO saas.especialidade(id, nome) VALUES ('" + ESPECIALIDADE + "', 'Especialidade Ficticia F9')");
            s.execute("INSERT INTO saas.usuario(id, sub_oidc, nome, email) VALUES "
                    + "('" + admin + "', 'sub-admin-f9', 'Admin Ficticio', 'adm9@exemplo.invalid')");
            s.execute("INSERT INTO saas.usuario_clinica(usuario_id, clinica_id, papel) VALUES "
                    + "('" + admin + "', '" + CLINICA_A + "', 'ADMIN')");
            s.execute("INSERT INTO saas.profissional(id, crm, crm_uf, nome, canal_verificado_em) VALUES "
                    + "('" + MEDICO + "', '900091', 'PE', 'Dr Ficticio F9', now())");
            s.execute("INSERT INTO saas.paciente(id, nome, telefone) VALUES ('" + PACIENTE_1
                    + "', 'Paciente Ficticio Um', '+5581900000901'), ('" + PACIENTE_2
                    + "', 'Paciente Ficticia Dois', '+5581900000902')");
            caso(s, CASO_1, PACIENTE_1, CLINICA_A);
            caso(s, CASO_1B, PACIENTE_1, CLINICA_A);
            caso(s, CASO_2, PACIENTE_2, CLINICA_A);
            caso(s, CASO_2S, PACIENTE_2, null);
            sessaoPaciente(s, PAC_1, PACIENTE_1, CASO_1);
            sessaoPaciente(s, PAC_1B, PACIENTE_1, CASO_1B);
            sessaoPaciente(s, PAC_2, PACIENTE_2, CASO_2);
            sessaoPaciente(s, PAC_2S, PACIENTE_2, CASO_2S);
            s.execute("INSERT INTO saas.sessao(token_hash, tipo, usuario_id, expira_em) VALUES "
                    + "(decode('" + hashToken(ADMIN_A) + "', 'hex'), 'EQUIPE', '" + admin + "', now() + interval '2 hours')");
            s.execute("INSERT INTO saas.sessao(token_hash, tipo, profissional_id, expira_em) VALUES "
                    + "(decode('" + hashToken(ENC) + "', 'hex'), 'ENCAMINHADOR', '" + MEDICO + "', now() + interval '2 hours')");
        }
    }

    private static void caso(Statement s, UUID id, UUID paciente, UUID destino) throws SQLException {
        s.execute("INSERT INTO saas.encaminhamento(id, profissional_origem_id, paciente_id, especialidade_destino_id, "
                + "clinica_destino_id, motivo_cifrado, urgencia, expira_em) VALUES ('" + id + "', '" + MEDICO + "', '"
                + paciente + "', '" + ESPECIALIDADE + "', " + (destino == null ? "NULL" : "'" + destino + "'")
                + ", '\\x00', 'ROTINA', now() + interval '10 days')");
    }

    private static void sessaoPaciente(Statement s, String token, UUID paciente, UUID caso) throws SQLException {
        UUID link = UUID.randomUUID();
        s.execute("INSERT INTO saas.link_paciente(id, encaminhamento_id, paciente_id, token_hash, expira_em, usado_em) "
                + "VALUES ('" + link + "', '" + caso + "', '" + paciente + "', decode('" + aleatorio(32)
                + "', 'hex'), now() + interval '2 days', now())");
        s.execute("INSERT INTO saas.sessao(token_hash, tipo, paciente_id, link_paciente_id, expira_em) VALUES "
                + "(decode('" + hashToken(token) + "', 'hex'), 'PACIENTE', '" + paciente + "', '" + link
                + "', now() + interval '20 minutes')");
    }

    // ------------------------------------------------------------- F9.1

    @Test
    void termoVersionadoPublico() throws Exception {
        for (String f : new String[] {"AGENDAMENTO", "COMPARTILHAR_CASO", "COMUNICACAO_WHATSAPP"}) {
            HttpResponse<String> r = get("/api/termos/consentimento/" + f, null);
            assertThat(r.statusCode()).as(f).isEqualTo(200);
            JsonNode b = json.readTree(r.body());
            assertThat(b.get("finalidade").asText()).isEqualTo(f);
            assertThat(b.get("versao").asText()).matches("[1-9][0-9]*\\.[0-9a-f]{12}");
            assertThat(b.get("texto").asText()).isNotBlank();
            assertThat(json.readTree(get("/api/termos/consentimento/" + f, null).body()).get("versao").asText())
                    .isEqualTo(b.get("versao").asText());
        }
        assertThat(get("/api/termos/consentimento/MARKETING", null).statusCode()).isEqualTo(404);
        assertThat(get("/api/termos/consentimento/compartilhar_caso", null).statusCode()).isEqualTo(404);
    }

    // ------------------------------------------------------------- F9.2 / F9.3 / F9.6

    @Test
    void concessaoComDadosDoServidorCamposForjadosIgnoradosEDestinoSoVeComConsentimento(CapturedOutput saida)
            throws Exception {
        JsonNode termo = json.readTree(get("/api/termos/consentimento/COMPARTILHAR_CASO", null).body());
        String versao = termo.get("versao").asText();
        assertThat(destinoVe(CASO_1)).isFalse();

        Instant antes = Instant.now();
        HttpResponse<String> r = post(PAC_1, "{\"finalidade\":\"COMPARTILHAR_CASO\",\"encaminhamentoId\":\"" + CASO_1
                + "\",\"clinicaId\":\"" + CLINICA_A + "\",\"versao\":\"" + versao + "\","
                + "\"pacienteId\":\"" + PACIENTE_2 + "\",\"textoAceito\":\"texto forjado\",\"canal\":\"RECEPCAO\","
                + "\"aceitoEm\":\"2001-01-01T00:00:00Z\",\"data\":\"2001-01-01\",\"ator\":\"ADMIN\","
                + "\"atorId\":\"" + UUID.randomUUID() + "\",\"revogadoEm\":\"2001-01-02T00:00:00Z\"}");
        assertThat(r.statusCode()).isIn(200, 201);
        UUID id = UUID.fromString(json.readTree(r.body()).get("id").asText());
        Map<String, String> linha = linha("SELECT paciente_id::text, finalidade, encaminhamento_id::text, clinica_id::text, "
                + "texto_aceito, versao_texto, canal, extract(epoch FROM aceito_em)::bigint::text, "
                + "(revogado_em IS NULL)::text FROM saas.consentimento WHERE id = ?", id);
        assertThat(linha).containsEntry("1", PACIENTE_1.toString()).containsEntry("2", "COMPARTILHAR_CASO")
                .containsEntry("3", CASO_1.toString()).containsEntry("4", CLINICA_A.toString())
                .containsEntry("5", termo.get("texto").asText()).containsEntry("6", versao)
                .containsEntry("7", "SITE").containsEntry("9", "true");
        assertThat(Long.parseLong(linha.get("8"))).isBetween(antes.getEpochSecond() - 5, Instant.now().getEpochSecond() + 5);
        assertThat(linha("SELECT ator_papel, ator_id::text, acao FROM saas.evento_auditoria WHERE recurso_id = ?", id))
                .containsEntry("1", "PACIENTE").containsEntry("2", PACIENTE_1.toString())
                .containsEntry("3", "CONCEDER_CONSENTIMENTO");

        // F9.6: com o consentimento ativo a clínica destino vê o caso; outro caso não.
        assertThat(destinoVe(CASO_1)).isTrue();
        assertThat(destinoVe(CASO_1B)).isFalse();

        // Mesmo pedido de novo: o mesmo consentimento, sem linha nova.
        HttpResponse<String> de2 = post(PAC_1, "{\"finalidade\":\"COMPARTILHAR_CASO\",\"encaminhamentoId\":\"" + CASO_1
                + "\",\"clinicaId\":\"" + CLINICA_A + "\",\"versao\":\"" + versao + "\"}");
        assertThat(de2.statusCode()).isEqualTo(200);
        assertThat(json.readTree(de2.body()).get("id").asText()).isEqualTo(id.toString());
        assertThat(conta("SELECT count(*)::text FROM saas.consentimento WHERE encaminhamento_id = ?", CASO_1)).isEqualTo(1);

        // Revogar tira a visibilidade na hora.
        assertThat(delete(PAC_1, id).statusCode()).isIn(200, 204);
        assertThat(destinoVe(CASO_1)).isFalse();
        assertThat(saida.getAll()).doesNotContain(PAC_1).doesNotContain("texto forjado");
    }

    @Test
    void recusasClarasSemGravarNada() throws Exception {
        String versaoCaso = versao("COMPARTILHAR_CASO");
        String versaoAg = versao("AGENDAMENTO");
        long antes = conta("SELECT count(*)::text FROM saas.consentimento WHERE paciente_id = ?", PACIENTE_2);

        // Finalidade inválida ou ausente.
        for (String f : new String[] {"\"MARKETING\"", "\"compartilhar_caso\"", "\"\"", "null", "1"}) {
            HttpResponse<String> r = post(PAC_2, "{\"finalidade\":" + f + ",\"encaminhamentoId\":\"" + CASO_2
                    + "\",\"versao\":\"" + versaoAg + "\"}");
            assertThat(r.statusCode()).as(f).isEqualTo(400);
            assertThat(r.body()).as(f).contains("FINALIDADE_INVALIDA");
        }
        // Versão ausente, de outra finalidade ou inventada.
        assertThat(post(PAC_2, "{\"finalidade\":\"AGENDAMENTO\",\"encaminhamentoId\":\"" + CASO_2 + "\"}").statusCode())
                .isEqualTo(400);
        assertThat(post(PAC_2, corpo("AGENDAMENTO", CASO_2, null, versaoCaso)).statusCode()).isEqualTo(409);
        assertThat(post(PAC_2, corpo("AGENDAMENTO", CASO_2, null, "1.000000000000")).statusCode()).isEqualTo(409);
        // Caso de outro paciente, outro caso do mesmo paciente, caso inexistente.
        assertThat(post(PAC_2, corpo("COMPARTILHAR_CASO", CASO_1, CLINICA_A, versaoCaso)).statusCode()).isEqualTo(404);
        assertThat(post(PAC_1B, corpo("COMPARTILHAR_CASO", CASO_1, CLINICA_A, versaoCaso)).statusCode()).isEqualTo(404);
        assertThat(post(PAC_2, corpo("AGENDAMENTO", UUID.randomUUID(), null, versaoAg)).statusCode()).isEqualTo(404);
        // Clínica que não é a destino; caso sem destino escolhido.
        assertThat(post(PAC_2, corpo("COMPARTILHAR_CASO", CASO_2, CLINICA_B, versaoCaso)).statusCode()).isEqualTo(422);
        assertThat(post(PAC_2S, corpo("COMPARTILHAR_CASO", CASO_2S, CLINICA_A, versaoCaso)).statusCode()).isEqualTo(422);
        // Ator que não é paciente; sem sessão; corpo malformado.
        assertThat(post(ENC, corpo("AGENDAMENTO", CASO_2, null, versaoAg)).statusCode()).isEqualTo(403);
        assertThat(post(ADMIN_A, corpo("AGENDAMENTO", CASO_2, null, versaoAg)).statusCode()).isEqualTo(403);
        assertThat(post(null, corpo("AGENDAMENTO", CASO_2, null, versaoAg)).statusCode()).isEqualTo(401);
        assertThat(post(aleatorio(32), corpo("AGENDAMENTO", CASO_2, null, versaoAg)).statusCode()).isEqualTo(401);
        assertThat(post(PAC_2, "[]").statusCode()).isEqualTo(400);
        assertThat(post(PAC_2, "{\"finalidade\":\"AGENDAMENTO\",\"versao\":\"" + versaoAg
                + "\",\"encaminhamentoId\":\"nao-uuid\"}").statusCode()).isEqualTo(400);
        assertThat(conta("SELECT count(*)::text FROM saas.consentimento WHERE paciente_id = ?", PACIENTE_2))
                .isEqualTo(antes);

        // Controle positivo: a mesma sessão concede no próprio caso (sem caso no corpo: o da sessão).
        HttpResponse<String> ok = post(PAC_2, "{\"finalidade\":\"AGENDAMENTO\",\"versao\":\"" + versaoAg + "\"}");
        assertThat(ok.statusCode()).isEqualTo(201);
        assertThat(linha("SELECT encaminhamento_id::text, paciente_id::text FROM saas.consentimento WHERE id = ?",
                UUID.fromString(json.readTree(ok.body()).get("id").asText())))
                .containsEntry("1", CASO_2.toString()).containsEntry("2", PACIENTE_2.toString());
    }

    // ------------------------------------------------------------- F9.4 / F9.5

    @Test
    void listagemDoCasoERevogacaoIdempotenteSemTocarConsentimentoAlheio() throws Exception {
        String versaoWa = versao("COMUNICACAO_WHATSAPP");
        UUID meu = id(post(PAC_1B, corpo("COMUNICACAO_WHATSAPP", CASO_1B, null, versaoWa)));
        UUID outroCaso = id(post(PAC_1, corpo("COMUNICACAO_WHATSAPP", CASO_1, null, versaoWa)));
        UUID alheio = id(post(PAC_2, corpo("COMUNICACAO_WHATSAPP", CASO_2, null, versaoWa)));

        HttpResponse<String> lista = get("/api/consentimentos", PAC_1B);
        assertThat(lista.statusCode()).isEqualTo(200);
        JsonNode l = json.readTree(lista.body());
        assertThat(l.isArray()).isTrue();
        assertThat(l).extracting(n -> n.get("id").asText()).containsExactly(meu.toString());
        assertThat(l.get(0).get("finalidade").asText()).isEqualTo("COMUNICACAO_WHATSAPP");
        assertThat(l.get(0).get("versao").asText()).isEqualTo(versaoWa);
        assertThat(l.get(0).get("ativo").asBoolean()).isTrue();
        assertThat(get("/api/consentimentos", null).statusCode()).isEqualTo(401);
        assertThat(get("/api/consentimentos", ENC).statusCode()).isEqualTo(403);

        // Alheio (outro paciente) e outro caso do mesmo paciente: 404 e nada muda.
        assertThat(delete(PAC_1B, alheio).statusCode()).isEqualTo(404);
        assertThat(delete(PAC_1B, outroCaso).statusCode()).isEqualTo(404);
        assertThat(delete(PAC_1B, UUID.randomUUID()).statusCode()).isEqualTo(404);
        assertThat(delete(ENC, meu).statusCode()).isEqualTo(403);
        assertThat(delete(null, meu).statusCode()).isEqualTo(401);
        assertThat(revogadoEm(alheio)).isNull();
        assertThat(revogadoEm(outroCaso)).isNull();
        assertThat(revogadoEm(meu)).isNull();

        assertThat(delete(PAC_1B, meu).statusCode()).isIn(200, 204);
        String primeira = revogadoEm(meu);
        assertThat(primeira).isNotNull();
        Thread.sleep(Duration.ofMillis(20));
        assertThat(delete(PAC_1B, meu).statusCode()).isIn(404, 409, 410);
        assertThat(revogadoEm(meu)).isEqualTo(primeira);
        assertThat(conta("SELECT count(*)::text FROM saas.evento_auditoria WHERE recurso_id = ? "
                + "AND acao = 'REVOGAR_CONSENTIMENTO'", meu)).isEqualTo(1);
        assertThat(revogadoEm(alheio)).isNull();
        assertThat(revogadoEm(outroCaso)).isNull();

        JsonNode depois = json.readTree(get("/api/consentimentos", PAC_1B).body());
        assertThat(depois.get(0).get("ativo").asBoolean()).isFalse();
        assertThat(depois.get(0).get("revogadoEm").isTextual()).isTrue();
    }

    // ------------------------------------------------------------- apoio

    /** A equipe ADMIN da clínica A vê o caso pelo papel saas_app, com contexto local à transação. */
    private static boolean destinoVe(UUID caso) throws SQLException {
        try (Connection c = DriverManager.getConnection(PG.getJdbcUrl(), "saas_app", SENHA)) {
            c.setAutoCommit(false);
            try (PreparedStatement p = c.prepareStatement("SELECT set_config('app.sessao', ?, true), "
                    + "set_config('app.clinica_id', ?, true), set_config('app.papel', ?, true)")) {
                p.setString(1, ADMIN_A);
                p.setString(2, CLINICA_A.toString());
                p.setString(3, "ADMIN");
                p.execute();
            }
            try (PreparedStatement p = c.prepareStatement("SELECT count(*) FROM saas.encaminhamento WHERE id = ?")) {
                p.setObject(1, caso);
                try (ResultSet rs = p.executeQuery()) {
                    rs.next();
                    return rs.getLong(1) == 1;
                }
            } finally {
                c.rollback();
            }
        }
    }

    private String versao(String finalidade) throws Exception {
        return json.readTree(get("/api/termos/consentimento/" + finalidade, null).body()).get("versao").asText();
    }

    private UUID id(HttpResponse<String> r) throws Exception {
        assertThat(r.statusCode()).as(r.body()).isIn(200, 201);
        return UUID.fromString(json.readTree(r.body()).get("id").asText());
    }

    private static String corpo(String finalidade, UUID caso, UUID clinica, String versao) {
        return "{\"finalidade\":\"" + finalidade + "\",\"encaminhamentoId\":\"" + caso + "\","
                + (clinica == null ? "" : "\"clinicaId\":\"" + clinica + "\",") + "\"versao\":\"" + versao + "\"}";
    }

    private static String revogadoEm(UUID id) throws SQLException {
        return linha("SELECT revogado_em::text FROM saas.consentimento WHERE id = ?", id).get("1");
    }

    private HttpResponse<String> get(String rota, String token) throws Exception {
        HttpRequest.Builder b = HttpRequest.newBuilder(URI.create(base() + rota)).GET();
        if (token != null) {
            b.header("Cookie", "SESSAO=" + token);
        }
        return http.send(b.build(), HttpResponse.BodyHandlers.ofString());
    }

    private HttpResponse<String> post(String token, String corpo) throws Exception {
        HttpRequest.Builder b = HttpRequest.newBuilder(URI.create(base() + "/api/consentimentos"))
                .header("Content-Type", "application/json").POST(HttpRequest.BodyPublishers.ofString(corpo));
        if (token != null) {
            b.header("Cookie", "SESSAO=" + token);
        }
        return http.send(b.build(), HttpResponse.BodyHandlers.ofString());
    }

    private HttpResponse<String> delete(String token, UUID id) throws Exception {
        HttpRequest.Builder b = HttpRequest.newBuilder(URI.create(base() + "/api/consentimentos/" + id)).DELETE();
        if (token != null) {
            b.header("Cookie", "SESSAO=" + token);
        }
        return http.send(b.build(), HttpResponse.BodyHandlers.ofString());
    }

    private String base() {
        return "http://127.0.0.1:" + porta;
    }

    private static long conta(String sql, Object param) throws SQLException {
        return Long.parseLong(linha(sql, param).get("1"));
    }

    private static Map<String, String> linha(String sql, Object param) throws SQLException {
        try (Connection c = superusuario(); PreparedStatement p = c.prepareStatement(sql)) {
            p.setObject(1, param);
            try (ResultSet rs = p.executeQuery()) {
                Map<String, String> r = new TreeMap<>();
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

    private static String hashToken(String tokenHex) {
        try {
            return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(HexFormat.of().parseHex(tokenHex)));
        } catch (java.security.NoSuchAlgorithmException e) {
            throw new IllegalStateException(e);
        }
    }

    private static String aleatorio(int bytes) {
        byte[] b = new byte[bytes];
        new SecureRandom().nextBytes(b);
        return HexFormat.of().formatHex(b);
    }
}
