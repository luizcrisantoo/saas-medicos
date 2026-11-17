package saasagenda.identidade.contexto;

import org.springframework.beans.factory.InitializingBean;
import org.springframework.context.annotation.Profile;
import org.springframework.core.env.Environment;
import org.springframework.stereotype.Component;
import saasagenda.identidade.credencial.CredencialBanco;

/**
 * E-09 no processo web: o pool padrão é exatamente {@code saas_app} (lista positiva única de
 * {@link CredencialBanco}, a mesma que o pool {@code saas_auth} e o processo de jobs usam). A
 * credencial de jobs nunca é lida neste processo, nem para avisar; nada de nome ou valor de
 * variável de ambiente vai para log ou mensagem.
 */
@Component
@Profile("web")
class GuardaCredencialWeb implements InitializingBean {

    private final Environment ambiente;

    GuardaCredencialWeb(Environment ambiente) {
        this.ambiente = ambiente;
    }

    @Override
    public void afterPropertiesSet() {
        CredencialBanco.exige(CredencialBanco.Uso.APP, ambiente.getProperty("spring.datasource.username"));
    }
}
