package saasagenda.identidade.sessao;

import java.time.Duration;
import java.util.Arrays;
import java.util.Set;
import java.util.stream.Collectors;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.web.client.RestTemplateBuilder;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Profile;
import org.springframework.security.oauth2.jose.jws.SignatureAlgorithm;
import org.springframework.security.oauth2.jwt.JwtDecoder;
import org.springframework.security.oauth2.jwt.NimbusJwtDecoder;

/**
 * Resource server do Cognito (ADR-0006, ADR-0007): as chaves vêm só de {@code SAAS_AUTH_JWKS_URI}
 * (nada de descoberta OIDC na partida) e só RS256 é aceito. As claims são conferidas por
 * {@link ValidadorAccessToken}.
 */
@Configuration(proxyBeanMethods = false)
@Profile("web")
class ConfiguracaoAutenticacao {

    @Bean
    JwtDecoder decodificadorAccessToken(
            @Value("${saas.auth.issuer}") String issuer,
            @Value("${saas.auth.jwks-uri}") String jwksUri,
            @Value("${saas.auth.client-ids}") String clientIds,
            RestTemplateBuilder rest) {
        Set<String> clientes = Arrays.stream(clientIds.split(","))
                .map(String::trim)
                .filter(c -> !c.isEmpty())
                .collect(Collectors.toUnmodifiableSet());
        if (issuer.isBlank() || clientes.isEmpty()) {
            throw new IllegalStateException("configuracao de autenticacao incompleta");
        }
        NimbusJwtDecoder decodificador = NimbusJwtDecoder.withJwkSetUri(jwksUri)
                .jwsAlgorithm(SignatureAlgorithm.RS256)
                .restOperations(rest
                        .connectTimeout(Duration.ofSeconds(3))
                        .readTimeout(Duration.ofSeconds(3))
                        .build())
                .build();
        decodificador.setJwtValidator(new ValidadorAccessToken(issuer, clientes, Duration.ofSeconds(30)));
        return decodificador;
    }
}
