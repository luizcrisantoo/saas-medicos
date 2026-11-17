package saasagenda.auditoria;

import java.util.List;
import java.util.UUID;

/**
 * API pública do módulo auditoria (docs/arquitetura/mapa-modulos.md, auditoria).
 * {@link #consultar(UUID)} só roda dentro da transação em que o contexto da requisição já foi
 * aplicado (identidade, {@code ContextoBanco}); a RLS ({@code auditoria_admin_ve}) entrega
 * eventos só ao ADMIN da clínica do contexto.
 */
public interface AuditoriaApi {

    /** Ids dos eventos da clínica visíveis ao contexto da transação corrente (mais recentes primeiro). */
    List<UUID> consultar(UUID clinicaId);
}
