package saasagenda.identidade.contexto;

import com.zaxxer.hikari.HikariDataSource;
import org.springframework.beans.factory.config.BeanPostProcessor;
import org.springframework.context.annotation.Profile;
import org.springframework.stereotype.Component;

/**
 * Troca o pool Hikari padrão do Spring Boot ({@code spring.datasource.*}, já com
 * {@code spring.datasource.hikari.*} ligado) pelo {@link PoolAppGuardado} antes que qualquer bean o
 * receba: o gerenciador de transações, o {@code JdbcTemplate} automático e o
 * {@link ContextoBancoJdbc} só enxergam o pool fechado por padrão. Outro tipo de pool derruba a
 * partida (falha fechada).
 */
@Component
@Profile("web")
class GuardaPoolApp implements BeanPostProcessor {

    @Override
    public Object postProcessAfterInitialization(Object bean, String nome) {
        if (!"dataSource".equals(nome)) {
            return bean;
        }
        if (bean instanceof HikariDataSource hikari) {
            return new PoolAppGuardado(hikari);
        }
        throw new IllegalStateException("pool saas_app precisa ser o Hikari padrao");
    }
}
