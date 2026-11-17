package saasagenda;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.Map;
import java.util.Set;
import java.util.TreeMap;
import java.util.TreeSet;
import java.util.stream.Collectors;

import org.junit.jupiter.api.Test;
import org.springframework.modulith.ApplicationModule;
import org.springframework.modulith.core.ApplicationModules;

/**
 * Fronteiras de módulo (ADR-0001; briefing, "Teste das fronteiras de módulo pelo Spring Modulith").
 * A tabela abaixo é a seção 3 de docs/arquitetura/mapa-modulos.md.
 */
class FronteirasModulosTest {

    static final Map<String, Set<String>> MAPA = Map.of(
            "auditoria", Set.of(),
            "identidade", Set.of("auditoria"),
            "clinicas", Set.of("identidade", "auditoria"),
            "pacientes", Set.of("identidade", "auditoria"),
            "arquivos", Set.of("identidade", "auditoria"),
            "agenda", Set.of("clinicas", "pacientes", "identidade", "auditoria"),
            "encaminhamentos", Set.of("agenda", "pacientes", "clinicas", "arquivos", "identidade", "auditoria"),
            "notificacoes", Set.of("encaminhamentos", "agenda", "pacientes", "clinicas", "identidade", "auditoria"));

    static final ApplicationModules MODULOS = ApplicationModules.of(Aplicacao.class);

    @Test
    void fronteirasRespeitadas() {
        MODULOS.verify();
    }

    @Test
    void existemExatamenteOsOitoModulos() {
        Set<String> pacotes = MODULOS.stream()
                .map(m -> m.getBasePackage().getName())
                .collect(Collectors.toCollection(TreeSet::new));
        Set<String> esperados = MAPA.keySet().stream()
                .map(n -> "saasagenda." + n)
                .collect(Collectors.toCollection(TreeSet::new));
        assertThat(pacotes).isEqualTo(esperados);
    }

    @Test
    void dependenciasDeclaradasIguaisAoMapaENenhumModuloAberto() throws Exception {
        Map<String, Set<String>> declaradas = new TreeMap<>();
        for (String modulo : MAPA.keySet()) {
            ApplicationModule anotacao = Class.forName("saasagenda." + modulo + ".package-info")
                    .getAnnotation(ApplicationModule.class);
            assertThat(anotacao).as("@ApplicationModule em %s", modulo).isNotNull();
            assertThat(anotacao.type()).as("tipo de %s", modulo).isEqualTo(ApplicationModule.Type.CLOSED);
            assertThat(anotacao.allowedDependencies())
                    .as("allowedDependencies de %s sem repetição", modulo)
                    .doesNotHaveDuplicates();
            declaradas.put(modulo, Set.of(anotacao.allowedDependencies()));
        }
        assertThat(declaradas).isEqualTo(new TreeMap<>(MAPA));
    }

    @Test
    void grafoDoMapaSemCiclo() {
        // Cada módulo só depende de módulos já visitados numa ordem topológica.
        Set<String> visitados = new TreeSet<>();
        Map<String, Set<String>> pendentes = new TreeMap<>(MAPA);
        while (!pendentes.isEmpty()) {
            String livre = pendentes.entrySet().stream()
                    .filter(e -> visitados.containsAll(e.getValue()))
                    .map(Map.Entry::getKey)
                    .findFirst()
                    .orElseThrow(() -> new AssertionError("ciclo entre " + pendentes.keySet()));
            visitados.add(livre);
            pendentes.remove(livre);
        }
    }
}
