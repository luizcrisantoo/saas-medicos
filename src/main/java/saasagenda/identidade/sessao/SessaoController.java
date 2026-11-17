package saasagenda.identidade.sessao;

import jakarta.servlet.http.Cookie;
import jakarta.servlet.http.HttpServletRequest;
import java.time.Duration;
import java.util.Map;
import java.util.Optional;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.CacheControl;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseCookie;
import org.springframework.http.ResponseEntity;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.jwt.JwtDecoder;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import saasagenda.identidade.SessaoApi;

/**
 * Sessão de equipe (spec da Fase 2, seção 3.4). O access token do Cognito só serve para abrir a
 * sessão; daí em diante vale o cookie {@code SESSAO} com o token opaco da tabela {@code sessao}
 * (nunca o JWT). Toda recusa é 401 sem corpo de detalhe. Os logs nunca levam token, cookie ou sub.
 */
@RestController
@RequestMapping("/api/sessao")
class SessaoController {

    static final String COOKIE = "SESSAO";
    private static final int MAX_TOKEN = 8192;
    private static final Logger LOG = LoggerFactory.getLogger(SessaoController.class);

    private final JwtDecoder decodificador;
    private final SessaoApi sessoes;

    SessaoController(JwtDecoder decodificador, SessaoApi sessoes) {
        this.decodificador = decodificador;
        this.sessoes = sessoes;
    }

    @PostMapping("/equipe")
    ResponseEntity<Void> abreEquipe(HttpServletRequest req) {
        Optional<String> bearer = bearer(req.getHeader(HttpHeaders.AUTHORIZATION));
        if (bearer.isEmpty()) {
            return recusa();
        }
        Jwt jwt;
        try {
            jwt = decodificador.decode(bearer.get());
        } catch (RuntimeException e) {
            LOG.info("abertura de sessao de equipe recusada: token invalido");
            return recusa();
        }
        Optional<String> sessao = sessoes.abrirEquipe(jwt.getSubject());
        if (sessao.isEmpty()) {
            LOG.info("abertura de sessao de equipe recusada: usuario nao permitido");
            return recusa();
        }
        ResponseCookie cookie = ResponseCookie.from(COOKIE, sessao.get())
                .httpOnly(true)
                .secure(true)
                .sameSite("Strict")
                .path("/")
                .maxAge(Duration.ofHours(12))
                .build();
        return ResponseEntity.noContent()
                .cacheControl(CacheControl.noStore())
                .header(HttpHeaders.SET_COOKIE, cookie.toString())
                .build();
    }

    @GetMapping
    ResponseEntity<Map<String, String>> consulta(HttpServletRequest req) {
        Optional<String> tipo = cookie(req).flatMap(sessoes::tipo);
        if (tipo.isEmpty()) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED).cacheControl(CacheControl.noStore()).build();
        }
        return ResponseEntity.ok().cacheControl(CacheControl.noStore()).body(Map.of("tipo", tipo.get()));
    }

    @DeleteMapping
    ResponseEntity<Void> encerra(HttpServletRequest req) {
        cookie(req).ifPresent(sessoes::encerrar);
        ResponseCookie apaga = ResponseCookie.from(COOKIE, "")
                .httpOnly(true)
                .secure(true)
                .sameSite("Strict")
                .path("/")
                .maxAge(0)
                .build();
        return ResponseEntity.noContent()
                .cacheControl(CacheControl.noStore())
                .header(HttpHeaders.SET_COOKIE, apaga.toString())
                .build();
    }

    /** Qualquer falha inesperada (banco, formato) vira 401 sem detalhe interno (ADR-0026, item 3). */
    @ExceptionHandler(Exception.class)
    ResponseEntity<Void> falha(Exception e) {
        LOG.warn("falha na sessao: {}", e.getClass().getSimpleName());
        return recusa();
    }

    private static ResponseEntity<Void> recusa() {
        return ResponseEntity.status(HttpStatus.UNAUTHORIZED).cacheControl(CacheControl.noStore()).build();
    }

    private static Optional<String> bearer(String autorizacao) {
        if (autorizacao == null || autorizacao.length() > MAX_TOKEN + 7) {
            return Optional.empty();
        }
        if (!autorizacao.regionMatches(true, 0, "Bearer ", 0, 7)) {
            return Optional.empty();
        }
        String token = autorizacao.substring(7).trim();
        return token.isEmpty() ? Optional.empty() : Optional.of(token);
    }

    private static Optional<String> cookie(HttpServletRequest req) {
        Cookie[] cookies = req.getCookies();
        if (cookies == null) {
            return Optional.empty();
        }
        for (Cookie c : cookies) {
            if (COOKIE.equals(c.getName())) {
                return Optional.ofNullable(c.getValue()).filter(SessaoBanco::formatoValido);
            }
        }
        return Optional.empty();
    }
}
