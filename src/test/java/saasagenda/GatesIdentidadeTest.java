package saasagenda;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.SecureRandom;
import java.sql.Connection;
import java.sql.Date;
import java.sql.DriverManager;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;
import java.util.HexFormat;
import java.util.UUID;
import org.flywaydb.core.Flyway;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.Test;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;
import org.testcontainers.utility.DockerImageName;

/**
 * F3: gates de identidade do Red Team (T-20, I-22, I-23) contra o banco migrado pelo Flyway,
 * com os papeis reais (saas_auth abre a sessao de equipe, saas_app age, saas_jobs prepara o
 * envio) e o fluxo real de link e codigo do paciente. Dados ficticios.
 */
@Testcontainers
class GatesIdentidadeTest {

    private static final DockerImageName IMAGEM = DockerImageName
            .parse("mirror.gcr.io/library/postgres:16-alpine")
            .asCompatibleSubstituteFor("postgres");

    @Container
    static final PostgreSQLContainer<?> PG = new PostgreSQLContainer<>(IMAGEM);

    private static final String SENHA = senhaAleatoria();

    private static final String ESPECIALIDADE = "e0000000-0000-0000-0000-000000000001";
    private static final String CLINICA = "c0000000-0000-0000-0000-000000000001";
    private static final String ENCAMINHADOR = "f0000000-0000-0000-0000-000000000001";
    private static final String MEDICO_DESTINO = "f0000000-0000-0000-0000-000000000002";
    private static final String PROF_CLINICA = "d0000000-0000-0000-0000-000000000001";
    private static final String TOKEN_ENCAMINHADOR = "ad".repeat(32);

    private static String tokenRecepcao;

