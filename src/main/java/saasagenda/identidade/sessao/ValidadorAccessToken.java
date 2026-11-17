package saasagenda.identidade.sessao;

import java.time.Duration;
import java.util.List;
import java.util.Set;
import org.springframework.security.oauth2.core.OAuth2Error;
import org.springframework.security.oauth2.core.OAuth2TokenValidator;
import org.springframework.security.oauth2.core.OAuth2TokenValidatorResult;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.jwt.JwtTimestampValidator;

/**
 * Claims do access token do Cognito (Red Team E-10): {@code kid} e {@code alg=RS256} no cabeçalho,
 * {@code iss} exatamente igual ao configurado, {@code client_id} na lista (e {@code aud}, se vier,
 * também na lista), {@code token_use=access}, {@code exp} obrigatório e {@code exp}/{@code nbf}
 * com tolerância pequena, {@code sub} presente. A assinatura RS256 pela JWKS é conferida antes,
 * pelo decodificador. MFA obrigatório é F11 (bloqueada): não é conferido aqui.
 */
final class ValidadorAccessToken implements OAuth2TokenValidator<Jwt> {

    private static final OAuth2TokenValidatorResult RECUSA =
            OAuth2TokenValidatorResult.failure(new OAuth2Error("invalid_token"));

    private final String issuer;
    private final Set<String> clientes;
    private final JwtTimestampValidator tempo;

    ValidadorAccessToken(String issuer, Set<String> clientes, Duration tolerancia) {
        this.issuer = issuer;
        this.clientes = Set.copyOf(clientes);
        this.tempo = new JwtTimestampValidator(tolerancia);
    }

    @Override
    public OAuth2TokenValidatorResult validate(Jwt jwt) {
        return aceita(jwt) && !tempo.validate(jwt).hasErrors()
                ? OAuth2TokenValidatorResult.success()
                : RECUSA;
    }

    private boolean aceita(Jwt jwt) {
        Object alg = jwt.getHeaders().get("alg");
        Object kid = jwt.getHeaders().get("kid");
        if (!"RS256".equals(String.valueOf(alg)) || !(kid instanceof String k) || k.isBlank()) {
            return false;
        }
        Object iss = jwt.getClaims().get("iss");
        if (iss == null || !issuer.equals(iss.toString())) {
            return false;
        }
        if (!"access".equals(jwt.getClaims().get("token_use"))) {
            return false;
        }
        if (!(jwt.getClaims().get("client_id") instanceof String cliente) || !clientes.contains(cliente)) {
            return false;
        }
        List<String> aud = jwt.getAudience();
        if (aud != null && !aud.isEmpty() && !aud.stream().allMatch(clientes::contains)) {
            return false;
        }
        if (jwt.getExpiresAt() == null) {
            return false;
        }
        String sub = jwt.getSubject();
        return sub != null && !sub.isBlank() && sub.length() <= 256;
    }
}
