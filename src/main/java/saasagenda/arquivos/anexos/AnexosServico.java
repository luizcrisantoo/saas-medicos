package saasagenda.arquivos.anexos;

import java.util.UUID;
import org.springframework.context.annotation.Profile;
import org.springframework.dao.DataAccessException;
import org.springframework.stereotype.Component;
import saasagenda.arquivos.ArquivosApi;
import saasagenda.arquivos.storage.AssinadorS3;
import saasagenda.auditoria.AuditoriaApi;
import saasagenda.identidade.ContextoAcesso;
import saasagenda.identidade.ContextoBanco;

/**
 * Anexos do encaminhamento (ADR-0010; spec da Fase 2, F8). Todo acesso ao banco passa pelo
 * {@link ContextoBanco} (papel {@code saas_app}, RLS com o contexto da requisição); o SQL é texto
 * fixo com parâmetros ligados. A URL é assinada dentro da transação que autoriza e só sai dela
 * depois do commit: se a inclusão do anexo ou do EventoAuditoria falhar, nenhuma URL é devolvida.
 */
@Component
@Profile("web")
class AnexosServico implements ArquivosApi {

    /** O caso existe para o ator (políticas de SELECT de {@code encaminhamento}). */
    static final String CASO_VISIVEL = "SELECT EXISTS (SELECT 1 FROM saas.encaminhamento e WHERE e.id = ?)";

    /**
     * Quem envia sai da sessão no banco (paciente do link ou profissional de origem); a política
     * {@code anexo_inclui} confere caso, status e ator. A chave do objeto é o padrão do banco.
     */
    static final String INCLUI = "INSERT INTO saas.anexo_encaminhamento"
            + "(encaminhamento_id, tipo_mime, tamanho_bytes, sha256, enviado_por_tipo, enviado_por_id) "
            + "VALUES (?, ?, ?, ?, "
            + "CASE WHEN saas.ator_paciente() IS NOT NULL THEN 'PACIENTE' ELSE 'PROFISSIONAL' END, "
            + "coalesce(saas.ator_paciente(), saas.ator_profissional())) RETURNING id";

    static final String CHAVE = "SELECT a.chave_storage FROM saas.anexo_encaminhamento a WHERE a.id = ?";

    /** Status do anexo visível ao ator (política {@code anexo_ver}); nada se não for visível. */
    static final String STATUS = "SELECT a.status_varredura FROM saas.anexo_encaminhamento a WHERE a.id = ?";

    static final String ACAO_DOWNLOAD = "DOWNLOAD_ANEXO";
    static final String RECURSO = "anexo_encaminhamento";
    static final String CANAL = "WEB";

    private final ContextoBanco banco;
    private final AuditoriaApi auditoria;
    private final AssinadorS3 assinador;

    AnexosServico(ContextoBanco banco, AuditoriaApi auditoria, AssinadorS3 assinador) {
        this.banco = banco;
        this.auditoria = auditoria;
        this.assinador = assinador;
    }

    @Override
    public UploadAutorizado autorizarUpload(ContextoAcesso contexto, UUID encaminhamentoId, String tipoMime,
            long tamanhoBytes, byte[] sha256) {
        if (tipoMime == null || !TIPOS.contains(tipoMime)) {
            throw new RecusaException(Motivo.TIPO_INVALIDO);
        }
        if (tamanhoBytes < 1 || tamanhoBytes > TAMANHO_MAXIMO) {
            throw new RecusaException(Motivo.TAMANHO_INVALIDO);
        }
        if (sha256 == null || sha256.length != 32) {
            throw new RecusaException(Motivo.HASH_INVALIDO);
        }
        if (encaminhamentoId == null) {
            throw new RecusaException(Motivo.NAO_ENCONTRADO);
        }
        if (!assinador.disponivel()) {
            throw new RecusaException(Motivo.INDISPONIVEL);
        }
        byte[] hash = sha256.clone();
        return banco.emTransacao(contexto, consulta -> {
            if (!Boolean.TRUE.equals(consulta.queryForObject(CASO_VISIVEL, Boolean.class, encaminhamentoId))) {
                throw new RecusaException(Motivo.NAO_ENCONTRADO);
            }
            UUID anexo;
            try {
                anexo = consulta.queryForObject(INCLUI, UUID.class, encaminhamentoId, tipoMime, tamanhoBytes, hash);
            } catch (DataAccessException e) {
                // Política anexo_inclui (ator que vê o caso mas não anexa nele, caso encerrado).
                throw new RecusaException(Motivo.NAO_PERMITIDO);
            }
            String chave = consulta.queryForObject(CHAVE, String.class, anexo);
            AssinadorS3.UrlAssinada url = assinador.assinaPut(chave, tipoMime, tamanhoBytes, hash);
            return new UploadAutorizado(anexo, url.url(), url.cabecalhos(), url.expiraEm());
        });
    }

    @Override
    public DownloadAutorizado urlDownload(ContextoAcesso contexto, UUID anexoId, String ipOrigem) {
        if (anexoId == null) {
            throw new RecusaException(Motivo.NAO_ENCONTRADO);
        }
        if (!assinador.disponivel()) {
            throw new RecusaException(Motivo.INDISPONIVEL);
        }
        return banco.emTransacao(contexto, consulta -> {
            String status = consulta.queryForList(STATUS, String.class, anexoId).stream().findFirst().orElse(null);
            if (status == null) {
                throw new RecusaException(Motivo.NAO_ENCONTRADO);
            }
            if (!"LIMPO".equals(status)) {
                throw new RecusaException(Motivo.NAO_LIMPO);
            }
            String chave = consulta.queryForObject(CHAVE, String.class, anexoId);
            // Registro do acesso antes de emitir a URL, na mesma transação.
            auditoria.registrar(consulta::update, ACAO_DOWNLOAD, RECURSO, anexoId, contexto.clinicaId(),
                    ipOrigem, CANAL);
            AssinadorS3.UrlAssinada url = assinador.assinaGet(chave);
            return new DownloadAutorizado(url.url(), url.expiraEm());
        });
    }
}
