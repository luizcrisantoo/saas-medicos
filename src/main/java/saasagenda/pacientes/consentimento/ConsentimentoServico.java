package saasagenda.pacientes.consentimento;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.time.Instant;
import java.time.OffsetDateTime;
import java.util.List;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.context.annotation.Profile;
import org.springframework.dao.DataAccessException;
import org.springframework.stereotype.Component;
import saasagenda.auditoria.AuditoriaApi;
import saasagenda.identidade.ConsultaContexto;
import saasagenda.identidade.ContextoAcesso;
import saasagenda.identidade.ContextoBanco;
import saasagenda.pacientes.ConsentimentoApi;

/**
 * Consentimento LGPD pela sessão do paciente (ADR-0022; spec da Fase 2, F9). Todo acesso ao banco
 * passa pelo {@link ContextoBanco} (papel {@code saas_app}, RLS com a sessão da requisição); o SQL
 * é texto fixo com parâmetros ligados. Paciente e caso saem da sessão no banco
 * ({@code ator_paciente()}, {@code ator_encaminhamento()}), o texto sai do catálogo do servidor, a
 * data é a do banco e o canal é o da API web: nenhum desses vem do cliente. Concessão e revogação
 * gravam EventoAuditoria na mesma transação.
 */
@Component
@Profile("web")
class ConsentimentoServico implements ConsentimentoApi {

    /** Destino e status do caso, só se for o caso da sessão do paciente (RLS e filtro explícito). */
    static final String CASO = "SELECT json_build_object('destino', e.clinica_destino_id, 'status', e.status)::text "
            + "FROM saas.encaminhamento e "
            + "WHERE e.id = ? AND e.id = saas.ator_encaminhamento() AND e.paciente_id = saas.ator_paciente()";

    static final String CASO_DA_SESSAO = "SELECT saas.ator_encaminhamento()";

    static final String EXISTENTE = "SELECT c.id FROM saas.consentimento c "
            + "WHERE c.paciente_id = saas.ator_paciente() AND c.encaminhamento_id = ? AND c.finalidade = ? "
            + "AND c.clinica_id IS NOT DISTINCT FROM ?::uuid AND c.versao_texto = ? AND c.revogado_em IS NULL "
            + "ORDER BY c.aceito_em LIMIT 1";

    /** Paciente da sessão, canal da API web e data do banco; a política confere paciente e caso. */
    static final String INCLUI = "INSERT INTO saas.consentimento"
            + "(paciente_id, finalidade, encaminhamento_id, clinica_id, texto_aceito, versao_texto, canal) "
            + "VALUES (saas.ator_paciente(), ?, ?, ?::uuid, ?, ?, 'SITE') RETURNING id";

    static final String LISTA = "SELECT json_build_object('id', c.id, 'finalidade', c.finalidade, "
            + "'versao', c.versao_texto, 'texto', c.texto_aceito, 'encaminhamentoId', c.encaminhamento_id, 'clinicaId', c.clinica_id, "
            + "'canal', c.canal, 'aceitoEm', c.aceito_em, 'revogadoEm', c.revogado_em)::text "
            + "FROM saas.consentimento c "
            + "WHERE c.paciente_id = saas.ator_paciente() AND c.encaminhamento_id = saas.ator_encaminhamento() "
            + "ORDER BY c.aceito_em, c.id";

    /** Só o consentimento ativo do paciente, no caso da sessão. */
    static final String REVOGA = "UPDATE saas.consentimento SET revogado_em = now() "
            + "WHERE id = ? AND paciente_id = saas.ator_paciente() AND encaminhamento_id = saas.ator_encaminhamento() "
            + "AND revogado_em IS NULL";

    static final String REVOGADO = "SELECT (c.revogado_em IS NOT NULL) FROM saas.consentimento c "
            + "WHERE c.id = ? AND c.paciente_id = saas.ator_paciente() "
            + "AND c.encaminhamento_id = saas.ator_encaminhamento()";

    static final String COMPARTILHAR = "COMPARTILHAR_CASO";
    static final Set<String> ENCERRADOS = Set.of("CONTRARREFERIDO", "EXPIRADO", "CANCELADO");
    static final String RECURSO = "consentimento";
    static final String CANAL = "WEB";

    private final ContextoBanco banco;
    private final AuditoriaApi auditoria;
    private final CatalogoTermos catalogo;
    private final ObjectMapper json = new ObjectMapper();

    @Autowired
    ConsentimentoServico(ContextoBanco banco, AuditoriaApi auditoria) {
        this(banco, auditoria, CatalogoTermos.doClasspath());
    }

    ConsentimentoServico(ContextoBanco banco, AuditoriaApi auditoria, CatalogoTermos catalogo) {
        this.banco = banco;
        this.auditoria = auditoria;
        this.catalogo = catalogo;
    }

    @Override
    public Optional<Termo> termoVigente(String finalidade) {
        return catalogo.vigente(finalidade);
    }

