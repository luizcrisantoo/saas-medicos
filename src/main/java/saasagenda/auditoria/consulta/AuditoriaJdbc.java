package saasagenda.auditoria.consulta;

import java.util.List;
import java.util.UUID;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Profile;
import org.springframework.stereotype.Component;
import saasagenda.auditoria.AuditoriaApi;

/**
 * Consulta de auditoria sem acesso próprio ao banco: o SQL é fixo e todo valor (clínica, cursor e
 * limite) vai como parâmetro ligado, pelo leitor da transação com contexto.
 */
@Component
@Profile("web")
class AuditoriaJdbc implements AuditoriaApi {

    static final String PRIMEIRA = "SELECT e.id FROM saas.evento_auditoria e WHERE e.clinica_id = ? "
            + "ORDER BY e.ocorrido_em DESC, e.id DESC LIMIT ?";

    static final String SEGUINTE = "SELECT e.id FROM saas.evento_auditoria e WHERE e.clinica_id = ? "
            + "AND (e.ocorrido_em, e.id) < (SELECT c.ocorrido_em, c.id FROM saas.evento_auditoria c "
            + "WHERE c.id = ? AND c.clinica_id = ?) "
            + "ORDER BY e.ocorrido_em DESC, e.id DESC LIMIT ?";

    private final int padrao;
    private final int teto;

    AuditoriaJdbc(
            @Value("${saas.auditoria.pagina.padrao:100}") int padrao,
            @Value("${saas.auditoria.pagina.teto:500}") int teto) {
        if (teto < 1 || teto > TETO_ABSOLUTO || padrao < 1 || padrao > teto) {
            throw new IllegalStateException("paginacao de auditoria fora dos limites (1 <= padrao <= teto <= "
                    + TETO_ABSOLUTO + ")");
        }
        this.padrao = padrao;
        this.teto = teto;
    }

    @Override
    public Pagina consultar(LeitorIds leitor, UUID clinicaId, UUID depoisDe, Integer limite) {
        if (clinicaId == null) {
            throw new IllegalArgumentException("clinica");
        }
        if (limite != null && limite < 1) {
            throw new IllegalArgumentException("limite");
        }
        int n = limite == null ? padrao : Math.min(limite, teto);
        // Um a mais para saber se existe página seguinte.
        List<UUID> ids = depoisDe == null
                ? leitor.ids(PRIMEIRA, clinicaId, n + 1)
                : leitor.ids(SEGUINTE, clinicaId, depoisDe, clinicaId, n + 1);
        if (ids.size() > n) {
            List<UUID> pagina = ids.subList(0, n);
            return new Pagina(pagina, pagina.get(n - 1));
        }
        return new Pagina(ids, null);
    }
}
