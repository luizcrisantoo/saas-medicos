package saasagenda.identidade;

/**
 * As 8 ações de sistema do ADR-0024 (docs/arquitetura/mapa-modulos.md, seção 5). O texto do SQL
 * é fixo e só tem marcadores {@code ?}: nenhum valor entra no texto.
 */
public enum FuncaoJobs {
    ENVIOS_PENDENTES("SELECT * FROM saas.jobs_envios_pendentes(?)", 1),
    ENVIO_LINK_PACIENTE("SELECT saas.jobs_envio_link_paciente(?::uuid)", 1),
    ENVIO_PREPARA("SELECT * FROM saas.jobs_envio_prepara(?::uuid)", 1),
    ENVIO_RESULTADO("SELECT saas.jobs_envio_resultado(?::uuid, ?, ?)", 3),
    EXPIRAR_ENCAMINHAMENTOS("SELECT saas.jobs_expirar_encaminhamentos()", 0),
    CONSULTA_REALIZADA("SELECT saas.jobs_consulta_realizada(?::uuid)", 1),
    AGENDAMENTO_DESFEITO("SELECT saas.jobs_agendamento_desfeito(?::uuid)", 1),
    ANEXO_VARREDURA("SELECT saas.jobs_anexo_varredura(?::uuid, ?)", 2);

    private final String sql;
    private final int parametros;

    FuncaoJobs(String sql, int parametros) {
        this.sql = sql;
        this.parametros = parametros;
    }

    public String sql() {
        return sql;
    }

    public int parametros() {
        return parametros;
    }
}
