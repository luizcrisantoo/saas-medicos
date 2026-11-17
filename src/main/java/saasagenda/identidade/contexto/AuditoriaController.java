package saasagenda.identidade.contexto;

import jakarta.servlet.http.Cookie;
import jakarta.servlet.http.HttpServletRequest;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.context.annotation.Profile;
import org.springframework.http.CacheControl;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;
import saasagenda.auditoria.AuditoriaApi;
import saasagenda.identidade.ContextoAcesso;
import saasagenda.identidade.ContextoBanco;

/**
 * {@code GET /api/auditoria} (spec da Fase 2, seção 3.4; ADR-0009): cookie de equipe, clínica em
 * {@code X-Clinica-Id} e papel em {@code X-Papel}. O banco decide pelo contexto aplicado na
 * transação: só o ADMIN vinculado à clínica vê eventos. Sem sessão válida: 401; cabeçalhos
 * malformados: 403; nenhuma resposta traz detalhe interno.
 */
@RestController
@Profile("web")
class AuditoriaController {

    private static final Logger LOG = LoggerFactory.getLogger(AuditoriaController.class);

    private final ContextoBanco contexto;
    private final AuditoriaApi auditoria;

    AuditoriaController(ContextoBanco contexto, AuditoriaApi auditoria) {
        this.contexto = contexto;
        this.auditoria = auditoria;
    }

    @GetMapping("/api/auditoria")
    ResponseEntity<List<Map<String, String>>> consulta(HttpServletRequest req) {
        String token = cookie(req);
        if (!ContextoAcesso.tokenValido(token)) {
            return status(HttpStatus.UNAUTHORIZED);
        }
        UUID clinica;
        String papel = req.getHeader("X-Papel");
        try {
            clinica = UUID.fromString(String.valueOf(req.getHeader("X-Clinica-Id")).trim());
        } catch (IllegalArgumentException e) {
            return status(HttpStatus.FORBIDDEN);
        }
        if (papel == null || !ContextoAcesso.PAPEIS.contains(papel)) {
            return status(HttpStatus.FORBIDDEN);
        }
        try {
            List<Map<String, String>> eventos = contexto.emTransacao(
                    ContextoAcesso.daEquipe(token, clinica, papel),
                    () -> auditoria.consultar(clinica).stream()
                            .map(id -> Map.of("id", id.toString()))
                            .toList());
            return ResponseEntity.ok().cacheControl(CacheControl.noStore()).body(eventos);
        } catch (ContextoBanco.SemSessaoException e) {
            return status(HttpStatus.UNAUTHORIZED);
        }
    }

    @ExceptionHandler(Exception.class)
    ResponseEntity<List<Map<String, String>>> falha(Exception e) {
        LOG.warn("falha na consulta de auditoria: {}", e.getClass().getSimpleName());
        return status(HttpStatus.FORBIDDEN);
    }

    private static ResponseEntity<List<Map<String, String>>> status(HttpStatus s) {
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
