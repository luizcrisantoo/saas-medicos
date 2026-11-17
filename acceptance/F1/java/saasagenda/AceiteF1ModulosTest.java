package saasagenda;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.Arrays;
import java.util.Map;
import java.util.Set;
import java.util.stream.Collectors;

import org.junit.jupiter.api.Test;
import org.springframework.modulith.ApplicationModule;
import org.springframework.modulith.core.ApplicationModules;

/**
 * Teste de aceite F1 (Arquiteto). Injetado pelo runner numa copia do repositorio; o Executor nao o mantem.
 * Fonte: docs/arquitetura/mapa-modulos.md, secao 3 (dependencias permitidas, sem ciclos).
 */
class AceiteF1ModulosTest {

    static final Map<String, Set<String>> ESPERADO = Map.of(
        "auditoria", Set.of(),
        "identidade", Set.of("auditoria"),
        "clinicas", Set.of("identidade", "auditoria"),
        "pacientes", Set.of("identidade", "auditoria"),
        "arquivos", Set.of("identidade", "auditoria"),
        "agenda", Set.of("clinicas", "pacientes", "identidade", "auditoria"),
        "encaminhamentos", Set.of("agenda", "pacientes", "clinicas", "arquivos", "identidade", "auditoria"),
        "notificacoes", Set.of("encaminhamentos", "agenda", "pacientes", "clinicas", "identidade", "auditoria"));

    static ApplicationModules modulos() {
        return ApplicationModules.of(Aplicacao.class);
    }

    @Test
    void fronteirasVerificadas() {
        modulos().verify();
    }

    @Test
    void exatamenteOsOitoModulos() {
        Set<String> nomes = modulos().stream().map(m -> m.getName()).collect(Collectors.toSet());
        assertThat(nomes).isEqualTo(ESPERADO.keySet());
    }

    @Test
    void dependenciasDeclaradasComoNoMapa() throws Exception {
        for (var e : ESPERADO.entrySet()) {
            Class<?> pi = Class.forName("saasagenda." + e.getKey() + ".package-info");
            ApplicationModule am = pi.getAnnotation(ApplicationModule.class);
            assertThat(am).as("@ApplicationModule em saasagenda.%s.package-info", e.getKey()).isNotNull();
            Set<String> declaradas = Arrays.stream(am.allowedDependencies())
                .map(s -> s.split("::")[0].trim()).filter(s -> !s.isEmpty()).collect(Collectors.toSet());
            assertThat(declaradas).as("allowedDependencies de %s", e.getKey()).isEqualTo(e.getValue());
            assertThat(am.type()).as("modulo %s nao pode ser OPEN", e.getKey()).isNotEqualTo(ApplicationModule.Type.OPEN);
        }
    }
}
