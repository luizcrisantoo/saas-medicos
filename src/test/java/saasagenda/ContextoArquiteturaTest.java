package saasagenda;

import static org.assertj.core.api.Assertions.assertThat;

import java.io.IOException;
import java.lang.reflect.Field;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.TreeMap;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import java.util.stream.Stream;
import org.junit.jupiter.api.Test;
import saasagenda.identidade.FuncaoJobs;

/**
 * Teste de arquitetura do ADR-0026, item 7 (Red Team I-20) e da separação de credenciais (E-09),
 * sobre o código-fonte de produção:
 * <ul>
 * <li>todo {@code set_config} do código é {@code set_config('app.<nome>', ?, true)}: parâmetro
 * ligado e local à transação. Literal, concatenação, {@code String.format}, {@code false} ou
 * qualquer outro valor no lugar do {@code ?} reprovam;</li>
 * <li>nenhum {@code SET [LOCAL|SESSION] app.*} e nenhum {@code RESET}/{@code SET ROLE} em SQL;</li>
 * <li>só o {@code ContextoBancoJdbc} grava contexto, e grava os três valores;</li>
 * <li>só o pacote de jobs lê a credencial de jobs, e ele só chama funções {@code jobs_*}.</li>
 * </ul>
 * O teste dinâmico correspondente (log do PostgreSQL com {@code log_statement=all} e
 * {@code pg_stat_statements}) está em {@link ContextoPoolTest}.
 */
class ContextoArquiteturaTest {

    private static final Path FONTES = Path.of("src/main/java");
    private static final Pattern SET_CONFIG = Pattern.compile("(?i)set_config");
    private static final Pattern SET_CONFIG_SEGURO =
            Pattern.compile("set_config\\('app\\.(sessao|clinica_id|papel)', \\?, true\\)");
    private static final Pattern SET_DE_GUC = Pattern.compile(
            "(?i)\\b(SET|RESET)\\s+(LOCAL\\s+|SESSION\\s+)?(\"?app\"?\\.|ROLE\\b|SESSION\\s+AUTHORIZATION\\b|ALL\\b)");
    private static final String GRAVADOR = "saasagenda/identidade/contexto/ContextoBancoJdbc.java";

    @Test
    void todoSetConfigEhParametrizadoELocal() throws IOException {
        Map<String, List<String>> defeitos = new TreeMap<>();
        Map<String, Integer> usos = new TreeMap<>();
        for (Map.Entry<String, String> f : fontes().entrySet()) {
            Matcher m = SET_CONFIG.matcher(f.getValue());
            while (m.find()) {
                usos.merge(f.getKey(), 1, Integer::sum);
                Matcher seguro = SET_CONFIG_SEGURO.matcher(f.getValue());
                seguro.region(m.start(), f.getValue().length());
                if (!seguro.lookingAt()) {
                    defeitos.computeIfAbsent(f.getKey(), k -> new ArrayList<>()).add(trecho(f.getValue(), m.start()));
                }
            }
        }
        assertThat(defeitos).as("set_config sem parametro ligado ou nao local (ADR-0026, item 7)").isEmpty();
        assertThat(usos).as("so o ContextoBancoJdbc grava contexto, com os tres valores").isEqualTo(Map.of(GRAVADOR, 3));
    }

    @Test
    void nenhumSetDeGucNemRoleEmSql() throws IOException {
        Map<String, String> defeitos = new TreeMap<>();
        for (Map.Entry<String, String> f : fontes().entrySet()) {
            Matcher m = SET_DE_GUC.matcher(f.getValue());
            if (m.find()) {
                defeitos.put(f.getKey(), trecho(f.getValue(), m.start()));
            }
        }
        assertThat(defeitos).as("SET/RESET de GUC ou de papel em SQL").isEmpty();
    }

    @Test
    void sqlDoContextoNaoTemValorNoTexto() throws Exception {
        Class<?> c = Class.forName("saasagenda.identidade.contexto.ContextoBancoJdbc");
        Field aplica = c.getDeclaredField("APLICA");
        aplica.setAccessible(true);
        String sql = (String) aplica.get(null);
        assertThat(sql).isEqualTo("SELECT set_config('app.sessao', ?, true), "
                + "set_config('app.clinica_id', ?, true), set_config('app.papel', ?, true)");
        assertThat(sql.chars().filter(ch -> ch == '?').count()).isEqualTo(3);
        // Os três valores vão pela lista de parâmetros da chamada, nunca pelo texto.
        String fonte = fontes().get(GRAVADOR);
        assertThat(fonte).containsPattern("queryForList\\(APLICA,\\s*contexto\\.tokenSessao\\(\\),");
        assertThat(fonte).doesNotContainPattern("APLICA\\s*\\+|\\+\\s*APLICA|APLICA\\.(formatted|replace)|format\\(APLICA");
    }

    @Test
    void controleNegativoOVerificadorRecusaInterpolacao() {
        // Prova que as expressões acima reprovam as formas conhecidas de interpolação (N4c).
        for (String ruim : List.of(
                "\"SELECT set_config('app.sessao', '\" + token + \"', true)\"",
                "\"SELECT set_config('app.sessao', '%s', true)\".formatted(token)",
                "\"SELECT set_config('app.sessao', ?, false)\"",
                "\"select SET_CONFIG('app.sessao', ?, true)\"",
                "\"SELECT set_config('app.sessao',\" + \"?, true)\"")) {
            Matcher m = SET_CONFIG.matcher(ruim);
            assertThat(m.find()).isTrue();
            Matcher seguro = SET_CONFIG_SEGURO.matcher(ruim);
            seguro.region(m.start(), ruim.length());
            assertThat(seguro.lookingAt()).as(ruim).isFalse();
        }
        for (String ruim : List.of("SET LOCAL app.sessao = 'x'", "set app.papel TO 'ADMIN'",
                "SET SESSION \"app\".sessao = 'x'", "RESET app.sessao", "SET ROLE saas_jobs")) {
            assertThat(SET_DE_GUC.matcher(ruim).find()).as(ruim).isTrue();
        }
        assertThat(SET_CONFIG_SEGURO.matcher("set_config('app.sessao', ?, true)").matches()).isTrue();
    }

