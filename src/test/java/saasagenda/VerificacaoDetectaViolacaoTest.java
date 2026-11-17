package saasagenda;

import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.tngtech.archunit.core.importer.ImportOption;
import org.junit.jupiter.api.Test;
import org.springframework.modulith.core.ApplicationModules;
import org.springframework.modulith.core.Violations;

/**
 * Prova que o verify() usado em {@link FronteirasModulosTest} reprova o que deve:
 * sistemas de módulos de teste em src/test/java/fixturemodulith, com controle positivo.
 */
class VerificacaoDetectaViolacaoTest {

    private static final ImportOption INCLUI_CLASSES_DE_TESTE = local -> true;

    private static ApplicationModules modulos(String pacote) {
        return ApplicationModules.of(pacote, INCLUI_CLASSES_DE_TESTE);
    }

    @Test
    void controlePositivoDependenciaDeclaradaPassa() {
        assertThatCode(() -> modulos("fixturemodulith.valido").verify()).doesNotThrowAnyException();
    }

    @Test
    void dependenciaNaoDeclaradaReprova() {
        assertThatThrownBy(() -> modulos("fixturemodulith.ilegal").verify())
                .isInstanceOf(Violations.class)
                .hasMessageContaining("fixturemodulith.ilegal.alto.Alto");
    }

    @Test
    void acessoATipoInternoReprova() {
        assertThatThrownBy(() -> modulos("fixturemodulith.interno").verify())
                .isInstanceOf(Violations.class)
                .hasMessageContaining("fixturemodulith.interno.baixo.interno.Segredo");
    }
}
