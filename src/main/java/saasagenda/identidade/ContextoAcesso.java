package saasagenda.identidade;

import java.util.Objects;
import java.util.Set;
import java.util.UUID;
import java.util.regex.Pattern;

/**
 * Contexto de uma requisição (docs/arquitetura/mapa-modulos.md, identidade; ADR-0023): o token
 * opaco da sessão (cookie) e, para a equipe, a clínica e o papel escolhidos. Quem é o ator o banco
 * descobre pela tabela {@code sessao}; clínica e papel são só escolhas, conferidas por
 * {@code eh_equipe}. O token nunca aparece em {@link #toString()} (ADR-0026, item 5).
 */
public final class ContextoAcesso {

    /** Papéis de equipe aceitos como escolha de contexto ({@code usuario_clinica.papel}). */
    public static final Set<String> PAPEIS = Set.of("ADMIN", "RECEPCAO", "MEDICO");

    private static final Pattern TOKEN = Pattern.compile("[0-9a-f]{64}");

    private final String tokenSessao;
    private final UUID clinicaId;
    private final String papel;

    private ContextoAcesso(String tokenSessao, UUID clinicaId, String papel) {
        this.tokenSessao = tokenSessao;
        this.clinicaId = clinicaId;
        this.papel = papel;
    }

    /** Só a sessão (paciente, encaminhador ou consulta da própria sessão). */
    public static ContextoAcesso daSessao(String tokenSessao) {
        return new ContextoAcesso(token(tokenSessao), null, null);
    }

    /** Sessão de equipe agindo numa clínica com um papel. */
    public static ContextoAcesso daEquipe(String tokenSessao, UUID clinicaId, String papel) {
        Objects.requireNonNull(clinicaId, "clinica");
        if (papel == null || !PAPEIS.contains(papel)) {
            throw new IllegalArgumentException("papel invalido");
        }
        return new ContextoAcesso(token(tokenSessao), clinicaId, papel);
    }

    /** Formato do token devolvido por {@code novo_token()}: 64 dígitos hexadecimais minúsculos. */
    public static boolean tokenValido(String token) {
        return token != null && TOKEN.matcher(token).matches();
    }

    private static String token(String token) {
        if (!tokenValido(token)) {
            throw new IllegalArgumentException("token de sessao invalido");
        }
        return token;
    }

    public String tokenSessao() {
        return tokenSessao;
    }

    public UUID clinicaId() {
        return clinicaId;
    }

    public String papel() {
        return papel;
    }

    @Override
    public String toString() {
        return "ContextoAcesso[clinica=" + clinicaId + ", papel=" + papel + "]";
    }
}
