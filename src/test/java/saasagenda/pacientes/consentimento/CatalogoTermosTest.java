package saasagenda.pacientes.consentimento;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import org.junit.jupiter.api.Test;
import saasagenda.pacientes.ConsentimentoApi;

/** F9.1: a versão identifica exatamente um texto; mudar o texto cria versão nova. */
class CatalogoTermosTest {

    @Test
    void mesmoTextoMesmaVersaoTextoNovoVersaoNova() {
        ConsentimentoApi.Termo a = CatalogoTermos.termo("AGENDAMENTO", "revisao: 1\n\nTexto ficticio.");
        ConsentimentoApi.Termo b = CatalogoTermos.termo("AGENDAMENTO", "revisao: 1\r\n\r\nTexto ficticio.\r\n");
        ConsentimentoApi.Termo c = CatalogoTermos.termo("AGENDAMENTO", "revisao: 1\n\nTexto ficticio alterado.");
        ConsentimentoApi.Termo d = CatalogoTermos.termo("AGENDAMENTO", "revisao: 2\n\nTexto ficticio.");
        assertThat(a.texto()).isEqualTo("Texto ficticio.");
        assertThat(a.versao()).matches("1\\.[0-9a-f]{12}").isEqualTo(b.versao());
        // Texto mudou sem trocar a revisão: a versão muda mesmo assim.
        assertThat(c.versao()).startsWith("1.").isNotEqualTo(a.versao());
        assertThat(d.versao()).startsWith("2.").isNotEqualTo(a.versao());
    }

    @Test
    void foraDoFormatoImpedeAPartida() {
        assertThatThrownBy(() -> CatalogoTermos.termo("AGENDAMENTO", "Texto sem revisao")).isInstanceOf(IllegalStateException.class);
        assertThatThrownBy(() -> CatalogoTermos.termo("AGENDAMENTO", "revisao: 1\n\n")).isInstanceOf(IllegalStateException.class);
    }

    @Test
    void catalogoDoRepositorioCobreTodaFinalidade() {
        CatalogoTermos cat = CatalogoTermos.doClasspath();
        for (String f : ConsentimentoApi.FINALIDADES) {
            assertThat(cat.vigente(f)).as(f).isPresent();
            assertThat(cat.vigente(f).orElseThrow().texto()).as(f).isNotBlank();
        }
        assertThat(cat.vigente("MARKETING")).isEmpty();
        assertThat(cat.vigente(null)).isEmpty();
        assertThat(cat.vigente("COMPARTILHAR_CASO").orElseThrow().texto()).contains("revogar")
                .contains("livremente outro especialista");
    }
}
