package saasagenda.pacientes.web;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import jakarta.servlet.http.Cookie;
import jakarta.servlet.http.HttpServletRequest;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.context.annotation.Profile;
import org.springframework.http.CacheControl;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;
import saasagenda.identidade.ContextoAcesso;
import saasagenda.identidade.ContextoBanco;
import saasagenda.pacientes.ConsentimentoApi;

/**
 * Rotas de consentimento (spec da Fase 2, seção 3.4; F9).
 * <ul>
 * <li>{@code GET /api/termos/consentimento/{finalidade}}: público; texto e versão vigentes.</li>
 * <li>{@code POST /api/consentimentos}: sessão de paciente; o corpo só escolhe
 * {@code finalidade}, {@code versao}, {@code encaminhamentoId} e {@code clinicaId}. Qualquer outro
 * campo (paciente, texto, canal, data, ator) é ignorado: tudo isso sai do servidor.</li>
 * <li>{@code GET /api/consentimentos}: consentimentos do caso da sessão.</li>
 * <li>{@code DELETE /api/consentimentos/{id}}: revoga; de novo, 409 sem mudar nada.</li>
 * </ul>
 * Sem sessão válida: 401; sessão que não é de paciente: 403; corpo, finalidade ou versão
 * malformados: 400; versão que não é a vigente ou caso encerrado: 409; caso ou consentimento que o
 * ator não vê: 404; clínica que não é a destino do caso: 422. O erro traz só o código da recusa,
 * sem exceção, SQL ou nome de objeto do banco (ADR-0026, item 3); nenhum log leva cookie ou corpo.
 */
@RestController
@Profile("web")
class ConsentimentoController {

    private static final Logger LOG = LoggerFactory.getLogger(ConsentimentoController.class);
    private static final int CORPO_MAXIMO = 4096;

    private final ConsentimentoApi consentimentos;
    private final ObjectMapper json;

    ConsentimentoController(ConsentimentoApi consentimentos, ObjectMapper json) {
        this.consentimentos = consentimentos;
        this.json = json;
    }

    @GetMapping("/api/termos/consentimento/{finalidade}")
    ResponseEntity<Map<String, Object>> termo(@PathVariable("finalidade") String finalidade) {
        return consentimentos.termoVigente(finalidade).map(t -> {
            Map<String, Object> r = new LinkedHashMap<>();
            r.put("finalidade", t.finalidade());
            r.put("versao", t.versao());
            r.put("texto", t.texto());
            return ResponseEntity.ok().cacheControl(CacheControl.noCache()).body(r);
        }).orElseGet(() -> erro(HttpStatus.NOT_FOUND, ConsentimentoApi.Motivo.FINALIDADE_INVALIDA));
    }

    @PostMapping("/api/consentimentos")
    ResponseEntity<Map<String, Object>> conceder(HttpServletRequest req, @RequestBody(required = false) String corpo) {
        String token = cookie(req);
        if (!ContextoAcesso.tokenValido(token)) {
            return status(HttpStatus.UNAUTHORIZED);
        }
        JsonNode n = corpo(corpo);
        if (n == null) {
            return erro(HttpStatus.BAD_REQUEST, null);
        }
        String finalidade = texto(n, "finalidade");
        if (finalidade == null || !ConsentimentoApi.FINALIDADES.contains(finalidade)) {
            return erro(HttpStatus.BAD_REQUEST, ConsentimentoApi.Motivo.FINALIDADE_INVALIDA);
        }
        String versao = texto(n, "versao");
        if (versao == null) {
            return erro(HttpStatus.BAD_REQUEST, ConsentimentoApi.Motivo.VERSAO_INVALIDA);
        }
        UUID caso = uuidOpcional(n, "encaminhamentoId");
        UUID clinica = uuidOpcional(n, "clinicaId");
        if (caso == INVALIDO || clinica == INVALIDO) {
            return erro(HttpStatus.BAD_REQUEST, null);
        }
        ConsentimentoApi.Concessao c = consentimentos.conceder(ContextoAcesso.daSessao(token), finalidade, versao,
                caso, clinica, req.getRemoteAddr());
        Map<String, Object> r = new LinkedHashMap<>();
        r.put("id", c.id().toString());
        r.put("finalidade", finalidade);
        r.put("versao", versao);
        return ResponseEntity.status(c.novo() ? HttpStatus.CREATED : HttpStatus.OK).cacheControl(CacheControl.noStore())
                .body(r);
    }

