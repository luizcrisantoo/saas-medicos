package saasagenda;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.SecureRandom;
import java.sql.Connection;
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
 * F4: gates de banco do Red Team (R-08, I-21, O3, envios pendentes apos cancelamento, E-09)
 * contra o banco migrado pelo Flyway, com os papeis reais e o log do servidor do container.
 * Todo criterio negativo tem controle positivo. Dados ficticios.
 */
@Testcontainers
class GatesBancoTest {

    private static final DockerImageName IMAGEM = DockerImageName
            .parse("mirror.gcr.io/library/postgres:16-alpine")
            .asCompatibleSubstituteFor("postgres");

    @Container
    static final PostgreSQLContainer<?> PG = new PostgreSQLContainer<>(IMAGEM);

    private static final String SENHA = senhaAleatoria();

    private static final String ESPECIALIDADE = "e0000000-0000-0000-0000-000000000001";
    private static final String CLINICA = "c0000000-0000-0000-0000-000000000001";
    private static final String CLINICA_SEM_REDE = "c0000000-0000-0000-0000-000000000002";
    private static final String ENCAMINHADOR = "f0000000-0000-0000-0000-000000000001";
    private static final String MEDICO_COM_CONTA = "f0000000-0000-0000-0000-000000000002";
    private static final String NAO_VERIFICADO = "f0000000-0000-0000-0000-000000000003";
    private static final String MEDICO_VOLUME = "f0000000-0000-0000-0000-000000000004";
    private static final String MEDICO_POUCO = "f0000000-0000-0000-0000-000000000005";
    private static final String PROF_CLINICA = "d0000000-0000-0000-0000-000000000001";
    private static final String TOKEN_ENCAMINHADOR = "ad".repeat(32);
    private static final String TELEFONE_VOLUME = "+5581999990004";

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
            s.execute("INSERT INTO clinica(id, nome) VALUES ('" + CLINICA + "', 'Clinica Ficticia'), "
                    + "('" + CLINICA_SEM_REDE + "', 'Clinica Ficticia Dois')");
            s.execute("INSERT INTO clinica_especialidade VALUES ('" + CLINICA + "', '" + ESPECIALIDADE + "')");
            s.execute("INSERT INTO flag_clinica(clinica_id, chave, ligada) VALUES ('" + CLINICA + "', 'REDE_ENCAMINHAMENTO', true)");
            s.execute("INSERT INTO usuario(id, sub_oidc, nome, email) VALUES "
                    + "('a0000000-0000-0000-0000-000000000001', 'rec-ficticia', 'Recepcao Ficticia', 'rec@exemplo.invalid'), "
                    + "('a0000000-0000-0000-0000-000000000002', 'med-ficticio', 'Medico Ficticio', 'med@exemplo.invalid')");
            s.execute("INSERT INTO usuario_clinica(usuario_id, clinica_id, papel) VALUES "
                    + "('a0000000-0000-0000-0000-000000000001', '" + CLINICA + "', 'RECEPCAO')");
            s.execute("INSERT INTO profissional(id, crm, crm_uf, nome, telefone, canal_verificado_em, usuario_id) VALUES "
                    + "('" + ENCAMINHADOR + "', '900001', 'PE', 'Dra Ficticia', '+5581999990001', now(), NULL), "
                    + "('" + MEDICO_COM_CONTA + "', '900002', 'PE', 'Dr Com Conta', '+5581999990002', NULL, "
                    + "'a0000000-0000-0000-0000-000000000002'), "
                    + "('" + NAO_VERIFICADO + "', '900003', 'PE', 'Cadastro Nao Verificado', '+5581999990003', NULL, NULL), "
                    + "('" + MEDICO_VOLUME + "', '900004', 'PE', 'Dr Volume', '" + TELEFONE_VOLUME + "', now(), NULL), "
                    + "('" + MEDICO_POUCO + "', '900005', 'PE', 'Dr Pouco', '+5581999990005', now(), NULL)");
            s.execute("INSERT INTO profissional_especialidade VALUES ('" + ENCAMINHADOR + "', '" + ESPECIALIDADE + "'), "
                    + "('" + MEDICO_COM_CONTA + "', '" + ESPECIALIDADE + "'), ('" + NAO_VERIFICADO + "', '" + ESPECIALIDADE + "')");
            s.execute("INSERT INTO profissional_clinica(id, profissional_id, clinica_id, recebe_encaminhamento) VALUES "
                    + "('" + PROF_CLINICA + "', '" + MEDICO_COM_CONTA + "', '" + CLINICA + "', true)");
            s.execute("INSERT INTO sessao(token_hash, tipo, profissional_id, expira_em) VALUES "
                    + "(sha256(decode('" + TOKEN_ENCAMINHADOR + "', 'hex')), 'ENCAMINHADOR', '" + ENCAMINHADOR
                    + "', now() + interval '1 hour')");
        }
        try (Connection c = conecta("saas_auth")) {
            tokenRecepcao = texto(c, "SELECT saas.sessao_equipe_abre('rec-ficticia')");
        }
    }

    // ---------------------------------------------------------------- R-08

    @Test
    void ddlDoDonoEmTabelaDeSaasGeraAlertaMesmoComRollback() throws Exception {
        String sufixo = UUID.randomUUID().toString().substring(0, 8);
        String politica = "r08_pol_" + sufixo;
        String gatilho = "r08_tg_" + sufixo;
        String regra = "r08_rule_" + sufixo;
        String[][] casos = {
            {"CREATE POLICY " + politica + " ON saas.encaminhamento FOR SELECT USING (true)", "CREATE POLICY " + politica},
            {"ALTER POLICY " + politica + " ON saas.encaminhamento USING (true)", "ALTER POLICY " + politica},
            {"ALTER POLICY " + politica + " ON saas.encaminhamento RENAME TO " + politica + "_b", "ALTER POLICY " + politica + "_b"},
            {"CREATE TRIGGER " + gatilho + " BEFORE UPDATE ON saas.paciente FOR EACH ROW EXECUTE FUNCTION saas.bloqueia_alteracao()",
                "CREATE TRIGGER " + gatilho},
            {"CREATE RULE " + regra + " AS ON INSERT TO saas.especialidade DO INSTEAD NOTHING", "CREATE RULE " + regra},
            {"ALTER TABLE saas.paciente DISABLE TRIGGER " + gatilho, "ALTER TABLE saas.paciente"},
            {"ALTER TABLE saas.historico_status_encaminhamento NO FORCE ROW LEVEL SECURITY",
                "ALTER TABLE saas.historico_status_encaminhamento"},
            {"DROP POLICY " + politica + "_b ON saas.encaminhamento", "DROP policy " + politica + "_b"},
            {"DROP TRIGGER " + gatilho + " ON saas.paciente", "DROP trigger " + gatilho},
        };
        int[] antes = new int[casos.length];
        for (int i = 0; i < casos.length; i++) {
            antes[i] = contaNoLog("ALERTA_DDL_SAAS: " + casos[i][1] + " ");
        }
        try (Connection c = conecta("saas_migracao"); Statement s = c.createStatement()) {
            c.setAutoCommit(false);
            s.execute("SET ROLE saas_owner");
            for (String[] caso : casos) {
                s.execute(caso[0]);
            }
            c.rollback();
        }
        Thread.sleep(1000);
        for (int i = 0; i < casos.length; i++) {
            assertThat(contaNoLog("ALERTA_DDL_SAAS: " + casos[i][1] + " ")).as(casos[i][0]).isGreaterThan(antes[i]);
        }
        // Nada persistiu e o DDL fora de saas nao gera alerta (controle).
        try (Connection c = superusuario(); Statement s = c.createStatement()) {
            assertThat(texto(c, "SELECT count(*)::text FROM pg_policy WHERE polname LIKE 'r08_pol_%'")).isEqualTo("0");
            s.execute("CREATE TABLE public.fora_" + sufixo + " (id int)");
            s.execute("CREATE POLICY fora_pol_" + sufixo + " ON public.fora_" + sufixo + " USING (true)");
            s.execute("DROP TABLE public.fora_" + sufixo);
        }
        assertThat(esperaNoLog("fora_pol_" + sufixo)).isFalse();
    }

    // ---------------------------------------------------------------- I-21

    @Test
    void funcoesDefinerNaoRespondemSemSessao() throws Exception {
        try (Connection web = conecta("saas_app")) {
            assertThat(texto(web, "SELECT saas.rede_ligada(?::uuid)::text", CLINICA)).isEqualTo("false");
            assertThat(texto(web, "SELECT saas.consentimento_ativo(gen_random_uuid(), ?::uuid)::text", CLINICA)).isEqualTo("false");
            assertThat(texto(web, "SELECT count(*)::text FROM saas.catalogo_rede(?::uuid)", ESPECIALIDADE)).isEqualTo("0");
        }
        // Mesmo chamada pelo dono das funcoes sem sessao: falso.
        try (Connection c = conecta("saas_migracao"); Statement s = c.createStatement()) {
            s.execute("SET ROLE saas_funcoes");
            assertThat(texto(c, "SELECT saas.rede_ligada(?::uuid)::text", CLINICA)).isEqualTo("false");
        }
        // Controle: com sessao, rede_ligada responde e o catalogo mostra a clinica com a rede ligada.
        try (Connection web = encaminhador()) {
            assertThat(texto(web, "SELECT saas.rede_ligada(?::uuid)::text", CLINICA)).isEqualTo("true");
            assertThat(texto(web, "SELECT saas.rede_ligada(?::uuid)::text", CLINICA_SEM_REDE)).isEqualTo("false");
            assertThat(texto(web, "SELECT string_agg(clinica_id::text, ',') FROM saas.catalogo_rede(?::uuid)", ESPECIALIDADE))
                    .isEqualTo(CLINICA);
        }
    }

    // ---------------------------------------------------------------- O3

    @Test
    void profissionalNaoVerificadoForaDaVisaoDePacienteEEncaminhador() throws Exception {
        String enc = criaEncaminhamento("Paciente O3", "+5581900000301");
        String sessaoPaciente = abreSessaoPaciente(enc);
        try (Connection paciente = conecta("saas_app"); Connection enc2 = encaminhador(); Connection rec = recepcao()) {
            define(paciente, "app.sessao", sessaoPaciente);
            for (Connection c : new Connection[] {paciente, enc2}) {
                assertThat(contaProfissional(c, NAO_VERIFICADO)).isZero();
                assertThat(texto(c, "SELECT count(*)::text FROM saas.profissional_especialidade WHERE profissional_id = ?::uuid",
                        NAO_VERIFICADO)).isEqualTo("0");
                // Controles: verificado por canal e com conta continuam visiveis.
                assertThat(contaProfissional(c, ENCAMINHADOR)).isEqualTo(1);
                assertThat(contaProfissional(c, MEDICO_COM_CONTA)).isEqualTo(1);
            }
            // A equipe continua vendo o cadastro (nome e CRM).
            assertThat(contaProfissional(rec, NAO_VERIFICADO)).isEqualTo(1);
        }
        try (Connection semSessao = conecta("saas_app")) {
            assertThat(contaProfissional(semSessao, ENCAMINHADOR)).isZero();
        }
    }

    // ---------------------------------------------------------------- envios apos cancelamento

    @Test
    void cancelarAgendamentoDiretoDerrubaConfirmacaoELembretePendentes() throws Exception {
        String pac;
        String agCancelado;
        String agAtivo;
        try (Connection rec = recepcao()) {
            pac = texto(rec, "SELECT saas.paciente_cadastra_na_clinica('Paciente Agenda', '+5581900000401', NULL, NULL, NULL)::text");
            insereAgendamento(rec, pac, 10, "f44-a");
            insereAgendamento(rec, pac, 11, "f44-b");
        }
        agCancelado = agendamentoPorChave("f44-a");
        agAtivo = agendamentoPorChave("f44-b");
        String conf = insereEnvio("CONFIRMACAO_AGENDAMENTO", pac, null, agCancelado);
        String lemb = insereEnvio("LEMBRETE", pac, null, agCancelado);
        String confAtivo = insereEnvio("CONFIRMACAO_AGENDAMENTO", pac, null, agAtivo);
        try (Connection rec = recepcao()) {
            executa(rec, "UPDATE saas.agendamento SET status = 'CANCELADO' WHERE id = ?::uuid", agCancelado);
        }
        assertThat(statusEnvio(conf)).isEqualTo("FALHOU");
        assertThat(statusEnvio(lemb)).isEqualTo("FALHOU");
        try (Connection jobs = conecta("saas_jobs")) {
            assertThatThrownBy(() -> prepara(jobs, conf)).isInstanceOf(SQLException.class);
            assertThat(texto(jobs, "SELECT count(*)::text FROM saas.jobs_envios_pendentes(100) WHERE envio_id IN (?::uuid, ?::uuid)",
                    conf, lemb)).isEqualTo("0");
            // Controle: o agendamento ativo continua com a confirmacao, ao telefone do proprio cadastro.
            assertThat(prepara(jobs, confAtivo)[0]).isEqualTo("+5581900000401");
        }
    }

    @Test
    void cancelamentoEmCascataPorT11DerrubaEnviosEContatoEhDoCaso() throws Exception {
        String enc = criaEncaminhamento("Paciente Cascata", "+5581900000501");
        String sessaoPaciente = abreSessaoPaciente(enc);
        String ag = agendaPeloDestino(enc, sessaoPaciente, "f44-t11");
        String pac = pacienteDe(enc);
        // Telefone do cadastro diferente do telefone de contato do caso (I-22).
        try (Connection c = superusuario()) {
            executa(c, "UPDATE saas.paciente SET telefone = '+5581900000599' WHERE id = ?::uuid", pac);
        }
        String semEncNoEnvio = insereEnvio("CONFIRMACAO_AGENDAMENTO", pac, null, ag);
        try (Connection jobs = conecta("saas_jobs")) {
            // I-22 mantido: envio pelo agendamento de um caso vai ao telefone de contato do caso.
            assertThat(prepara(jobs, semEncNoEnvio)[0]).isEqualTo("+5581900000501");
        }
        String conf = insereEnvio("CONFIRMACAO_AGENDAMENTO", pac, enc, ag);
        String lemb = insereEnvio("LEMBRETE", pac, null, ag);
        try (Connection rec = recepcao()) {
            executa(rec, "UPDATE saas.encaminhamento SET status = 'CANCELADO' WHERE id = ?::uuid", enc);
        }
        try (Connection c = superusuario()) {
            assertThat(texto(c, "SELECT status FROM saas.agendamento WHERE id = ?::uuid", ag)).isEqualTo("CANCELADO");
        }
        assertThat(statusEnvio(conf)).isEqualTo("FALHOU");
        assertThat(statusEnvio(lemb)).isEqualTo("FALHOU");
        // Envio criado depois do cancelamento: o preparo rele o agendamento e nada sai.
        String tardio = insereEnvio("LEMBRETE", pac, null, ag);
        try (Connection jobs = conecta("saas_jobs")) {
            assertThat(preparaLinhas(jobs, tardio)).isZero();
        }
        assertThat(statusEnvio(tardio)).isEqualTo("FALHOU");
    }

    // ---------------------------------------------------------------- E-09

    @Test
    void vinteePreparosNaHoraGeramAlertaSemContato() throws Exception {
        try (Connection jobs = conecta("saas_jobs")) {
            for (int i = 1; i <= 19; i++) {
                prepara(jobs, insereEnvioProfissional(MEDICO_VOLUME));
                prepara(jobs, insereEnvioProfissional(MEDICO_POUCO));
            }
            assertThat(esperaNoLog("destinatario_id=" + MEDICO_VOLUME)).isFalse();
            prepara(jobs, insereEnvioProfissional(MEDICO_VOLUME));
            assertThat(esperaNoLog("ALERTA_PREPARO_VOLUME: 20 preparos em 1 hora para destinatario_tipo=PROFISSIONAL destinatario_id="
                    + MEDICO_VOLUME)).isTrue();
            prepara(jobs, insereEnvioProfissional(MEDICO_VOLUME));
            assertThat(esperaNoLog("ALERTA_PREPARO_VOLUME: 21 preparos")).isTrue();
        }
        // Controle: 19 preparos para outro destinatario nao alertam; nenhuma linha traz o contato.
        assertThat(esperaNoLog("destinatario_id=" + MEDICO_POUCO)).isFalse();
        assertThat(PG.getLogs().lines().filter(l -> l.contains("ALERTA_PREPARO_VOLUME"))
                .noneMatch(l -> l.contains(TELEFONE_VOLUME) || l.contains("+55"))).isTrue();
    }

    // ---------------------------------------------------------------- auxiliares

    private static String criaEncaminhamento(String nome, String telefone) throws SQLException {
        try (Connection c = encaminhador()) {
            return texto(c, "SELECT saas.encaminhamento_cria(?, ?, NULL, NULL, NULL, ?::uuid, '\\x01'::bytea, 'ROTINA')::text",
                    nome, telefone, ESPECIALIDADE);
        }
    }

    private static String abreSessaoPaciente(String enc) throws SQLException {
        try (Connection jobs = conecta("saas_jobs"); Connection web = conecta("saas_app")) {
            String envio = texto(jobs, "SELECT saas.jobs_envio_link_paciente(?::uuid)::text", enc);
            String link = prepara(jobs, envio)[1];
            executa(jobs, "SELECT saas.jobs_envio_resultado(?::uuid, 'ACEITO', 'prov-ficticio')", envio);
            assertThat(texto(web, "SELECT saas.paciente_pede_codigo(?)::text", link)).isEqualTo("true");
            String envioCodigo;
            try (Connection c = superusuario()) {
                envioCodigo = texto(c, "SELECT id::text FROM saas.envio_notificacao WHERE encaminhamento_id = ?::uuid "
                        + "AND finalidade = 'CODIGO_PACIENTE' AND status = 'PENDENTE' ORDER BY criado_em DESC LIMIT 1", enc);
            }
            String codigo = prepara(jobs, envioCodigo)[1];
            String sessao = texto(web, "SELECT saas.paciente_confirma_codigo(?, ?)", link, codigo);
            assertThat(sessao).isNotNull();
            return sessao;
        }
    }

    /** T3 pelo paciente e T4 pela recepcao do destino; devolve o agendamento. */
    private static String agendaPeloDestino(String enc, String sessaoPaciente, String chave) throws SQLException {
        try (Connection paciente = conecta("saas_app")) {
            define(paciente, "app.sessao", sessaoPaciente);
            executa(paciente, "SELECT saas.paciente_solicita(?::uuid, ?::uuid, NULL, 'Texto ficticio', 'v1')", enc, CLINICA);
        }
        try (Connection rec = recepcao()) {
            return texto(rec, "SELECT saas.destino_confirma_horario(?::uuid, ?::uuid, now() + interval '20 days', "
                    + "now() + interval '20 days 30 minutes', ?)::text", enc, PROF_CLINICA, chave);
        }
    }

    private static void insereAgendamento(Connection c, String paciente, int dias, String chave) throws SQLException {
        executa(c, "INSERT INTO saas.agendamento(clinica_id, profissional_clinica_id, paciente_id, inicio, fim, origem, "
                + "chave_idempotencia) VALUES (?::uuid, ?::uuid, ?::uuid, now() + make_interval(days => " + dias + "), "
                + "now() + make_interval(days => " + dias + ", mins => 30), 'RECEPCAO', ?)", CLINICA, PROF_CLINICA, paciente, chave);
    }

    private static String agendamentoPorChave(String chave) throws SQLException {
        try (Connection c = superusuario()) {
            return texto(c, "SELECT id::text FROM saas.agendamento WHERE chave_idempotencia = ?", chave);
        }
    }

    private static String insereEnvio(String finalidade, String paciente, String enc, String ag) throws SQLException {
        try (Connection c = superusuario()) {
            return texto(c, "INSERT INTO saas.envio_notificacao(finalidade, canal, destinatario_tipo, destinatario_id, "
                    + "encaminhamento_id, agendamento_id, chave_idempotencia) VALUES (?, 'WHATSAPP', 'PACIENTE', ?::uuid, "
                    + "?::uuid, ?::uuid, gen_random_uuid()::text) RETURNING id::text", finalidade, paciente, enc, ag);
        }
    }

    private static String insereEnvioProfissional(String profissional) throws SQLException {
        try (Connection c = superusuario()) {
            return texto(c, "INSERT INTO saas.envio_notificacao(finalidade, canal, destinatario_tipo, destinatario_id, "
                    + "chave_idempotencia) VALUES ('AVISO_ORIGEM', 'WHATSAPP', 'PROFISSIONAL', ?::uuid, gen_random_uuid()::text) "
                    + "RETURNING id::text", profissional);
        }
    }

    private static String statusEnvio(String envio) throws SQLException {
        try (Connection c = superusuario()) {
            return texto(c, "SELECT status FROM saas.envio_notificacao WHERE id = ?::uuid", envio);
        }
    }

    private static String pacienteDe(String enc) throws SQLException {
        try (Connection c = superusuario()) {
            return texto(c, "SELECT paciente_id::text FROM saas.encaminhamento WHERE id = ?::uuid", enc);
        }
    }

    private static int contaProfissional(Connection c, String id) throws SQLException {
        return Integer.parseInt(texto(c, "SELECT count(*)::text FROM saas.profissional WHERE id = ?::uuid", id));
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

    private static int preparaLinhas(Connection jobs, String envio) throws SQLException {
        return Integer.parseInt(texto(jobs, "SELECT count(*)::text FROM saas.jobs_envio_prepara(?::uuid)", envio));
    }

    private static int contaNoLog(String trecho) {
        return (int) PG.getLogs().lines().filter(l -> l.contains(trecho)).count();
    }

    /** Espera ate 5 s pela linha no log do servidor (o log chega ao container por stream). */
    private static boolean esperaNoLog(String trecho) throws InterruptedException {
        for (int i = 0; i < 25; i++) {
            if (PG.getLogs().contains(trecho)) {
                return true;
            }
            Thread.sleep(200);
        }
        return false;
    }

    private static Connection encaminhador() throws SQLException {
        Connection c = conecta("saas_app");
        define(c, "app.sessao", TOKEN_ENCAMINHADOR);
        return c;
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
