package saasagenda.identidade;

import java.util.function.Supplier;

/**
 * Aplica o contexto da requisição no banco, sempre dentro de uma transação nova do pool
 * {@code saas_app} (ADR-0023; ADR-0026, item 7; Red Team I-20):
 * {@code set_config('app.sessao'|'app.clinica_id'|'app.papel', ?, true)}, com parâmetro ligado e
 * local à transação. Nada de {@code SET} de sessão e nada de valor no texto do SQL: ao fim da
 * transação o PostgreSQL desfaz os três valores e a conexão volta limpa ao pool.
 */
public interface ContextoBanco {

    /**
     * Abre a transação, confere que a conexão chegou sem contexto, aplica o contexto, exige sessão
     * válida ({@code ator_tipo()} não nulo) e executa o trabalho na mesma transação.
     *
     * @throws SemSessaoException sessão inexistente, vencida ou encerrada
     * @throws IllegalStateException já existe transação no fio (contexto é um por transação)
     */
    <T> T emTransacao(ContextoAcesso contexto, Supplier<T> trabalho);

    /** Tipo do ator da sessão aplicada na transação corrente (EQUIPE, PACIENTE, ENCAMINHADOR). */
    String tipoAtor();

    /** Sessão ausente ou inválida no banco: a resposta é 401 sem detalhe. */
    final class SemSessaoException extends RuntimeException {
        private static final long serialVersionUID = 1L;

        public SemSessaoException() {
            super("sem sessao", null, false, false);
        }
    }
}