    @Override
    public Concessao conceder(ContextoAcesso contexto, String finalidade, String versao, UUID encaminhamentoId,
            UUID clinicaId, String ipOrigem) {
        Termo termo = catalogo.vigente(finalidade)
                .orElseThrow(() -> new RecusaException(Motivo.FINALIDADE_INVALIDA));
        if (versao == null || versao.isBlank()) {
            throw new RecusaException(Motivo.VERSAO_INVALIDA);
        }
        if (!termo.versao().equals(versao)) {
            // O paciente viu outro texto (ou nenhum): aceita só a versão vigente, conferida aqui.
            throw new RecusaException(Motivo.VERSAO_DESATUALIZADA);
        }
        return banco.emTransacao(contexto, consulta -> {
            exigePaciente(consulta);
            UUID caso = encaminhamentoId != null ? encaminhamentoId
                    : consulta.queryForObject(CASO_DA_SESSAO, UUID.class);
            JsonNode c = caso == null ? null
                    : consulta.queryForList(CASO, String.class, caso).stream().findFirst().map(this::le).orElse(null);
            if (c == null) {
                throw new RecusaException(Motivo.NAO_ENCONTRADO);
            }
            UUID destino = c.path("destino").isTextual() ? UUID.fromString(c.path("destino").asText()) : null;
            if (ENCERRADOS.contains(c.path("status").asText())) {
                throw new RecusaException(Motivo.CASO_ENCERRADO);
            }
            UUID clinica = clinicaId;
            if (COMPARTILHAR.equals(finalidade)) {
                if (destino == null) {
                    throw new RecusaException(Motivo.CLINICA_INVALIDA);
                }
                clinica = clinica == null ? destino : clinica;
            }
            if (clinica != null && !clinica.equals(destino)) {
                throw new RecusaException(Motivo.CLINICA_INVALIDA);
            }
            String clinicaTexto = clinica == null ? null : clinica.toString();
            Optional<UUID> existente = consulta.queryForList(EXISTENTE, UUID.class, caso, finalidade, clinicaTexto,
                    termo.versao()).stream().findFirst();
            if (existente.isPresent()) {
                return new Concessao(existente.get(), false);
            }
            UUID id;
            try {
                id = consulta.queryForObject(INCLUI, UUID.class, finalidade, caso, clinicaTexto, termo.texto(),
                        termo.versao());
            } catch (DataAccessException e) {
                // Política consentimento_paciente_concede ou chaves compostas do modelo.
                throw new RecusaException(Motivo.NAO_PERMITIDO);
            }
            auditoria.registrar(consulta::update, "CONCEDER_CONSENTIMENTO", RECURSO, id, null, ipOrigem, CANAL);
            return new Concessao(id, true);
        });
    }

    @Override
    public List<Consentimento> listar(ContextoAcesso contexto) {
        return banco.emTransacao(contexto, consulta -> {
            exigePaciente(consulta);
            return consulta.queryForList(LISTA, String.class).stream().map(this::le).map(ConsentimentoServico::linha)
                    .toList();
        });
    }

    @Override
    public void revogar(ContextoAcesso contexto, UUID consentimentoId, String ipOrigem) {
        if (consentimentoId == null) {
            throw new RecusaException(Motivo.NAO_ENCONTRADO);
        }
        banco.emTransacao(contexto, consulta -> {
            exigePaciente(consulta);
            if (consulta.update(REVOGA, consentimentoId) == 1) {
                auditoria.registrar(consulta::update, "REVOGAR_CONSENTIMENTO", RECURSO, consentimentoId, null, ipOrigem,
                        CANAL);
                return null;
            }
            Boolean revogado = consulta.queryForList(REVOGADO, Boolean.class, consentimentoId).stream().findFirst()
                    .orElse(null);
            throw new RecusaException(revogado == null ? Motivo.NAO_ENCONTRADO : Motivo.JA_REVOGADO);
        });
    }

    private static void exigePaciente(ConsultaContexto consulta) {
        if (!"PACIENTE".equals(consulta.tipoAtor())) {
            throw new RecusaException(Motivo.NAO_PERMITIDO);
        }
    }

    private JsonNode le(String texto) {
        try {
            return json.readTree(texto);
        } catch (Exception e) {
            throw new IllegalStateException("resposta do banco ilegivel");
        }
    }

    private static Consentimento linha(JsonNode n) {
        return new Consentimento(UUID.fromString(n.path("id").asText()), n.path("finalidade").asText(),
                n.path("versao").asText(), n.path("texto").asText(), uuid(n.path("encaminhamentoId")), uuid(n.path("clinicaId")),
                n.path("canal").asText(), instante(n.path("aceitoEm")), instante(n.path("revogadoEm")));
    }

    private static UUID uuid(JsonNode n) {
        return n.isTextual() ? UUID.fromString(n.asText()) : null;
    }

    private static Instant instante(JsonNode n) {
        return n.isTextual() ? OffsetDateTime.parse(n.asText()).toInstant() : null;
    }
}
