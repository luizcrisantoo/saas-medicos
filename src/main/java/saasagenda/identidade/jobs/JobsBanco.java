package saasagenda.identidade.jobs;

import com.zaxxer.hikari.HikariConfig;
import com.zaxxer.hikari.HikariDataSource;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
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
import saasagenda.identidade.credencial.CredencialBanco;

/**
 * Processo de jobs (E-09, ADR-0024): pool próprio só com {@code SAAS_DB_JOBS_*}. Não existe no
 * processo web, e o processo de jobs não tem pool {@code saas_app} nem {@code saas_auth}. A conexão
 * abre na partida e fica viva (conferida a cada {@code saas.jobs.batimento-segundos}, padrão 30 s,
 * sem SQL de aplicação); o pool tem até {@code saas.jobs.pool.maximo} conexões (padrão 2). Nada aqui grava valor
 * de parâmetro, contato ou segredo em log.
 */
@Component
@Profile("jobs")
class JobsBanco implements JobsApi, DisposableBean {

    private static final Logger LOG = LoggerFactory.getLogger(JobsBanco.class);
    /** Faixas aceitas da configuração (fora delas a partida falha). */
    static final int POOL_MAXIMO_TETO = 10;
    static final int BATIMENTO_MINIMO_S = 5;
    static final int BATIMENTO_MAXIMO_S = 300;

    private final HikariDataSource jobs;
    private final ScheduledExecutorService batimento;

    JobsBanco(
            @Value("${saas.db.jobs.url}") String url,
            @Value("${saas.db.jobs.username}") String usuario,
            @Value("${saas.db.jobs.password}") String senha,
            @Value("${saas.jobs.pool.maximo:2}") int poolMaximo,
            @Value("${saas.jobs.batimento-segundos:30}") int batimentoSegundos) {
        // E-09: lista positiva única (CredencialBanco): este processo é só saas_jobs.
        CredencialBanco.exige(CredencialBanco.Uso.JOBS, usuario);
        if (poolMaximo < 1 || poolMaximo > POOL_MAXIMO_TETO) {
            throw new IllegalStateException("saas.jobs.pool.maximo fora de 1.." + POOL_MAXIMO_TETO);
        }
        if (batimentoSegundos < BATIMENTO_MINIMO_S || batimentoSegundos > BATIMENTO_MAXIMO_S) {
            throw new IllegalStateException("saas.jobs.batimento-segundos fora de "
                    + BATIMENTO_MINIMO_S + ".." + BATIMENTO_MAXIMO_S);
        }
        HikariConfig cfg = new HikariConfig();
        cfg.setPoolName("saas-jobs");
        cfg.setJdbcUrl(url);
        cfg.setUsername(usuario);
        cfg.setPassword(senha);
        cfg.setMaximumPoolSize(poolMaximo);
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
        this.batimento.scheduleWithFixedDelay(this::confere, batimentoSegundos, batimentoSegundos, TimeUnit.SECONDS);
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
