package saasagenda.auditoria.consulta;

import java.util.List;
import java.util.UUID;
import org.springframework.context.annotation.Profile;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;
import org.springframework.transaction.support.TransactionSynchronizationManager;
import saasagenda.auditoria.AuditoriaApi;

@Component
@Profile("web")
class AuditoriaJdbc implements AuditoriaApi {

    private final JdbcTemplate app;

    AuditoriaJdbc(JdbcTemplate app) {
        this.app = app;
    }

    @Override
    public List<UUID> consultar(UUID clinicaId) {
        if (!TransactionSynchronizationManager.isActualTransactionActive()) {
            // Fora da transação com contexto, a RLS veria uma conexão sem sessão: recusa explícita.
            throw new IllegalStateException("consulta de auditoria exige transacao com contexto");
        }
        return app.queryForList("SELECT id FROM saas.evento_auditoria WHERE clinica_id = ? "
                + "ORDER BY ocorrido_em DESC, id LIMIT 500", UUID.class, clinicaId);
    }
}
