package saasagenda.identidade;

import java.util.List;

/**
 * Único executor de consultas do papel {@code saas_app} (ADR-0026, item 7; Red Team I-20). Uma
 * instância só existe dentro de {@link ContextoBanco#emTransacao}: é o token de que o contexto da
 * requisição foi aplicado naquela transação. Cada chamada confere que a transação corrente é a
 * mesma em que o contexto foi aplicado, na mesma conexão, e que o token ainda está vivo; fora disso
 * recusa. O pool {@code saas_app} recusa qualquer SQL que não venha por aqui (falha fechada).
 * O SQL é sempre texto fixo; todo valor vai como parâmetro ligado ({@code ?}).
 */
public interface ConsultaContexto {

    <T> List<T> queryForList(String sql, Class<T> tipo, Object... parametros);

    <T> T queryForObject(String sql, Class<T> tipo, Object... parametros);

    /**
     * INSERT/UPDATE sem {@code RETURNING} (por exemplo, a inclusão de EventoAuditoria por quem não
     * pode ler a tabela); devolve as linhas afetadas.
     */
    int update(String sql, Object... parametros);

    /** Tipo do ator da sessão aplicada (EQUIPE, PACIENTE, ENCAMINHADOR) ou nulo sem sessão válida. */
    String tipoAtor();
}
