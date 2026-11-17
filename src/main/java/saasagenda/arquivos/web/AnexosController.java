package saasagenda.arquivos.web;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import jakarta.servlet.http.Cookie;
import jakarta.servlet.http.HttpServletRequest;
import java.util.Base64;
import java.util.HexFormat;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.UUID;
import java.util.regex.Pattern;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.context.annotation.Profile;
import org.springframework.http.CacheControl;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;
import saasagenda.arquivos.ArquivosApi;
import saasagenda.identidade.ContextoAcesso;
import saasagenda.identidade.ContextoBanco;

/**
 * Rotas de anexo (spec da Fase 2, seção 3.4; F8). Cookie {@code SESSAO}; a equipe escolhe clínica e
 * papel em {@code X-Clinica-Id} e {@code X-Papel} (os dois ou nenhum). Sem sessão válida: 401;
 * cabeçalhos malformados: 403; tipo inválido: 415; tamanho, hash ou corpo inválidos: 400; caso ou
 * anexo que o ator não vê: 404; ator que vê mas não pode anexar: 403; anexo PENDENTE ou INFECTADO:
 * 409; storage não configurado: 503. Nenhuma resposta de erro traz detalhe interno, e nenhum log
 * leva URL, chave de objeto, cookie ou corpo (ADR-0026, itens 3 e 5).
 */
@RestController
@Profile("web")
class AnexosController {

    private static final Logger LOG = LoggerFactory.getLogger(AnexosController.class);
    private static final Pattern HEX_SHA256 = Pattern.compile("[0-9a-fA-F]{64}");
    private static final Pattern B64_SHA256 = Pattern.compile("[A-Za-z0-9+/]{43}=");
    private static final int CORPO_MAXIMO = 4096;

    private final ArquivosApi arquivos;
    private final ObjectMapper json;

    AnexosController(ArquivosApi arquivos, ObjectMapper json) {
        this.arquivos = arquivos;
        this.json = json;
    }

    @PostMapping("/api/encaminhamentos/{id}/anexos")
    ResponseEntity<Map<String, Object>> upload(@PathVariable("id") String id, HttpServletRequest req,
            @RequestBody(required = false) String corpo) {
        String token = cookie(req);
        if (!ContextoAcesso.tokenValido(token)) {
            return status(HttpStatus.UNAUTHORIZED);
        }
        ContextoAcesso contexto = contexto(req, token);
        if (contexto == null) {
            return status(HttpStatus.FORBIDDEN);
        }
        UUID encaminhamento = uuid(id);
        if (encaminhamento == null) {
            return status(HttpStatus.NOT_FOUND);
        }
        Pedido pedido = pedido(corpo);
        if (pedido == null) {
            return status(HttpStatus.BAD_REQUEST);
        }
        ArquivosApi.UploadAutorizado u = arquivos.autorizarUpload(contexto, encaminhamento, pedido.tipoMime(),
                pedido.tamanho(), pedido.sha256());
        Map<String, Object> r = new LinkedHashMap<>();
        r.put("anexoId", u.anexoId().toString());
        r.put("url", u.url());
        r.put("cabecalhos", u.cabecalhos());
        r.put("expiraEm", u.expiraEm().toString());
        return ResponseEntity.status(HttpStatus.CREATED).cacheControl(CacheControl.noStore())
                .header("Referrer-Policy", "no-referrer").body(r);
    }

    @GetMapping("/api/anexos/{id}/download")
    ResponseEntity<Map<String, Object>> download(@PathVariable("id") String id, HttpServletRequest req) {
        String token = cookie(req);
        if (!ContextoAcesso.tokenValido(token)) {
            return status(HttpStatus.UNAUTHORIZED);
        }
        ContextoAcesso contexto = contexto(req, token);
        if (contexto == null) {
            return status(HttpStatus.FORBIDDEN);
        }
        UUID anexo = uuid(id);
        if (anexo == null) {
            return status(HttpStatus.NOT_FOUND);
        }
        ArquivosApi.DownloadAutorizado d = arquivos.urlDownload(contexto, anexo, req.getRemoteAddr());
        Map<String, Object> r = new LinkedHashMap<>();
        r.put("url", d.url());
        r.put("expiraEm", d.expiraEm().toString());
        return ResponseEntity.ok().cacheControl(CacheControl.noStore())
                .header("Referrer-Policy", "no-referrer").body(r);
    }

