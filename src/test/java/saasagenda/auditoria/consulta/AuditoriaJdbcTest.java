package saasagenda.auditoria.consulta;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.util.ArrayList;
import java.util.List;
import java.util.UUID;
import java.util.stream.IntStream;
import org.junit.jupiter.api.Test;
import saasagenda.auditoria.AuditoriaApi;

/** Paginação da auditoria: limite configurável com teto, cursor e valores só como parâmetros. */
class AuditoriaJdbcTest {

    private final List<Object[]> chamadas = new ArrayList<>();
    private final List<String> textos = new ArrayList<>();

    private AuditoriaApi.LeitorIds leitor(int disponiveis) {
        return (sql, parametros) -> {
            textos.add(sql);
            chamadas.add(parametros);
            int limite = (Integer) parametros[parametros.length - 1];
            return IntStream.range(0, Math.min(limite, disponiveis)).mapToObj(i -> UUID.randomUUID()).toList();
        };
    }

    @Test
    void limitePadraoTetoECursor() {
        AuditoriaJdbc a = new AuditoriaJdbc(100, 500);
        UUID clinica = UUID.randomUUID();
        AuditoriaApi.Pagina p = a.consultar(leitor(1000), clinica, null, null);
        assertThat(p.ids()).hasSize(100);
        assertThat(p.proximo()).isEqualTo(p.ids().get(99));
        assertThat(chamadas.get(0)).containsExactly(clinica, 101);
        assertThat(a.consultar(leitor(1000), clinica, null, 100000).ids()).hasSize(500);
        assertThat(chamadas.get(1)).containsExactly(clinica, 501);
        UUID cursor = UUID.randomUUID();
        AuditoriaApi.Pagina ultima = a.consultar(leitor(3), clinica, cursor, 10);
        assertThat(ultima.ids()).hasSize(3);
        assertThat(ultima.proximo()).isNull();
        assertThat(chamadas.get(2)).containsExactly(clinica, cursor, clinica, 11);
        // Texto fixo: nenhum valor no SQL.
        assertThat(textos).containsOnly(AuditoriaJdbc.PRIMEIRA, AuditoriaJdbc.SEGUINTE);
        for (String t : textos) {
            assertThat(t).doesNotContain(clinica.toString()).doesNotContain(cursor.toString()).doesNotContain("500");
        }
        assertThatThrownBy(() -> a.consultar(leitor(1), clinica, null, 0)).isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(() -> a.consultar(leitor(1), null, null, 1)).isInstanceOf(IllegalArgumentException.class);
    }

    @Test
    void configuracaoForaDosLimitesNaoSobe() {
        assertThatThrownBy(() -> new AuditoriaJdbc(0, 500)).isInstanceOf(IllegalStateException.class);
        assertThatThrownBy(() -> new AuditoriaJdbc(600, 500)).isInstanceOf(IllegalStateException.class);
        assertThatThrownBy(() -> new AuditoriaJdbc(10, AuditoriaApi.TETO_ABSOLUTO + 1)).isInstanceOf(IllegalStateException.class);
        assertThat(new AuditoriaJdbc(1, AuditoriaApi.TETO_ABSOLUTO)).isNotNull();
    }

    @Test
    void registrarGravaUmEventoComAtorDaSessaoOuFalha() {
        AuditoriaJdbc a = new AuditoriaJdbc(100, 500);
        UUID anexo = UUID.randomUUID();
        UUID clinica = UUID.randomUUID();
        List<Object[]> gravados = new ArrayList<>();
        a.registrar((sql, p) -> {
            textos.add(sql);
            gravados.add(p);
            return 1;
        }, "DOWNLOAD_ANEXO", "anexo_encaminhamento", anexo, clinica, "127.0.0.1", "WEB");
        assertThat(textos).containsExactly(AuditoriaJdbc.REGISTRA);
        assertThat(gravados.get(0)).containsExactly(clinica, "DOWNLOAD_ANEXO", "anexo_encaminhamento", anexo, "127.0.0.1", "WEB");
        // O ator nunca vem do chamador: papel e id saem da sessao no banco.
        assertThat(AuditoriaJdbc.REGISTRA).contains("saas.papel_efetivo(), saas.ator_id_efetivo()")
                .doesNotContain(anexo.toString());
        assertThatThrownBy(() -> a.registrar((sql, p) -> 0, "X", "y", anexo, null, null, "WEB"))
                .isInstanceOf(AuditoriaApi.AuditoriaNaoGravadaException.class);
        assertThatThrownBy(() -> a.registrar((sql, p) -> 1, "", "y", anexo, null, null, "WEB"))
                .isInstanceOf(IllegalArgumentException.class);
    }
}
