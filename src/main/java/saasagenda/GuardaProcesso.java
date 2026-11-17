package saasagenda;

import java.util.Arrays;
import java.util.Set;
import org.springframework.beans.factory.InitializingBean;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.env.Environment;

/**
 * Separação dos processos (E-09; spec da Fase 2, seção 3.3): {@code SAAS_PROCESSO} escolhe
 * exatamente um perfil, {@code web} ou {@code jobs}. Valor desconhecido, os dois juntos ou
 * nenhum derrubam a partida, para que nenhum processo carregue as duas credenciais.
 */
@Configuration(proxyBeanMethods = false)
class GuardaProcesso implements InitializingBean {

    static final Set<String> PROCESSOS = Set.of("web", "jobs");

    private final Environment ambiente;

    GuardaProcesso(Environment ambiente) {
        this.ambiente = ambiente;
    }

    @Override
    public void afterPropertiesSet() {
        long ativos = Arrays.stream(ambiente.getActiveProfiles()).filter(PROCESSOS::contains).count();
        if (ativos != 1) {
            throw new IllegalStateException("SAAS_PROCESSO deve ser exatamente um de " + PROCESSOS);
        }
    }
}
