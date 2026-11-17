package saasagenda.identidade.credencial;

import java.util.Locale;

/**
 * Regra única de credencial de banco por uso (E-09, ADR-0024; spec da Fase 2, seção 3.3): lista
 * positiva, um papel de login exato por pool. Qualquer outro usuário (inclusive vazio, dono,
 * superusuário ou o papel de outro processo) derruba a partida. A mensagem não traz nome nem valor
 * de variável de ambiente, só o uso.
 */
public final class CredencialBanco {

    /** Os três pools da aplicação e o único papel que cada um aceita. */
    public enum Uso {
        /** Pool padrão do processo web. */
        APP("saas_app"),
        /** Pool de abertura de sessão do processo web. */
        AUTH("saas_auth"),
        /** Pool do processo de jobs. */
        JOBS("saas_jobs");

        private final String papel;

        Uso(String papel) {
            this.papel = papel;
        }

        public String papel() {
            return papel;
        }
    }

    private CredencialBanco() {
    }

    /** Devolve o usuário se for exatamente o papel do uso; senão recusa sem expor o valor. */
    public static String exige(Uso uso, String usuario) {
        if (usuario == null || !uso.papel().equals(usuario)) {
            throw new IllegalStateException("credencial de banco invalida para o uso "
                    + uso.name().toLowerCase(Locale.ROOT));
        }
        return usuario;
    }
}
