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
 * malformados: 403; parâmetros de página inválidos: 400; nenhuma resposta traz detalhe interno.
 * Paginação opcional ({@code AuditoriaApi}): {@code ?limite=N} (padrão e teto configuráveis) e
 * {@code ?depoisDe=<id>}; havendo mais eventos, o cabeçalho {@code X-Proxima-Pagina} traz o cursor.
 * Sem parâmetros, a resposta é a primeira página no formato do contrato ({@code [{"id": ...}]}).
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
            Integer limite;
            UUID depoisDe;
            try {
                String l = req.getParameter("limite");
                String d = req.getParameter("depoisDe");
                limite = l == null ? null : Integer.valueOf(l.trim());
                depoisDe = d == null ? null : UUID.fromString(d.trim());
                if (limite != null && limite < 1) {
                    return status(HttpStatus.BAD_REQUEST);
                }
            } catch (IllegalArgumentException e) {
                return status(HttpStatus.BAD_REQUEST);
            }
            // O leitor só repassa o SQL fixo da auditoria ao executor desta transação.
            AuditoriaApi.Pagina pagina = contexto.emTransacao(
                    ContextoAcesso.daEquipe(token, clinica, papel),
                    consulta -> auditoria.consultar(
                            (sql, parametros) -> consulta.queryForList(sql, UUID.class, parametros),
                            clinica, depoisDe, limite));
            List<Map<String, String>> eventos = pagina.ids().stream()
                    .map(id -> Map.of("id", id.toString()))
                    .toList();
            ResponseEntity.BodyBuilder ok = ResponseEntity.ok().cacheControl(CacheControl.noStore());
            if (pagina.proximo() != null) {
                ok.header("X-Proxima-Pagina", pagina.proximo().toString());
            }
            return ok.body(eventos);
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
