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
import org.springframework.stereotype.Component;
import saasagenda.identidade.ConsultaContexto;
import saasagenda.identidade.ContextoAcesso;
import saasagenda.identidade.ContextoBanco;
import saasagenda.identidade.SessaoApi;
import saasagenda.identidade.credencial.CredencialBanco;

/**
 * Sessão verificável no banco (ADR-0023, ADR-0024).
 * <ul>
 * <li>Abertura: pool próprio com a credencial {@code saas_auth}, que só executa {@code sessao_equipe_abre}.
 * O pool não é bean {@link DataSource}: o pool padrão do Spring Boot continua sendo o de {@code saas_app}.</li>
 * <li>Consulta e encerramento: pool padrão ({@code saas_app}) pelo executor de {@link ContextoBanco}; o token
 * entra só como parâmetro ligado em {@code set_config}, local à transação (ADR-0026, item 7).</li>
 * </ul>
 * Nada aqui grava log com token, sub ou mensagem do banco.
 */
@Component
@Profile("web")
class SessaoBanco implements SessaoApi, DisposableBean {

    static final String ABRE = "SELECT saas.sessao_equipe_abre(?)";
    static final String ENCERRA = "SELECT saas.sessao_encerra()::text";

    private final HikariDataSource auth;
    private final ContextoBanco contexto;

    SessaoBanco(
            @Value("${saas.db.auth.url}") String url,
            @Value("${saas.db.auth.username}") String usuario,
            @Value("${saas.db.auth.password}") String senha,
            ContextoBanco contexto) {
        // E-09: regra única de credencial (lista positiva): este pool é só saas_auth.
        CredencialBanco.exige(CredencialBanco.Uso.AUTH, usuario);
        HikariConfig cfg = new HikariConfig();
        cfg.setPoolName("saas-auth");
        cfg.setJdbcUrl(url);
        cfg.setUsername(usuario);
        cfg.setPassword(senha);
        cfg.setMaximumPoolSize(2);
        cfg.setMinimumIdle(0);
        cfg.setAutoCommit(true);
        this.auth = new HikariDataSource(cfg);
        this.contexto = contexto;
    }

    static boolean formatoValido(String token) {
        return ContextoAcesso.tokenValido(token);
    }

    @Override
    public Optional<String> abrirEquipe(String subOidc) {
        try (Connection c = auth.getConnection();
                PreparedStatement ps = c.prepareStatement(ABRE)) {
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
            return Optional.ofNullable(contexto.emTransacao(ContextoAcesso.daSessao(tokenSessao), ConsultaContexto::tipoAtor));
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
                    consulta -> consulta.queryForObject(ENCERRA, String.class));
        } catch (ContextoBanco.SemSessaoException e) {
            // Sessao ja encerrada, vencida ou inexistente: nada a encerrar.
        }
    }

    @Override
    public void destroy() {
        auth.close();
    }
}
