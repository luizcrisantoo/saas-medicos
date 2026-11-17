package saasagenda.identidade.sessao;

import com.zaxxer.hikari.HikariConfig;
import com.zaxxer.hikari.HikariDataSource;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.util.Optional;
import javax.sql.DataSource;
import org.springframework.beans.factory.DisposableBean;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Profile;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;
import saasagenda.identidade.ContextoAcesso;
import saasagenda.identidade.ContextoBanco;
import saasagenda.identidade.SessaoApi;

/**
 * Sessão verificável no banco (ADR-0023, ADR-0024).
 * <ul>
 * <li>Abertura: pool próprio com a credencial {@code saas_auth}, que só executa {@code sessao_equipe_abre}.
 * O pool não é bean {@link DataSource}: o pool padrão do Spring Boot continua sendo o de {@code saas_app}.</li>
 * <li>Consulta e encerramento: pool padrão ({@code saas_app}) pelo {@link ContextoBanco}; o token
 * entra só como parâmetro ligado em {@code set_config}, local à transação (ADR-0026, item 7).</li>
 * </ul>
 * Nada aqui grava log com token, sub ou mensagem do banco.
 */
@Component
@Profile("web")
class SessaoBanco implements SessaoApi, DisposableBean {

    private final HikariDataSource auth;
    private final JdbcTemplate app;
    private final ContextoBanco contexto;

    SessaoBanco(
            @Value("${saas.db.auth.url}") String url,
            @Value("${saas.db.auth.username}") String usuario,
            @Value("${saas.db.auth.password}") String senha,
            JdbcTemplate app,
            ContextoBanco contexto) {
        if (usuario == null || usuario.isBlank() || "saas_jobs".equals(usuario.trim())) {
            // E-09: o processo web nunca usa a credencial de jobs.
            throw new IllegalStateException("credencial de autenticacao invalida");
        }
        HikariConfig cfg = new HikariConfig();
        cfg.setPoolName("saas-auth");
        cfg.setJdbcUrl(url);
        cfg.setUsername(usuario);
        cfg.setPassword(senha);
        cfg.setMaximumPoolSize(2);
        cfg.setMinimumIdle(0);
        cfg.setAutoCommit(true);
        this.auth = new HikariDataSource(cfg);
        this.app = app;
        this.contexto = contexto;
    }

    static boolean formatoValido(String token) {
        return ContextoAcesso.tokenValido(token);
    }

    @Override
    public Optional<String> abrirEquipe(String subOidc) {
        try (Connection c = auth.getConnection();
                PreparedStatement ps = c.prepareStatement("SELECT saas.sessao_equipe_abre(?)")) {
            ps.setString(1, subOidc);
            try (ResultSet rs = ps.executeQuery()) {
                String token = rs.next() ? rs.getString(1) : null;
                return formatoValido(token) ? Optional.of(token) : Optional.empty();
            }
        } catch (SQLException e) {
            // Usuario inexistente ou inativo ('nao permitido') ou banco indisponivel: recusa sem detalhe.
            return Optional.empty();
        }
    }

    @Override
    public Optional<String> tipo(String tokenSessao) {
        if (!formatoValido(tokenSessao)) {
            return Optional.empty();
        }
        try {
            return Optional.ofNullable(contexto.emTransacao(ContextoAcesso.daSessao(tokenSessao), contexto::tipoAtor));
        } catch (ContextoBanco.SemSessaoException e) {
            return Optional.empty();
        }
    }

    @Override
    public void encerrar(String tokenSessao) {
        if (!formatoValido(tokenSessao)) {
            return;
        }
        try {
            contexto.emTransacao(ContextoAcesso.daSessao(tokenSessao),
                    () -> app.queryForObject("SELECT saas.sessao_encerra()::text", String.class));
        } catch (ContextoBanco.SemSessaoException e) {
            // Sessao ja encerrada, vencida ou inexistente: nada a encerrar.
        }
    }

    @Override
    public void destroy() {
        auth.close();
    }
}
