package saasagenda.pacientes;

import java.time.Instant;
import java.util.List;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;
import saasagenda.identidade.ContextoAcesso;

/**
 * API pública de consentimento LGPD do módulo pacientes (docs/arquitetura/mapa-modulos.md,
 * pacientes; ADR-0022; spec da Fase 2, F9).
 * <p>
 * O texto de cada finalidade é versionado: a versão identifica exatamente um texto (mudar o texto
 * muda a versão, porque ela carrega o resumo SHA-256 do texto). O paciente aceita uma versão
 * identificada; o servidor grava o texto daquela versão, o paciente e o caso da sessão, o canal e a
 * data. Nada disso vem do cliente. Quem vê e quem altera decide a RLS do banco, aplicada pelo
 * {@code ContextoBanco} do contexto recebido.
 */
public interface ConsentimentoApi {

    /** Finalidades do modelo v2 ({@code consentimento.finalidade}). */
    Set<String> FINALIDADES = Set.of("AGENDAMENTO", "COMPARTILHAR_CASO", "COMUNICACAO_WHATSAPP");

    /** Texto vigente da finalidade; vazio para finalidade desconhecida. */
    Optional<Termo> termoVigente(String finalidade);

    /**
     * Concede o consentimento da versão vigente, para o paciente e o caso da sessão. Se já existe
     * consentimento ativo igual (mesma finalidade, caso, clínica e versão), devolve o mesmo, sem
     * gravar outro.
     *
     * @param encaminhamentoId caso pedido; tem que ser o caso da sessão (nulo: o caso da sessão)
     * @param clinicaId clínica pedida; se informada, tem que ser a destino do caso (para
     *        COMPARTILHAR_CASO, nula vale a destino)
     * @throws RecusaException finalidade ou versão inválida, caso que o ator não vê, clínica que não
     *         é a destino, caso encerrado, ator que não é paciente
     * @throws saasagenda.identidade.ContextoBanco.SemSessaoException sem sessão válida
     */
    Concessao conceder(ContextoAcesso contexto, String finalidade, String versao, UUID encaminhamentoId,
            UUID clinicaId, String ipOrigem);

    /** Consentimentos do caso da sessão do paciente (ativos e revogados), mais antigos primeiro. */
    List<Consentimento> listar(ContextoAcesso contexto);

    /**
     * Revoga um consentimento ativo do paciente, no caso da sessão. Revogar de novo não muda nada e
     * recusa com {@link Motivo#JA_REVOGADO}; consentimento de outro paciente ou de outro caso é
     * {@link Motivo#NAO_ENCONTRADO} e não é tocado.
     */
    void revogar(ContextoAcesso contexto, UUID consentimentoId, String ipOrigem);

    record Termo(String finalidade, String versao, String texto) {
    }

    record Concessao(UUID id, boolean novo) {
    }

    /** {@code texto} é o texto aceito, gravado inteiro: o titular vê exatamente o que aceitou. */
    record Consentimento(UUID id, String finalidade, String versao, String texto, UUID encaminhamentoId, UUID clinicaId,
            String canal, Instant aceitoEm, Instant revogadoEm) {
        public boolean ativo() {
            return revogadoEm == null;
        }
    }

    /** Motivo de recusa, sem detalhe interno; o controlador traduz em status HTTP. */
    enum Motivo {
        FINALIDADE_INVALIDA, VERSAO_INVALIDA, VERSAO_DESATUALIZADA, NAO_ENCONTRADO, CLINICA_INVALIDA,
        CASO_ENCERRADO, NAO_PERMITIDO, JA_REVOGADO
    }

    final class RecusaException extends RuntimeException {
        private static final long serialVersionUID = 1L;
        private final Motivo motivo;

        public RecusaException(Motivo motivo) {
            super(motivo.name(), null, false, false);
            this.motivo = motivo;
        }

        public Motivo motivo() {
            return motivo;
        }
    }
}
