package saasagenda.identidade;

import java.util.function.Function;

/**
 * Aplica o contexto da requisição no banco, sempre dentro de uma transação nova do pool
 * {@code saas_app} (ADR-0023; ADR-0026, item 7; Red Team I-20):
 * {@code set_config('app.sessao'|'app.clinica_id'|'app.papel', ?, true)}, com parâmetro ligado e
 * local à transação. Nada de {@code SET} de sessão e nada de valor no texto do SQL: ao fim da
 * transação o PostgreSQL desfaz os três valores e a conexão volta limpa ao pool.
 * <p>
 * É o único caminho de SQL do papel {@code saas_app}: o trabalho recebe o {@link ConsultaContexto}
 * criado para esta transação, e o pool recusa SQL que não passe por ele (inclusive um
 * {@code @Transactional} comum com {@code JdbcTemplate}).
 */
public interface ContextoBanco {

    /**
     * Abre a transação, confere que a conexão chegou sem contexto (se não, descarta a conexão do
     * pool e recusa), aplica o contexto, exige sessão válida ({@code ator_tipo()} não nulo) e
     * executa o trabalho na mesma transação com o executor ligado a ela.
     *
     * @throws SemSessaoException sessão inexistente, vencida ou encerrada
     * @throws IllegalStateException já existe transação no fio (contexto é um por transação) ou a
     *         conexão chegou com contexto residual
     */
    <T> T emTransacao(ContextoAcesso contexto, Function<ConsultaContexto, T> trabalho);

    /** Sessão ausente ou inválida no banco: a resposta é 401 sem detalhe. */
    final class SemSessaoException extends RuntimeException {
        private static final long serialVersionUID = 1L;

        public SemSessaoException() {
            super("sem sessao", null, false, false);
        }
    }
}
