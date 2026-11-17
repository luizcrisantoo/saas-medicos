package saasagenda.identidade.jobs;

import com.zaxxer.hikari.HikariConfig;
import com.zaxxer.hikari.HikariDataSource;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.util.Set;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.TimeUnit;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.DisposableBean;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Profile;
import org.springframework.stereotype.Component;
import saasagenda.identidade.FuncaoJobs;
import saasagenda.identidade.JobsApi;

/**
 * Processo de jobs (E-09, ADR-0024): pool próprio só com {@code SAAS_DB_JOBS_*}. Não existe no
 * processo web, e o processo de jobs não tem pool {@code saas_app} nem {@code saas_auth}. A conexão
 * abre na partida e fica viva (conferida a cada 30 s sem SQL de aplicação). Nada aqui grava valor
 * de parâmetro, contato ou segredo em log.
 */
@Component
@Profile("jobs")
class JobsBanco implements JobsApi, DisposableBean {

    private static final Logger LOG = LoggerFactory.getLogger(JobsBanco.class);
    private static final Set<String> PAPEIS_PROIBIDOS = Set.of("saas_app", "saas_auth", "saas_owner",
            "saas_funcoes", "saas_migracao", "postgres");

    private final HikariDataSource jobs;
    private final ScheduledExecutorService batimento;

    JobsBanco(
            @Value("${saas.db.jobs.url}") String url,
            @Value("${saas.db.jobs.username}") String usuario,
            @Value("${saas.db.jobs.password}") String senha) {
        if (usuario == null || usuario.isBlank() || PAPEIS_PROIBIDOS.contains(usuario.trim())) {
            throw new IllegalStateException("credencial de jobs invalida");
        }
        HikariConfig cfg = new HikariConfig();
        cfg.setPoolName("saas-jobs");
        cfg.setJdbcUrl(url);
        cfg.setUsername(usuario);
        cfg.setPassword(senha);
        cfg.setMaximumPoolSize(2);
        cfg.setMinimumIdle(1);
        cfg.setAutoCommit(true);
        this.jobs = new HikariDataSource(cfg);
        try (Connection c = jobs.getConnection()) {
            if (!c.isValid(5)) {
                throw new IllegalStateException("banco de jobs indisponivel");
            }
        } catch (SQLException e) {
            jobs.close();
            throw new IllegalStateException("banco de jobs indisponivel");
        }
        this.batimento = Executors.newSingleThreadScheduledExecutor(r -> {
            Thread t = new Thread(r, "saas-jobs-batimento");
            t.setDaemon(false);
            return t;
        });
        this.batimento.scheduleWithFixedDelay(this::confere, 30, 30, TimeUnit.SECONDS);
        LOG.info("processo de jobs conectado ao banco");
    }

    private void confere() {
        try (Connection c = jobs.getConnection()) {
            if (!c.isValid(5)) {
                LOG.warn("conexao de jobs invalida");
            }
        } catch (SQLException e) {
            LOG.warn("banco de jobs indisponivel: {}", e.getSQLState());
        }
    }

    @Override
    public <T> T chamar(FuncaoJobs funcao, LeitorResultado<T> leitor, Object... argumentos) {
        Object[] args = argumentos == null ? new Object[0] : argumentos;
        if (args.length != funcao.parametros()) {
            throw new IllegalArgumentException("numero de parametros");
        }
        try (Connection c = jobs.getConnection(); PreparedStatement ps = c.prepareStatement(funcao.sql())) {
            for (int i = 0; i < args.length; i++) {
                ps.setObject(i + 1, args[i] == null ? null : (args[i] instanceof Number ? args[i] : args[i].toString()));
            }
            try (ResultSet rs = ps.executeQuery()) {
                return leitor.ler(rs);
            }
        } catch (SQLException e) {
            throw new IllegalStateException("falha na funcao de jobs " + funcao.name() + " (" + e.getSQLState() + ")");
        }
    }

    @Override
    public void destroy() {
        batimento.shutdownNow();
        jobs.close();
    }
}