    @BeforeAll
    static void prepara() throws Exception {
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
            s.execute("SET search_path = saas");
            s.execute("INSERT INTO especialidade(id, nome) VALUES ('" + ESPECIALIDADE + "', 'Ortopedia')");
            s.execute("INSERT INTO clinica(id, nome) VALUES ('" + CLINICA + "', 'Clinica Ficticia')");
            s.execute("INSERT INTO clinica_especialidade VALUES ('" + CLINICA + "', '" + ESPECIALIDADE + "')");
            s.execute("INSERT INTO flag_clinica(clinica_id, chave, ligada) VALUES ('" + CLINICA + "', 'REDE_ENCAMINHAMENTO', true)");
            s.execute("INSERT INTO usuario(id, sub_oidc, nome, email) VALUES "
                    + "('a0000000-0000-0000-0000-000000000001', 'rec-ficticia', 'Recepcao Ficticia', 'rec@exemplo.invalid')");
            s.execute("INSERT INTO usuario_clinica(usuario_id, clinica_id, papel) VALUES "
                    + "('a0000000-0000-0000-0000-000000000001', '" + CLINICA + "', 'RECEPCAO')");
            s.execute("INSERT INTO profissional(id, crm, crm_uf, nome, telefone, canal_verificado_em) VALUES "
                    + "('" + ENCAMINHADOR + "', '900001', 'PE', 'Dra Ficticia', '+5581999990001', now()), "
                    + "('" + MEDICO_DESTINO + "', '900002', 'PE', 'Dr Ficticio', '+5581999990002', now())");
            s.execute("INSERT INTO profissional_clinica(id, profissional_id, clinica_id, recebe_encaminhamento) VALUES "
                    + "('" + PROF_CLINICA + "', '" + MEDICO_DESTINO + "', '" + CLINICA + "', true)");
            s.execute("INSERT INTO sessao(token_hash, tipo, profissional_id, expira_em) VALUES "
                    + "(sha256(decode('" + TOKEN_ENCAMINHADOR + "', 'hex')), 'ENCAMINHADOR', '" + ENCAMINHADOR
                    + "', now() + interval '1 hour')");
        }
        try (Connection c = conecta("saas_auth")) {
            tokenRecepcao = texto(c, "SELECT saas.sessao_equipe_abre('rec-ficticia')");
        }
    }

    // ---------------------------------------------------------------- T-20

    @Test
    void cpfSoIdentificaComNomeENascimentoIguais() throws Exception {
        byte[] cpf = {1, 2, 3, 4};
        String mae = criaEncaminhamento("Mae Ficticia", "+5581900000101", "1980-01-01", cpf);
        String filho = criaEncaminhamento("Filho Ficticio", "+5581900000101", "2015-05-05", cpf);
        String umDia = criaEncaminhamento("Mae Ficticia", "+5581900000101", "1980-01-02", cpf);
        String mesmaComTelefoneNovo = criaEncaminhamento("  MAE   ficticia ", "+5581900000102", "1980-01-01", cpf);
        String mesmaSemNascimento = criaEncaminhamento("Mae Ficticia", "+5581900000103", null, cpf);

        assertThat(pacienteDe(filho)).isNotEqualTo(pacienteDe(mae));
        assertThat(pacienteDe(umDia)).isNotEqualTo(pacienteDe(mae));
        assertThat(nomeDoPaciente(pacienteDe(filho))).isEqualTo("Filho Ficticio");
        // Controles: CPF com nome normalizado e nascimento iguais (ou ausente num dos lados).
        assertThat(pacienteDe(mesmaComTelefoneNovo)).isEqualTo(pacienteDe(mae));
        assertThat(pacienteDe(mesmaSemNascimento)).isEqualTo(pacienteDe(mae));
        // Regra da Fase 1 mantida: sem CPF, nome normalizado + nascimento + telefone.
        String semCpf1 = criaEncaminhamento("Idosa Ficticia", "+5581900000104", "1940-02-02", null);
        String semCpf2 = criaEncaminhamento("idosa  FICTICIA", "+5581900000104", "1940-02-02", null);
        String netoSemCpf = criaEncaminhamento("Neto Ficticio", "+5581900000104", "2016-02-02", null);
        assertThat(pacienteDe(semCpf2)).isEqualTo(pacienteDe(semCpf1));
        assertThat(pacienteDe(netoSemCpf)).isNotEqualTo(pacienteDe(semCpf1));
    }

    @Test
    void recepcaoNuncaRecebeIdDePacienteExistente() throws Exception {
        try (Connection c = recepcao()) {
            String a = cadastraNaClinica(c, "Paciente Recepcao", "+5581900000201", "1970-03-03", new byte[] {9});
            String b = cadastraNaClinica(c, "Paciente Recepcao", "+5581900000201", "1970-03-03", new byte[] {9});
            String d = cadastraNaClinica(c, "paciente  RECEPCAO", "+5581900000201", "1970-03-03", null);
            assertThat(b).isNotEqualTo(a);
            assertThat(d).isNotEqualTo(a).isNotEqualTo(b);
        }
    }

    // ---------------------------------------------------------------- I-22

    @Test
    void linkECodigoVaoAoTelefoneInformadoNoCaso() throws Exception {
        byte[] cpf = {7, 7, 7};
        String antigo = criaEncaminhamento("Pessoa Telefone", "+5581900000301", "1990-04-04", cpf);
        String novo = criaEncaminhamento("Pessoa Telefone", "+5581900000302", "1990-04-04", cpf);
        assertThat(pacienteDe(novo)).isEqualTo(pacienteDe(antigo));

        try (Connection jobs = conecta("saas_jobs")) {
            String envio = texto(jobs, "SELECT saas.jobs_envio_link_paciente(?::uuid)", novo);
            String[] preparo = prepara(jobs, envio);
            assertThat(preparo[0]).isEqualTo("+5581900000302");

            try (Connection web = conecta("saas_app")) {
                assertThat(texto(web, "SELECT saas.paciente_pede_codigo(?)::text", preparo[1])).isEqualTo("true");
            }
            String envioCodigo = envioPendente(novo, "CODIGO_PACIENTE");
            assertThat(prepara(jobs, envioCodigo)[0]).isEqualTo("+5581900000302");
        }
        // O cadastro global nao mudou: o caso antigo continua com o telefone dele.
        try (Connection jobs = conecta("saas_jobs")) {
            String envio = texto(jobs, "SELECT saas.jobs_envio_link_paciente(?::uuid)", antigo);
            assertThat(prepara(jobs, envio)[0]).isEqualTo("+5581900000301");
        }
    }

    @Test
    void casoSemTelefoneDeContatoUsaOCadastro() throws Exception {
        String pac;
        String enc = UUID.randomUUID().toString();
        try (Connection c = superusuario(); Statement s = c.createStatement()) {
            pac = texto(c, "INSERT INTO saas.paciente(nome, telefone) VALUES ('Linha Antiga', '+5581900000401') RETURNING id::text");
            s.execute("INSERT INTO saas.encaminhamento(id, profissional_origem_id, paciente_id, especialidade_destino_id, "
                    + "motivo_cifrado, urgencia, expira_em) VALUES ('" + enc + "', '" + ENCAMINHADOR + "', '" + pac
                    + "', '" + ESPECIALIDADE + "', '\\x00', 'ROTINA', now() + interval '1 day')");
        }
        try (Connection jobs = conecta("saas_jobs")) {
            String envio = texto(jobs, "SELECT saas.jobs_envio_link_paciente(?::uuid)", enc);
            assertThat(prepara(jobs, envio)[0]).isEqualTo("+5581900000401");
        }
    }

    @Test
    void papelWebNaoTrocaOTelefoneDeContato() throws Exception {
        String enc = criaEncaminhamento("Pessoa Imutavel", "+5581900000501", "1991-05-05", null);
        try (Connection c = conecta("saas_app")) {
            define(c, "app.sessao", TOKEN_ENCAMINHADOR);
            try (PreparedStatement p = c.prepareStatement(
                    "UPDATE saas.encaminhamento SET telefone_contato = '+5581900000999' WHERE id = ?::uuid")) {
                p.setString(1, enc);
                assertThatThrownBy(p::executeUpdate).isInstanceOf(SQLException.class);
            }
        }
    }

    // ---------------------------------------------------------------- I-23

    @Test
    void depoisDaRevogacaoRecepcaoNaoUsaOVinculoDoEncaminhamento() throws Exception {
        String enc = criaEncaminhamento("Pessoa Revoga", "+5581900000601", "1985-06-06", null);
        String pac = pacienteDe(enc);
        String sessaoPaciente = abreSessaoPaciente(enc);
        try (Connection web = conecta("saas_app")) {
            define(web, "app.sessao", sessaoPaciente);
            executa(web, "SELECT saas.paciente_solicita(?::uuid, ?::uuid, ?::uuid, 'texto ficticio', 'v1')",
                    enc, CLINICA, MEDICO_DESTINO);
        }
        try (Connection c = recepcao()) {
            executa(c, "SELECT saas.destino_confirma_horario(?::uuid, ?::uuid, now() + interval '2 days', "
                    + "now() + interval '2 days 30 minutes', 'chave-t4')", enc, PROF_CLINICA);
            // Controle: com o consentimento ativo, a recepcao registra consentimento e marca consulta.
            assertThat(insereConsentimento(c, pac)).isEqualTo(1);
            assertThat(insereAgendamento(c, pac, 5, "antes-revogacao")).isEqualTo(1);
        }
        try (Connection web = conecta("saas_app")) {
            define(web, "app.sessao", sessaoPaciente);
            try (PreparedStatement p = web.prepareStatement("UPDATE saas.consentimento SET revogado_em = now() "
                    + "WHERE encaminhamento_id = ?::uuid AND finalidade = 'COMPARTILHAR_CASO'")) {
                p.setString(1, enc);
                assertThat(p.executeUpdate()).isEqualTo(1);
            }
        }
        try (Connection c = recepcao()) {
            assertThat(cadastraNaClinica(c, "Pessoa Revoga", "+5581900000601", "1985-06-06", null)).isNotEqualTo(pac);
            assertThatThrownBy(() -> insereAgendamento(c, pac, 6, "depois-revogacao")).isInstanceOf(SQLException.class);
            assertThatThrownBy(() -> insereConsentimento(c, pac)).isInstanceOf(SQLException.class);
            // Controle: paciente com vinculo de cadastro continua atendido.
            String proprio = cadastraNaClinica(c, "Pessoa Cadastro", "+5581900000602", "1986-06-06", null);
            assertThat(insereConsentimento(c, proprio)).isEqualTo(1);
            assertThat(insereAgendamento(c, proprio, 7, "cadastro")).isEqualTo(1);
        }
    }

    // ---------------------------------------------------------------- apoio

    private static String criaEncaminhamento(String nome, String telefone, String nascimento, byte[] cpf) throws SQLException {
        try (Connection c = conecta("saas_app")) {
            define(c, "app.sessao", TOKEN_ENCAMINHADOR);
            try (PreparedStatement p = c.prepareStatement(
                    "SELECT saas.encaminhamento_cria(?, ?, ?, ?, ?, ?::uuid, '\\x0a'::bytea, 'ROTINA')::text")) {
                p.setString(1, nome);
                p.setString(2, telefone);
                p.setDate(3, nascimento == null ? null : Date.valueOf(nascimento));
                p.setBytes(4, cpf == null ? null : new byte[] {0x55});
                p.setBytes(5, cpf);
                p.setString(6, ESPECIALIDADE);
                try (ResultSet r = p.executeQuery()) {
                    r.next();
                    return r.getString(1);
                }
            }
        }
    }

    private static String cadastraNaClinica(Connection c, String nome, String telefone, String nascimento, byte[] cpf)
            throws SQLException {
        try (PreparedStatement p = c.prepareStatement("SELECT saas.paciente_cadastra_na_clinica(?, ?, ?, ?, ?)::text")) {
            p.setString(1, nome);
            p.setString(2, telefone);
            p.setDate(3, Date.valueOf(nascimento));
            p.setBytes(4, cpf == null ? null : new byte[] {0x55});
            p.setBytes(5, cpf);
            try (ResultSet r = p.executeQuery()) {
                r.next();
                return r.getString(1);
            }
        }
    }

    private static int insereAgendamento(Connection c, String paciente, int dias, String chave) throws SQLException {
        try (PreparedStatement p = c.prepareStatement("INSERT INTO saas.agendamento(clinica_id, profissional_clinica_id, "
                + "paciente_id, inicio, fim, origem, chave_idempotencia) VALUES (?::uuid, ?::uuid, ?::uuid, "
                + "now() + make_interval(days => ?), now() + make_interval(days => ?, mins => 30), 'RECEPCAO', ?)")) {
            p.setString(1, CLINICA);
            p.setString(2, PROF_CLINICA);
            p.setString(3, paciente);
            p.setInt(4, dias);
            p.setInt(5, dias);
            p.setString(6, chave);
            return p.executeUpdate();
        }
    }

    private static int insereConsentimento(Connection c, String paciente) throws SQLException {
        try (PreparedStatement p = c.prepareStatement("INSERT INTO saas.consentimento(paciente_id, finalidade, clinica_id, "
                + "texto_aceito, versao_texto, canal) VALUES (?::uuid, 'COMUNICACAO_WHATSAPP', ?::uuid, 'texto', 'v1', 'RECEPCAO')")) {
            p.setString(1, paciente);
            p.setString(2, CLINICA);
            return p.executeUpdate();
        }
    }

    /** Fluxo real: link preparado pelo saas_jobs, T2, pedido de codigo, codigo e confirmacao. */
    private static String abreSessaoPaciente(String enc) throws SQLException {
        try (Connection jobs = conecta("saas_jobs"); Connection web = conecta("saas_app")) {
            String envio = texto(jobs, "SELECT saas.jobs_envio_link_paciente(?::uuid)", enc);
            String link = prepara(jobs, envio)[1];
            executa(jobs, "SELECT saas.jobs_envio_resultado(?::uuid, 'ACEITO', 'prov-ficticio')", envio);
            assertThat(texto(web, "SELECT saas.paciente_pede_codigo(?)::text", link)).isEqualTo("true");
            String codigo = prepara(jobs, envioPendente(enc, "CODIGO_PACIENTE"))[1];
            String sessao = texto(web, "SELECT saas.paciente_confirma_codigo(?, ?)", link, codigo);
            assertThat(sessao).isNotNull();
            return sessao;
        }
    }

    private static String[] prepara(Connection jobs, String envio) throws SQLException {
        try (PreparedStatement p = jobs.prepareStatement("SELECT contato, segredo FROM saas.jobs_envio_prepara(?::uuid)")) {
            p.setString(1, envio);
            try (ResultSet r = p.executeQuery()) {
                assertThat(r.next()).isTrue();
                return new String[] {r.getString(1), r.getString(2)};
            }
        }
    }

    private static String envioPendente(String enc, String finalidade) throws SQLException {
        try (Connection c = superusuario()) {
            return texto(c, "SELECT id::text FROM saas.envio_notificacao WHERE encaminhamento_id = ?::uuid "
                    + "AND finalidade = ? AND status = 'PENDENTE' ORDER BY criado_em DESC LIMIT 1", enc, finalidade);
        }
    }

    private static String pacienteDe(String enc) throws SQLException {
        try (Connection c = superusuario()) {
            return texto(c, "SELECT paciente_id::text FROM saas.encaminhamento WHERE id = ?::uuid", enc);
        }
    }

    private static String nomeDoPaciente(String pac) throws SQLException {
        try (Connection c = superusuario()) {
            return texto(c, "SELECT nome FROM saas.paciente WHERE id = ?::uuid", pac);
        }
    }

    private static Connection recepcao() throws SQLException {
        Connection c = conecta("saas_app");
        define(c, "app.sessao", tokenRecepcao);
        define(c, "app.clinica_id", CLINICA);
        define(c, "app.papel", "RECEPCAO");
        return c;
    }

    private static void define(Connection c, String chave, String valor) throws SQLException {
        executa(c, "SELECT set_config(?, ?, false)", chave, valor);
    }

    private static void executa(Connection c, String sql, String... args) throws SQLException {
        try (PreparedStatement p = c.prepareStatement(sql)) {
            for (int i = 0; i < args.length; i++) {
                p.setString(i + 1, args[i]);
            }
            p.execute();
        }
    }

    private static String texto(Connection c, String sql, String... args) throws SQLException {
        try (PreparedStatement p = c.prepareStatement(sql)) {
            for (int i = 0; i < args.length; i++) {
                p.setString(i + 1, args[i]);
            }
            try (ResultSet r = p.executeQuery()) {
                r.next();
                return r.getString(1);
            }
        }
    }

    private static Connection superusuario() throws SQLException {
        return DriverManager.getConnection(PG.getJdbcUrl(), PG.getUsername(), PG.getPassword());
    }

    private static Connection conecta(String papel) throws SQLException {
        return DriverManager.getConnection(PG.getJdbcUrl(), papel, SENHA);
    }

    private static String senhaAleatoria() {
        byte[] b = new byte[24];
        new SecureRandom().nextBytes(b);
        return HexFormat.of().formatHex(b);
    }
}
