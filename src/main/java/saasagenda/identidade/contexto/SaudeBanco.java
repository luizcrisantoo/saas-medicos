package saasagenda.identidade.contexto;

import java.sql.Connection;
import javax.sql.DataSource;
import org.springframework.boot.actuate.health.Health;
import org.springframework.boot.actuate.health.HealthIndicator;
import org.springframework.context.annotation.Profile;
import org.springframework.stereotype.Component;

/**
 * Saúde do pool {@code saas_app} sem SQL de aplicação: só {@code Connection.isValid}, que o
 * {@link PoolAppGuardado} aceita sem contexto (o indicador padrão do Spring lê metadados, que o
 * pool recusa). Nenhum detalhe sai na resposta ({@code show-details=never}).
 */
@Component("banco")
@Profile("web")
class SaudeBanco implements HealthIndicator {

    private final DataSource dataSource;

    SaudeBanco(DataSource dataSource) {
        this.dataSource = dataSource;
    }

    @Override
    public Health health() {
        try (Connection c = dataSource.getConnection()) {
            return c.isValid(2) ? Health.up().build() : Health.down().build();
        } catch (Exception e) {
            return Health.down().build();
        }
    }
}
