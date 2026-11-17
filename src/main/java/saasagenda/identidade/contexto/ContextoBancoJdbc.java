package saasagenda.identidade.contexto;

import java.util.List;
import java.util.function.Function;
import java.util.function.Supplier;
import javax.sql.DataSource;
import org.springframework.context.annotation.Profile;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.ConnectionHolder;
import org.springframework.stereotype.Component;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.TransactionDefinition;
import org.springframework.transaction.support.TransactionSynchronizationManager;
import org.springframework.transaction.support.TransactionTemplate;
import saasagenda.identidade.ConsultaContexto;
import saasagenda.identidade.ContextoAcesso;
import saasagenda.identidade.ContextoBanco;

/**
 * Único ponto do código que grava contexto no banco e único executor de SQL do papel
 * {@code saas_app} (ADR-0026, item 7; Red Team I-20). O teste de arquitetura
 * {@code ContextoArquiteturaTest} recusa qualquer outro uso de {@code set_config} ou
 * {@code SET app.*}, qualquer SQL montado com valor e qualquer outro chamador da permissão do
 * {@link PoolAppGuardado}.
 */
@Component
@Profile("web")
class ContextoBancoJdbc implements ContextoBanco {

    /** Os três valores só como parâmetros ligados e locais à transação ({@code true}). */
    static final String APLICA = "SELECT set_config('app.sessao', ?, true), "
            + "set_config('app.clinica_id', ?, true), set_config('app.papel', ?, true)";

    /** A conexão tem que chegar do pool sem contexto (nenhum SET de sessão nem de papel vazou nela). */
    static final String LIMPA = "SELECT coalesce(current_setting('app.sessao', true), '') = '' "
            + "AND coalesce(current_setting('app.clinica_id', true), '') = '' "
            + "AND coalesce(current_setting('app.papel', true), '') = '' "
            + "AND current_user = session_user";

    static final String ATOR = "SELECT saas.ator_tipo()";

    private final PoolAppGuardado dataSource;
    private final JdbcTemplate jdbc;
    private final TransactionTemplate transacao;

    ContextoBancoJdbc(DataSource dataSource, PlatformTransactionManager transacoes) {
        if (!(dataSource instanceof PoolAppGuardado guardado)) {
            throw new IllegalStateException("pool saas_app sem guarda de contexto");
        }
        this.dataSource = guardado;
        this.jdbc = new JdbcTemplate(guardado);
        this.transacao = new TransactionTemplate(transacoes);
        this.transacao.setPropagationBehavior(TransactionDefinition.PROPAGATION_REQUIRED);
        this.transacao.setIsolationLevel(TransactionDefinition.ISOLATION_DEFAULT);
    }

    @Override
    public <T> T emTransacao(ContextoAcesso contexto, Function<ConsultaContexto, T> trabalho) {
        if (contexto == null) {
            throw new SemSessaoException();
        }
        if (TransactionSynchronizationManager.isActualTransactionActive()) {
            // Um contexto por transação: aninhar misturaria o contexto de dois atores.
            throw new IllegalStateException("contexto exige transacao propria");
        }
        return transacao.execute(st -> {
            PoolAppGuardado.ConexaoGuardada conexao = conexaoDaTransacao();
            if (!Boolean.TRUE.equals(PoolAppGuardado.comPermissao(conexao,
                    () -> jdbc.queryForObject(LIMPA, Boolean.class)))) {
                // Conexão contaminada: sai do pool para sempre; a próxima requisição recebe outra.
                conexao.descartar();
                throw new IllegalStateException("conexao com contexto residual descartada");
            }
            PoolAppGuardado.comPermissao(conexao, () -> jdbc.queryForList(APLICA,
                    contexto.tokenSessao(),
                    contexto.clinicaId() == null ? "" : contexto.clinicaId().toString(),
                    contexto.papel() == null ? "" : contexto.papel()));
            Token token = new Token(conexao);
            TransactionSynchronizationManager.bindResource(Token.class, token);
            try {
                if (token.tipoAtor() == null) {
                    throw new SemSessaoException();
                }
                return trabalho.apply(token);
            } finally {
                token.vivo = false;
                TransactionSynchronizationManager.unbindResourceIfPossible(Token.class);
            }
        });
    }

    private PoolAppGuardado.ConexaoGuardada conexaoDaTransacao() {
        Object holder = TransactionSynchronizationManager.getResource(dataSource);
        if (holder instanceof ConnectionHolder h && h.getConnection() instanceof PoolAppGuardado.ConexaoGuardada c) {
            return c;
        }
        throw new IllegalStateException("transacao sem conexao guardada");
    }

    /**
     * O token de contexto: prova de que {@link #APLICA} rodou nesta transação, nesta conexão. Cada
     * consulta confere as três coisas antes de receber a permissão do pool.
     */
    private final class Token implements ConsultaContexto {
        private final PoolAppGuardado.ConexaoGuardada conexao;
        private volatile boolean vivo = true;

        Token(PoolAppGuardado.ConexaoGuardada conexao) {
            this.conexao = conexao;
        }

        private <T> T executa(Supplier<T> sql) {
            if (!vivo
                    || !TransactionSynchronizationManager.isActualTransactionActive()
                    || TransactionSynchronizationManager.getResource(Token.class) != this
                    || conexaoDaTransacao() != conexao) {
                throw new IllegalStateException("consulta sem contexto aplicado nesta transacao");
            }
            return PoolAppGuardado.comPermissao(conexao, sql);
        }

        @Override
        public <T> List<T> queryForList(String sql, Class<T> tipo, Object... parametros) {
            return executa(() -> jdbc.queryForList(sql, tipo, parametros));
        }

        @Override
        public <T> T queryForObject(String sql, Class<T> tipo, Object... parametros) {
            return executa(() -> jdbc.queryForObject(sql, tipo, parametros));
        }

        @Override
        public String tipoAtor() {
            return executa(() -> jdbc.queryForObject(ATOR, String.class));
        }
    }
}
