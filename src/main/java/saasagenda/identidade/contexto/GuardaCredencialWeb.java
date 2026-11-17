package saasagenda.identidade.contexto;

import java.util.Set;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.InitializingBean;
import org.springframework.context.annotation.Profile;
import org.springframework.core.env.Environment;
import org.springframework.stereotype.Component;

/**
 * E-09 no processo web: o pool padrão é {@code saas_app}, nunca a credencial de jobs, de login ou
 * de dono. As variáveis {@code SAAS_DB_JOBS_*} nunca são lidas aqui; se estiverem no ambiente, só
 * um aviso sem valor é registrado (a credencial de jobs não deveria chegar a este processo).
 */
@Component
@Profile("web")
class GuardaCredencialWeb implements InitializingBean {

    private static final Logger LOG = LoggerFactory.getLogger(GuardaCredencialWeb.class);
    private static final Set<String> PROIBIDOS = Set.of("saas_jobs", "saas_auth", "saas_owner",
            "saas_funcoes", "saas_migracao");

    private final Environment ambiente;

    GuardaCredencialWeb(Environment ambiente) {
        this.ambiente = ambiente;
    }

    @Override
    public void afterPropertiesSet() {
        String usuario = ambiente.getProperty("spring.datasource.username", "").trim();
        if (PROIBIDOS.contains(usuario)) {
            throw new IllegalStateException("credencial do processo web invalida");
        }
        if (System.getenv().keySet().stream().anyMatch(k -> k.startsWith("SAAS_DB_JOBS_"))) {
            LOG.warn("credencial de jobs presente no ambiente do processo web: ignorada (E-09)");
        }
    }
}