    @Test
    void credencialDeJobsSoNoPacoteDeJobsESoFuncoesJobs() throws IOException {
        Map<String, String> fontes = fontes();
        List<String> leem = fontes.entrySet().stream()
                .filter(e -> e.getValue().contains("saas.db.jobs") || e.getValue().contains("SAAS_DB_JOBS"))
                .map(Map.Entry::getKey)
                .toList();
        // A guarda web só olha se o prefixo existe no ambiente, para avisar; nunca lê o valor.
        assertThat(leem).containsExactlyInAnyOrder("saasagenda/identidade/jobs/JobsBanco.java",
                "saasagenda/identidade/contexto/GuardaCredencialWeb.java");
        assertThat(fontes.get("saasagenda/identidade/contexto/GuardaCredencialWeb.java"))
                .doesNotContain("saas.db.jobs").doesNotContain("getenv(\"SAAS_DB_JOBS");
        assertThat(fontes.get("saasagenda/identidade/jobs/JobsBanco.java"))
                .contains("@Profile(\"jobs\")")
                .doesNotContainIgnoringCase("prepareStatement(\"")
                .contains("prepareStatement(funcao.sql())");
        for (FuncaoJobs f : FuncaoJobs.values()) {
            assertThat(f.sql()).as(f.name()).matches("SELECT (\\* FROM )?saas\\.jobs_[a-z_]+\\((\\?(::uuid)?(, )?)*\\)");
            assertThat(f.sql().chars().filter(ch -> ch == '?').count()).as(f.name()).isEqualTo(f.parametros());
        }
        assertThat(FuncaoJobs.values()).hasSize(8);
    }

    @Test
    void beansDeBancoTemPerfilDeProcesso() throws IOException {
        // Todo componente que abre pool ou usa JdbcTemplate pertence a um único processo.
        List<String> semPerfil = new ArrayList<>();
        for (Map.Entry<String, String> f : fontes().entrySet()) {
            String s = f.getValue();
            boolean usaBanco = s.contains("JdbcTemplate") || s.contains("HikariDataSource") || s.contains("JwtDecoder")
                    || s.contains("@RestController");
            boolean componente = s.contains("@Component") || s.contains("@Configuration") || s.contains("@RestController");
            if (usaBanco && componente && !s.contains("@Profile(\"web\")") && !s.contains("@Profile(\"jobs\")")) {
                semPerfil.add(f.getKey());
            }
        }
        assertThat(semPerfil).isEmpty();
    }

    private static Map<String, String> fontes() throws IOException {
        Map<String, String> m = new TreeMap<>();
        try (Stream<Path> s = Files.walk(FONTES)) {
            for (Path p : s.filter(p -> p.toString().endsWith(".java")).toList()) {
                m.put(FONTES.relativize(p).toString().replace('\\', '/'),
                        semComentarios(Files.readString(p, StandardCharsets.UTF_8)));
            }
        }
        assertThat(m).isNotEmpty();
        return m;
    }

    /**
     * Troca comentários por espaço e preserva literais (texto, bloco de texto e caractere), para que
     * documentação que cita {@code set_config} não conte e SQL dentro de string sempre conte.
     */
    static String semComentarios(String fonte) {
        StringBuilder out = new StringBuilder(fonte.length());
        int i = 0;
        int n = fonte.length();
        while (i < n) {
            char c = fonte.charAt(i);
            if (fonte.startsWith("\"\"\"", i)) {
                int fim = fonte.indexOf("\"\"\"", i + 3);
                fim = fim < 0 ? n : fim + 3;
                out.append(fonte, i, fim);
                i = fim;
            } else if (c == '"' || c == '\'') {
                int j = i + 1;
                while (j < n && fonte.charAt(j) != c && fonte.charAt(j) != '\n') {
                    j += fonte.charAt(j) == '\\' ? 2 : 1;
                }
                j = Math.min(n, j + 1);
                out.append(fonte, i, j);
                i = j;
            } else if (fonte.startsWith("//", i)) {
                int fim = fonte.indexOf('\n', i);
                i = fim < 0 ? n : fim;
                out.append(' ');
            } else if (fonte.startsWith("/*", i)) {
                int fim = fonte.indexOf("*/", i + 2);
                String comentario = fonte.substring(i, fim < 0 ? n : fim + 2);
                out.append(comentario.replaceAll("[^\n]", " "));
                i = fim < 0 ? n : fim + 2;
            } else {
                out.append(c);
                i++;
            }
        }
        return out.toString();
    }

    @Test
    void lexicoPreservaStringsEDescartaComentarios() {
        String f = "/* set_config('x', 'y', false) */ String a = \"set_config('app.sessao', '\" + t + \"', true)\"; "
                + "// SET app.sessao = 'x'\n char q = '\"'; String b = \"/* nao e comentario */\";";
        String r = semComentarios(f);
        assertThat(r).contains("\"set_config('app.sessao', '\" + t").contains("\"/* nao e comentario */\"")
                .doesNotContain("false").doesNotContain("SET app");
    }

    private static String trecho(String texto, int inicio) {
        return texto.substring(inicio, Math.min(texto.length(), inicio + 60)).replace('\n', ' ');
    }
}