    @GetMapping("/api/consentimentos")
    ResponseEntity<List<Map<String, Object>>> listar(HttpServletRequest req) {
        String token = cookie(req);
        if (!ContextoAcesso.tokenValido(token)) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED).cacheControl(CacheControl.noStore()).build();
        }
        List<Map<String, Object>> lista = consentimentos.listar(ContextoAcesso.daSessao(token)).stream().map(c -> {
            Map<String, Object> m = new LinkedHashMap<>();
            m.put("id", c.id().toString());
            m.put("finalidade", c.finalidade());
            m.put("versao", c.versao());
            m.put("texto", c.texto());
            m.put("encaminhamentoId", c.encaminhamentoId() == null ? null : c.encaminhamentoId().toString());
            m.put("clinicaId", c.clinicaId() == null ? null : c.clinicaId().toString());
            m.put("canal", c.canal());
            m.put("aceitoEm", c.aceitoEm() == null ? null : c.aceitoEm().toString());
            m.put("revogadoEm", c.revogadoEm() == null ? null : c.revogadoEm().toString());
            m.put("ativo", c.ativo());
            return m;
        }).toList();
        return ResponseEntity.ok().cacheControl(CacheControl.noStore()).body(lista);
    }

    @DeleteMapping("/api/consentimentos/{id}")
    ResponseEntity<Map<String, Object>> revogar(@PathVariable("id") String id, HttpServletRequest req) {
        String token = cookie(req);
        if (!ContextoAcesso.tokenValido(token)) {
            return status(HttpStatus.UNAUTHORIZED);
        }
        UUID consentimento = uuid(id);
        if (consentimento == null) {
            return erro(HttpStatus.NOT_FOUND, ConsentimentoApi.Motivo.NAO_ENCONTRADO);
        }
        consentimentos.revogar(ContextoAcesso.daSessao(token), consentimento, req.getRemoteAddr());
        return status(HttpStatus.NO_CONTENT);
    }

    @ExceptionHandler(ConsentimentoApi.RecusaException.class)
    ResponseEntity<Map<String, Object>> recusa(ConsentimentoApi.RecusaException e) {
        LOG.info("pedido de consentimento recusado: {}", e.motivo());
        return erro(switch (e.motivo()) {
            case FINALIDADE_INVALIDA, VERSAO_INVALIDA -> HttpStatus.BAD_REQUEST;
            case VERSAO_DESATUALIZADA, CASO_ENCERRADO, JA_REVOGADO -> HttpStatus.CONFLICT;
            case NAO_ENCONTRADO -> HttpStatus.NOT_FOUND;
            case CLINICA_INVALIDA -> HttpStatus.UNPROCESSABLE_ENTITY;
            case NAO_PERMITIDO -> HttpStatus.FORBIDDEN;
        }, e.motivo());
    }

    @ExceptionHandler(ContextoBanco.SemSessaoException.class)
    ResponseEntity<Map<String, Object>> semSessao(ContextoBanco.SemSessaoException e) {
        return status(HttpStatus.UNAUTHORIZED);
    }

    @ExceptionHandler(Exception.class)
    ResponseEntity<Map<String, Object>> falha(Exception e) {
        // Só a classe: a mensagem pode trazer SQL ou nome de objeto do banco.
        LOG.warn("falha no pedido de consentimento: {}", e.getClass().getSimpleName());
        return status(HttpStatus.INTERNAL_SERVER_ERROR);
    }

    private static final UUID INVALIDO = new UUID(0, 0);

    private JsonNode corpo(String corpo) {
        if (corpo == null || corpo.isBlank() || corpo.length() > CORPO_MAXIMO) {
            return null;
        }
        try {
            JsonNode n = json.readTree(corpo);
            return n != null && n.isObject() ? n : null;
        } catch (Exception e) {
            return null;
        }
    }

    private static String texto(JsonNode n, String campo) {
        JsonNode v = n.get(campo);
        return v != null && v.isTextual() && !v.textValue().isBlank() ? v.textValue() : null;
    }

    /** Ausente ou nulo: nulo; presente e malformado: {@link #INVALIDO}. */
    private static UUID uuidOpcional(JsonNode n, String campo) {
        JsonNode v = n.get(campo);
        if (v == null || v.isNull()) {
            return null;
        }
        UUID u = v.isTextual() ? uuid(v.textValue()) : null;
        return u == null ? INVALIDO : u;
    }

    private static UUID uuid(String s) {
        if (s == null) {
            return null;
        }
        try {
            UUID u = UUID.fromString(s.trim());
            return u.toString().equalsIgnoreCase(s.trim()) && !u.equals(INVALIDO) ? u : null;
        } catch (IllegalArgumentException e) {
            return null;
        }
    }

    private static ResponseEntity<Map<String, Object>> erro(HttpStatus s, ConsentimentoApi.Motivo motivo) {
        Map<String, Object> r = new LinkedHashMap<>();
        r.put("erro", motivo == null ? "PEDIDO_INVALIDO" : motivo.name());
        return ResponseEntity.status(s).cacheControl(CacheControl.noStore()).body(r);
    }

    private static ResponseEntity<Map<String, Object>> status(HttpStatus s) {
        return ResponseEntity.status(s).cacheControl(CacheControl.noStore()).build();
    }

    private static String cookie(HttpServletRequest req) {
        Cookie[] cookies = req.getCookies();
        if (cookies != null) {
            for (Cookie c : cookies) {
                if ("SESSAO".equals(c.getName())) {
                    return c.getValue();
                }
            }
        }
        return null;
    }
}
