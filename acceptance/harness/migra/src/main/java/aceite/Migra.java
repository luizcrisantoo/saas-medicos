package aceite;

import org.flywaydb.core.Flyway;
import org.flywaydb.core.api.output.MigrateResult;

/**
 * Uso: migra <jdbcUrl> <usuario> <senha> <diretorioMigracoes> [alvo|info|validate]
 * Historico do Flyway no schema "migracao" (criado pelo bootstrap), nunca em "saas".
 * Sem initSql: cada migracao assume o papel dono com SET ROLE e termina com RESET ROLE.
 */
public final class Migra {
    public static void main(String[] a) {
        if (a.length < 4) { System.err.println("uso: migra url usuario senha dir [alvo|info|validate]"); System.exit(2); }
        var cfg = Flyway.configure()
            .dataSource(a[0], a[1], a[2])
            .locations("filesystem:" + a[3])
            .schemas("migracao").defaultSchema("migracao").createSchemas(false)
            .validateMigrationNaming(true)
            .cleanDisabled(true);
        String modo = a.length > 4 ? a[4] : "latest";
        if (!modo.equals("info") && !modo.equals("validate") && !modo.equals("latest")) cfg = cfg.target(modo);
        Flyway f = cfg.load();
        switch (modo) {
            case "info" -> { for (var m : f.info().applied()) System.out.println("APLICADA " + m.getVersion() + " " + m.getDescription()); }
            case "validate" -> { f.validate(); System.out.println("VALIDATE_OK"); }
            default -> {
                MigrateResult r = f.migrate();
                System.out.println("MIGRATE_OK aplicadas=" + r.migrationsExecuted + " versao=" + r.targetSchemaVersion);
            }
        }
    }
}
