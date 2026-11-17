package saasagenda.identidade;

import java.sql.ResultSet;
import java.sql.SQLException;

/**
 * Acesso ao banco do processo de jobs (E-09, ADR-0024): só pela credencial {@code saas_jobs} e só
 * pelas funções {@code jobs_*} de {@link FuncaoJobs}, com parâmetros ligados. Existe apenas no
 * processo {@code SAAS_PROCESSO=jobs}; o processo web não tem este bean nem a credencial.
 */
public interface JobsApi {

    <T> T chamar(FuncaoJobs funcao, LeitorResultado<T> leitor, Object... argumentos);

    @FunctionalInterface
    interface LeitorResultado<T> {
        T ler(ResultSet rs) throws SQLException;
    }
}