    @ExceptionHandler(ArquivosApi.RecusaException.class)
    ResponseEntity<Map<String, Object>> recusa(ArquivosApi.RecusaException e) {
        LOG.info("pedido de anexo recusado: {}", e.motivo());
        return status(switch (e.motivo()) {
            case TIPO_INVALIDO -> HttpStatus.UNSUPPORTED_MEDIA_TYPE;
            case TAMANHO_INVALIDO, HASH_INVALIDO -> HttpStatus.BAD_REQUEST;
            case NAO_ENCONTRADO -> HttpStatus.NOT_FOUND;
            case NAO_PERMITIDO -> HttpStatus.FORBIDDEN;
            case NAO_LIMPO -> HttpStatus.CONFLICT;
            case INDISPONIVEL -> HttpStatus.SERVICE_UNAVAILABLE;
        });
    }

    @ExceptionHandler(ContextoBanco.SemSessaoException.class)
    ResponseEntity<Map<String, Object>> semSessao(ContextoBanco.SemSessaoException e) {
        return status(HttpStatus.UNAUTHORIZED);
    }

    @ExceptionHandler(Exception.class)
    ResponseEntity<Map<String, Object>> falha(Exception e) {
        // Só a classe: a mensagem pode trazer SQL, chave ou URL.
        LOG.warn("falha no pedido de anexo: {}", e.getClass().getSimpleName());
        return status(HttpStatus.INTERNAL_SERVER_ERROR);
    }

    /** Corpo {@code {"tipoMime","tamanhoBytes","sha256"}}; tipo e tamanho conferidos no serviço. */
    private Pedido pedido(String corpo) {
        if (corpo == null || corpo.isBlank() || corpo.length() > CORPO_MAXIMO) {
            return null;
        }
        JsonNode n;
        try {
            n = json.readTree(corpo);
        } catch (Exception e) {
            return null;
        }
        if (n == null || !n.isObject()) {
            return null;
        }
        JsonNode tipo = n.get("tipoMime");
        JsonNode tamanho = n.get("tamanhoBytes");
        JsonNode hash = n.get("sha256");
        if (tipo == null || !tipo.isTextual()) {
            throw new ArquivosApi.RecusaException(ArquivosApi.Motivo.TIPO_INVALIDO);
        }
        if (tamanho == null || !tamanho.isIntegralNumber() || !tamanho.canConvertToLong()) {
            throw new ArquivosApi.RecusaException(ArquivosApi.Motivo.TAMANHO_INVALIDO);
        }
        byte[] sha = sha256(hash);
        if (sha == null) {
            throw new ArquivosApi.RecusaException(ArquivosApi.Motivo.HASH_INVALIDO);
        }
        return new Pedido(tipo.textValue(), tamanho.longValue(), sha);
    }

    /** SHA-256 em hexadecimal (64 dígitos) ou Base64 (44 caracteres). */
    private static byte[] sha256(JsonNode hash) {
        if (hash == null || !hash.isTextual()) {
            return null;
        }
        String h = hash.textValue();
        if (HEX_SHA256.matcher(h).matches()) {
            return HexFormat.of().parseHex(h);
        }
        if (B64_SHA256.matcher(h).matches()) {
            return Base64.getDecoder().decode(h);
        }
        return null;
    }

    /** Só a sessão, ou sessão de equipe com clínica e papel; meio-termo ou malformado: nulo. */
    private static ContextoAcesso contexto(HttpServletRequest req, String token) {
        String clinica = req.getHeader("X-Clinica-Id");
        String papel = req.getHeader("X-Papel");
        if (clinica == null && papel == null) {
            return ContextoAcesso.daSessao(token);
        }
        UUID c = uuid(clinica);
        if (c == null || papel == null || !ContextoAcesso.PAPEIS.contains(papel)) {
            return null;
        }
        return ContextoAcesso.daEquipe(token, c, papel);
    }

    private static UUID uuid(String s) {
        if (s == null) {
            return null;
        }
        try {
            UUID u = UUID.fromString(s.trim());
            return u.toString().equalsIgnoreCase(s.trim()) ? u : null;
        } catch (IllegalArgumentException e) {
            return null;
        }
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

    private record Pedido(String tipoMime, long tamanho, byte[] sha256) {
        @Override
        public String toString() {
            return "Pedido[" + tipoMime + "]";
        }
    }
}
