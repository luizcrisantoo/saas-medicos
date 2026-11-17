package saasagenda.identidade.contexto;

import java.util.function.Supplier;
import org.springframework.context.annotation.Profile;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.TransactionDefinition;
import org.springframework.transaction.support.TransactionSynchronizationManager;
import org.springframework.transaction.support.TransactionTemplate;
import saasagenda.identidade.ContextoAcesso;
import saasagenda.identidade.ContextoBanco;

/**
 * Único ponto do código que grava contexto no banco (ADR-0026, item 7; Red Team I-20). O teste de
 * arquitetura {@code ContextoTransacaoTest} recusa qualquer outro uso de {@code set_config} ou
 * {@code SET app.*} e qualquer valor fora de parâmetro ligado.
 */
@Component
@Profile("web")
class ContextoBancoJdbc implements ContextoBanco {

    /** Os três valores só como parâmetros ligados e locais à transação ({@code true}). */
    static final String APLICA = "SELECT set_config('app.sessao', ?, true), "
            + "set_config('app.clinica_id', ?, true), set_config('app.papel', ?, true)";

    /** A conexão tem que chegar do pool sem contexto (nenhum SET de sessão vazou nela). */
    static final String LIMPA = "SELECT coalesce(current_setting('app.sessao', true), '') = '' "
            + "AND coalesce(current_setting('app.clinica_id', true), '') = '' "
            + "AND coalesce(current_setting('app.papel', true), '') = ''";

    private final JdbcTemplate app;
    private final TransactionTemplate transacao;

    ContextoBancoJdbc(JdbcTemplate app, PlatformTransactionManager transacoes) {
        this.app = app;
        this.transacao = new TransactionTemplate(transacoes);
        this.transacao.setPropagationBehavior(TransactionDefinition.PROPAGATION_REQUIRED);
        this.transacao.setIsolationLevel(TransactionDefinition.ISOLATION_DEFAULT);
    }

    @Override
    public <T> T emTransacao(ContextoAcesso contexto, Supplier<T> trabalho) {
        if (contexto == null) {
            throw new SemSessaoException();
        }
        if (TransactionSynchronizationManager.isActualTransactionActive()) {
            // Um contexto por transação: aninhar misturaria o contexto de dois atores.
            throw new IllegalStateException("contexto exige transacao propria");
        }
        return transacao.execute(st -> {
            if (!Boolean.TRUE.equals(app.queryForObject(LIMPA, Boolean.class))) {
                throw new IllegalStateException("conexao com contexto residual");
            }
            app.queryForList(APLICA,
                    contexto.tokenSessao(),
                    contexto.clinicaId() == null ? "" : contexto.clinicaId().toString(),
                    contexto.papel() == null ? "" : contexto.papel());
            if (tipoAtor() == null) {
                throw new SemSessaoException();
            }
            return trabalho.get();
        });
    }

    @Override
    public String tipoAtor() {
        if (!TransactionSynchronizationManager.isActualTransactionActive()) {
            throw new IllegalStateException("fora de transacao");
        }
        return app.queryForObject("SELECT saas.ator_tipo()", String.class);
    }
}
