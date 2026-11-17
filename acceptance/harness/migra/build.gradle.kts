// Harness de aceite: aplica as migracoes do Executor com Flyway real (nao e codigo do produto).
plugins { application; java }
repositories { mavenCentral() }
java { toolchain { languageVersion.set(JavaLanguageVersion.of(21)) } }
dependencies {
    implementation("org.flywaydb:flyway-core:10.20.1")
    implementation("org.flywaydb:flyway-database-postgresql:10.20.1")
    implementation("org.postgresql:postgresql:42.7.4")
    implementation("org.slf4j:slf4j-simple:2.0.16")
}
application { mainClass.set("aceite.Migra") }
