package saasagenda;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import org.junit.jupiter.api.Test;
import saasagenda.identidade.credencial.CredencialBanco;
import saasagenda.identidade.credencial.CredencialBanco.Uso;

/** Regra única de credencial (E-09): lista positiva, e a mensagem não expõe o valor recebido. */
class CredencialBancoTest {

    @Test
    void soOPapelExatoDeCadaUso() {
        assertThat(CredencialBanco.exige(Uso.APP, "saas_app")).isEqualTo("saas_app");
        assertThat(CredencialBanco.exige(Uso.AUTH, "saas_auth")).isEqualTo("saas_auth");
        assertThat(CredencialBanco.exige(Uso.JOBS, "saas_jobs")).isEqualTo("saas_jobs");
        for (Uso uso : Uso.values()) {
            for (String ruim : new String[] {null, "", " ", "postgres", "saas_owner", "saas_funcoes", "saas_migracao",
                    "qualquer_outro", uso.papel() + " ", uso.papel().toUpperCase()}) {
                assertThatThrownBy(() -> CredencialBanco.exige(uso, ruim)).as(uso + ":" + ruim)
                        .isInstanceOf(IllegalStateException.class)
                        .satisfies(e -> {
                            if (ruim != null && !ruim.isBlank()) {
                                assertThat(e.getMessage()).doesNotContain(ruim.trim());
                            }
                        });
            }
            for (Uso outro : Uso.values()) {
                if (outro != uso) {
                    assertThatThrownBy(() -> CredencialBanco.exige(uso, outro.papel())).isInstanceOf(IllegalStateException.class);
                }
            }
        }
    }
}
