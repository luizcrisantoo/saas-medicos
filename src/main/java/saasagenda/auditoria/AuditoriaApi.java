package saasagenda.auditoria;

import java.util.List;
import java.util.UUID;

/**
 * API pública do módulo auditoria (docs/arquitetura/mapa-modulos.md, auditoria).
 * {@link #consultar} não tem acesso próprio ao banco: só lê pelo {@link LeitorIds} que o chamador
 * entrega, ligado ao executor da transação em que o contexto da requisição já foi aplicado
 * (identidade, {@code ContextoBanco}); a RLS ({@code auditoria_admin_ve}) entrega eventos só ao
 * ADMIN da clínica do contexto.
 * <p>
 * Paginação por cursor (mais recentes primeiro): {@code limite} nulo usa
 * {@code saas.auditoria.pagina.padrao} (padrão 100); acima de {@code saas.auditoria.pagina.teto}
 * (padrão 500, nunca acima de {@link #TETO_ABSOLUTO}) é reduzido ao teto; menor que 1 é recusado.
 * {@code depoisDe} é o {@link Pagina#proximo()} da página anterior.
 */
public interface AuditoriaApi {

    /** Teto que nenhuma configuração ultrapassa. */
    int TETO_ABSOLUTO = 1000;

    Pagina consultar(LeitorIds leitor, UUID clinicaId, UUID depoisDe, Integer limite);

    /** Executa SQL fixo com parâmetros ligados e devolve a primeira coluna como UUID. */
    @FunctionalInterface
    interface LeitorIds {
        List<UUID> ids(String sql, Object... parametros);
    }

    /** Ids da página e o cursor da seguinte (nulo quando não há mais eventos visíveis). */
    record Pagina(List<UUID> ids, UUID proximo) {
        public Pagina {
            ids = List.copyOf(ids);
        }
    }
}
