package saasagenda.arquivos;

import java.time.Instant;
import java.util.Map;
import java.util.UUID;
import saasagenda.identidade.ContextoAcesso;

/**
 * API pública do módulo arquivos (docs/arquitetura/mapa-modulos.md, arquivos; ADR-0010).
 * <p>
 * O arquivo nunca passa pela aplicação: ela registra o anexo e devolve uma URL pré-assinada SigV4
 * (S3, {@code sa-east-1}, bucket do ambiente) de no máximo 5 minutos. A chave do objeto é a
 * {@code chave_storage} gerada pelo banco (UUID aleatório): nunca nome de arquivo nem dado do
 * paciente. Quem pode anexar e quem vê o anexo decide a RLS do banco, aplicada pelo
 * {@code ContextoBanco} do contexto recebido.
 * <p>
 * URL, chave e credencial nunca vão para log, exceção ou {@code toString} (ADR-0026, itens 3 e 5).
 */
public interface ArquivosApi {

    /** Tipos aceitos, pelo valor exato (sem parâmetros como {@code charset}; sem SVG). */
    java.util.Set<String> TIPOS = java.util.Set.of("application/pdf", "image/jpeg", "image/png");

    /** 20 MiB (ADR-0010; CHECK de {@code anexo_encaminhamento.tamanho_bytes}). */
    long TAMANHO_MAXIMO = 20L * 1024 * 1024;

    /** Validade máxima de qualquer URL assinada (spec da Fase 2, P2: "poucos minutos"). */
    long VALIDADE_MAXIMA_SEGUNDOS = 300;

    /**
     * Registra o anexo (PENDENTE de varredura) no caso, se o ator do contexto pode anexar nele, e
     * devolve a URL PUT com SSE-KMS, tipo, tamanho e SHA-256 assinados.
     *
     * @throws RecusaException tipo, tamanho ou hash inválidos; caso não visível ao ator; ator sem
     *         permissão de anexar; storage não configurado
     * @throws saasagenda.identidade.ContextoBanco.SemSessaoException sem sessão válida
     */
    UploadAutorizado autorizarUpload(ContextoAcesso contexto, UUID encaminhamentoId, String tipoMime,
            long tamanhoBytes, byte[] sha256);

    /**
     * URL GET de um anexo LIMPO que o ator vê, com EventoAuditoria gravado na mesma transação que
     * autoriza: se a auditoria falhar, nenhuma URL é emitida.
     *
     * @throws RecusaException anexo inexistente ou não visível, PENDENTE ou INFECTADO; storage não
     *         configurado
     * @throws saasagenda.identidade.ContextoBanco.SemSessaoException sem sessão válida
     */
    DownloadAutorizado urlDownload(ContextoAcesso contexto, UUID anexoId, String ipOrigem);

    /** URL de upload e os cabeçalhos que o cliente tem que mandar (todos assinados). */
    record UploadAutorizado(UUID anexoId, String url, Map<String, String> cabecalhos, Instant expiraEm) {
        public UploadAutorizado {
            cabecalhos = Map.copyOf(cabecalhos);
        }

        @Override
        public String toString() {
            return "UploadAutorizado[anexo=" + anexoId + "]";
        }
    }

    record DownloadAutorizado(String url, Instant expiraEm) {
        @Override
        public String toString() {
            return "DownloadAutorizado[expiraEm=" + expiraEm + "]";
        }
    }

    /** Motivo de recusa, sem detalhe interno; o controlador traduz em status HTTP. */
    enum Motivo {
        TIPO_INVALIDO, TAMANHO_INVALIDO, HASH_INVALIDO, NAO_ENCONTRADO, NAO_PERMITIDO, NAO_LIMPO, INDISPONIVEL
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
