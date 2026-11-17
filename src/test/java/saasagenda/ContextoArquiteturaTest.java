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
 * <li>só o pacote de jobs lê a credencial de jobs, e ele só chama funções {@code jobs_*};</li>
 * <li>todo SQL que chega ao JDBC/JdbcTemplate (ou aos executores do projeto) é texto fixo: literal
 * ou constante só de literais; concatenação com variável, {@code String.format}/{@code formatted},
 * {@code StringBuilder}, bloco de texto montado e repasse não declarado reprovam, e o mesmo vale
 * para os {@code .sql} do repositório (migrações, reversões e bootstrap);</li>
 * <li>só o {@code ContextoBancoJdbc} concede permissão de SQL no pool {@code saas_app};</li>
 * <li>credencial de banco por lista positiva única, sem ler nem citar variável de ambiente.</li>
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
        assertThat(fonte).containsPattern("jdbc\\.queryForList\\(APLICA,\\s*contexto\\.tokenSessao\\(\\),");
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
        assertThat(leem).containsExactly("saasagenda/identidade/jobs/JobsBanco.java");
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
    void regraUnicaDeCredencialPorListaPositivaSemLerAmbiente() throws IOException {
        Map<String, String> fontes = fontes();
        assertThat(fontes.get("saasagenda/identidade/contexto/GuardaCredencialWeb.java"))
                .contains("CredencialBanco.exige(CredencialBanco.Uso.APP,");
        assertThat(fontes.get("saasagenda/identidade/sessao/SessaoBanco.java"))
                .contains("CredencialBanco.exige(CredencialBanco.Uso.AUTH,");
        assertThat(fontes.get("saasagenda/identidade/jobs/JobsBanco.java"))
                .contains("CredencialBanco.exige(CredencialBanco.Uso.JOBS,");
        Map<String, String> defeitos = new TreeMap<>();
        Pattern listaNegra = Pattern.compile("(?s)(Set|List)\\.of\\([^)]*\"saas_(app|auth|jobs|owner|funcoes|migracao)\"");
        Pattern ambiente = Pattern.compile("System\\.getenv|SAAS_[A-Z_]+");
        for (Map.Entry<String, String> f : fontes.entrySet()) {
            if (listaNegra.matcher(f.getValue()).find()) {
                defeitos.put(f.getKey(), "lista negra de papeis");
            }
            Matcher m = ambiente.matcher(f.getValue());
            if (m.find()) {
                defeitos.put(f.getKey(), "nome de variavel de ambiente no codigo: " + m.group());
            }
        }
        assertThat(defeitos).isEmpty();
    }

    @Test
    void soOContextoBancoConcedePermissaoDeSqlNoPool() throws IOException {
        Map<String, Integer> usos = new TreeMap<>();
        for (Map.Entry<String, String> f : fontes().entrySet()) {
            Matcher m = Pattern.compile("comPermissao\\(").matcher(f.getValue());
            while (m.find()) {
                usos.merge(f.getKey(), 1, Integer::sum);
            }
        }
        // Declaração no pool guardado; checagem, aplicação e o executor no ContextoBancoJdbc.
        assertThat(usos).isEqualTo(Map.of("saasagenda/identidade/contexto/PoolAppGuardado.java", 1, GRAVADOR, 3));
    }

    // ------------------------------------------------------------- I-20: SQL sem valor no texto

    /** Métodos JDBC e JdbcTemplate (e os executores do projeto) cujo 1º argumento é SQL. */
    static final Pattern CHAMADA_SQL = Pattern.compile("\\.(prepareStatement|prepareCall|nativeSQL|executeQuery|"
            + "executeUpdate|executeLargeUpdate|execute|addBatch|query|queryForList|queryForObject|queryForMap|"
            + "queryForRowSet|queryForStream|queryForInt|queryForLong|update|batchUpdate|ids)\\s*\\(");

    /** Texto que parece SQL dentro de um literal. */
    static final Pattern PALAVRA_SQL = Pattern.compile(
            "(?i)\\b(select|insert|update|delete|set_config|from|where|values|returning|limit|execute|call)\\b");

    /** Montagem de texto proibida em arquivo que fala com o banco. */
    static final Pattern MONTAGEM = Pattern.compile(
            "\\bStringBuilder\\b|\\bStringBuffer\\b|String\\.format\\s*\\(|\\.formatted\\s*\\(|MessageFormat|"
            + "String\\.join\\s*\\(|\\.concat\\s*\\(|StringTemplate|\\bSTR\\.");

    static final Pattern FALA_COM_BANCO = Pattern.compile(
            "java\\.sql\\.|JdbcTemplate|ConsultaContexto|LeitorIds|DataSource|FuncaoJobs");

    /**
     * Pontos de repasse: o SQL chega por parâmetro e segue para o JDBC. Cada um é conferido aqui
     * pelo nome do parâmetro e pela contagem; a origem do texto passa pela regra de chamada.
     */
    static final Map<String, Map<String, Integer>> REPASSES = Map.of(
            GRAVADOR, Map.of("sql", 2),
            "saasagenda/identidade/contexto/AuditoriaController.java", Map.of("sql", 1));

    @Test
    void todoSqlDoCodigoEhTextoFixoComParametroLigado() throws IOException {
        Map<String, String> fontes = fontes();
        Map<String, List<String>> defeitos = verificaJava(fontes);
        assertThat(defeitos).as("SQL montado com valor (I-20; ADR-0026, item 7)").isEmpty();
        // Os repasses existem exatamente como declarados (nada novo passa por eles sem revisão).
        for (Map.Entry<String, Map<String, Integer>> r : REPASSES.entrySet()) {
            assertThat(repasses(fontes.get(r.getKey()))).as(r.getKey()).isEqualTo(r.getValue());
        }
    }

    @Test
    void controleNegativoVerificadorDeSqlPegaTodaFormaDeMontagem() {
        String c = "class X { static final String OK = \"SELECT 1 FROM t WHERE a = ?\"; ";
        List<String> mutantes = List.of(
                // concatenação direta na chamada
                "void a(){ jdbc.queryForList(\"SELECT id FROM t WHERE c = '\" + clinicaId + \"'\", UUID.class); }",
                // variável local montada antes
                "void a(){ String sql = \"SELECT id FROM t WHERE c = \" + c; jdbc.query(sql, m); }",
                // String.format
                "void a(){ jdbc.queryForObject(String.format(\"SELECT %s\", t), String.class); }",
                // formatted em literal comum
                "void a(){ c.prepareStatement(\"SELECT * FROM t WHERE c = '%s'\".formatted(v)); }",
                // text block com formatted
                "void a(){ jdbc.update(\"\"\"\n UPDATE t SET a = '%s'\n\"\"\".formatted(v)); }",
                // text block concatenado
                "void a(){ jdbc.execute(\"\"\"\n DELETE FROM t WHERE id = \"\"\" + id); }",
                // StringBuilder
                "void a(){ StringBuilder sb = new StringBuilder(\"SELECT \"); sb.append(col); jdbc.query(sb.toString(), m); }",
                // constante que não é só literal
                "static final String RUIM = \"SELECT \" + COLUNA; void a(){ s.executeQuery(RUIM); }",
                // concat
                "void a(){ s.execute(\"SELECT \".concat(v)); }",
                // repasse não declarado
                "void a(String q){ jdbc.queryForList(q, UUID.class); }",
                // literal com valor do lado esquerdo
                "void a(){ c.prepareCall(v + \" FROM t\"); }",
                // leitor da auditoria com SQL montado
                "void a(){ leitor.ids(\"SELECT id FROM t LIMIT \" + n); }");
        for (String m : mutantes) {
            Map<String, String> f = Map.of("saasagenda/Mutante.java", ContextoArquiteturaTest.semComentarios(c + m + " }"));
            assertThat(verificaJava(f)).as(m).isNotEmpty();
        }
        // Controle positivo: as formas permitidas passam.
        Map<String, String> bom = Map.of("saasagenda/Bom.java", c
                + "static final String DOIS = \"SELECT a \" + \"FROM t WHERE b = ? LIMIT ?\"; "
                + "static final String BLOCO = \"\"\"\n SELECT a FROM t WHERE b = ?\n\"\"\"; "
                + "void a(){ jdbc.queryForList(OK, UUID.class, clinicaId); s.executeQuery(\"SELECT 1\"); "
                + "jdbc.query(DOIS, m, a, b); jdbc.queryForObject(BLOCO, String.class, x); "
                + "transacao.execute(st -> { return null; }); ps.executeQuery(); } }");
        assertThat(verificaJava(bom)).isEmpty();
    }

    static Map<String, List<String>> verificaJava(Map<String, String> fontes) {
        Map<String, List<String>> defeitos = new TreeMap<>();
        Map<String, String> constantes = new TreeMap<>();
        Pattern decl = Pattern.compile("static\\s+final\\s+String\\s+([A-Z][A-Z0-9_]*)\\s*=");
        for (Map.Entry<String, String> f : fontes.entrySet()) {
            Matcher d = decl.matcher(f.getValue());
            while (d.find()) {
                String expr = ate(f.getValue(), d.end(), ';');
                constantes.put(f.getKey() + "#" + d.group(1), expr);
                if (literalSql(expr) && !soLiterais(expr)) {
                    defeitos.computeIfAbsent(f.getKey(), k -> new ArrayList<>()).add("constante montada: " + d.group(1));
                }
            }
        }
        for (Map.Entry<String, String> f : fontes.entrySet()) {
            String src = f.getValue();
            List<String> lista = new ArrayList<>();
            Map<String, Integer> repasseDeclarado = REPASSES.getOrDefault(f.getKey(), Map.of());
            Matcher m = CHAMADA_SQL.matcher(src);
            while (m.find()) {
                if (dentroDeLiteral(src, m.start())) {
                    continue;
                }
                String arg = primeiroArgumento(src, m.end()).strip();
                if (arg.isEmpty() || arg.matches("(?s)^(\\w+|\\([^)]*\\))\\s*->.*") || arg.matches("^[\\w.]+::\\w+$")
                        || soLiterais(arg) || repasseDeclarado.containsKey(arg)
                        || ("funcao.sql()".equals(arg) && f.getKey().endsWith("identidade/jobs/JobsBanco.java"))) {
                    continue;
                }
                if (arg.matches("^([A-Z]\\w*\\.)?[A-Z][A-Z0-9_]*$")) {
                    String nome = arg.contains(".") ? arg.substring(arg.indexOf('.') + 1) : arg;
                    String expr = constantes.get(f.getKey() + "#" + nome);
                    if (expr == null) {
                        expr = constantes.entrySet().stream().filter(e -> e.getKey().endsWith("#" + nome))
                                .map(Map.Entry::getValue).findFirst().orElse(null);
                    }
                    if (expr != null && soLiterais(expr)) {
                        continue;
                    }
                }
                lista.add(m.group(1) + "(" + trecho(arg, 0));
            }
            // Literal com cara de SQL só pode encostar em outro literal.
            for (int[] l : literais(src)) {
                String texto = src.substring(l[0], l[1]);
                if (!PALAVRA_SQL.matcher(texto).find()) {
                    continue;
                }
                String depois = src.substring(l[1]).stripLeading();
                String antes = src.substring(0, l[0]).stripTrailing();
                boolean ruim = depois.startsWith(".")
                        || (depois.startsWith("+") && !comecaComLiteral(depois.substring(1).stripLeading()))
                        || (antes.endsWith("+") && !antes.substring(0, antes.length() - 1).stripTrailing().endsWith("\""))
                        || antes.matches("(?s).*\\b(format|append|insert|join|concat)\\s*\\($");
                if (ruim) {
                    lista.add("literal SQL montado: " + trecho(texto, 0));
                }
            }
            if (FALA_COM_BANCO.matcher(src).find()) {
                Matcher mo = MONTAGEM.matcher(src);
                while (mo.find()) {
                    if (!dentroDeLiteral(src, mo.start())) {
                        lista.add("montagem de texto em codigo de banco: " + mo.group());
                    }
                }
            }
            if (!lista.isEmpty()) {
                defeitos.put(f.getKey(), lista);
            }
        }
        return defeitos;
    }

    private static Map<String, Integer> repasses(String src) {
        Map<String, Integer> r = new TreeMap<>();
        Matcher m = CHAMADA_SQL.matcher(src);
        while (m.find()) {
            String arg = primeiroArgumento(src, m.end()).strip();
            if ("sql".equals(arg)) {
                r.merge(arg, 1, Integer::sum);
            }
        }
        return r;
    }

    private static boolean literalSql(String expr) {
        for (int[] l : literais(expr)) {
            if (PALAVRA_SQL.matcher(expr.substring(l[0], l[1])).find()) {
                return true;
            }
        }
        return false;
    }

    /** Só literais (texto ou bloco de texto) unidos por {@code +}. */
    static boolean soLiterais(String expr) {
        StringBuilder resto = new StringBuilder();
        int i = 0;
        for (int[] l : literais(expr)) {
            resto.append(expr, i, l[0]).append('L');
            i = l[1];
        }
        resto.append(expr.substring(i));
        return resto.toString().replaceAll("\\s+", "").matches("L(\\+L)*");
    }

    private static boolean comecaComLiteral(String s) {
        return s.startsWith("\"");
    }

    /** Intervalos [início, fim) dos literais de texto e blocos de texto (fonte já sem comentários). */
    static List<int[]> literais(String src) {
        List<int[]> r = new ArrayList<>();
        int i = 0;
        int n = src.length();
        while (i < n) {
            char c = src.charAt(i);
            if (src.startsWith("\"\"\"", i)) {
                int fim = src.indexOf("\"\"\"", i + 3);
                fim = fim < 0 ? n : fim + 3;
                r.add(new int[] {i, fim});
                i = fim;
            } else if (c == '"' || c == '\'') {
                int j = i + 1;
                while (j < n && src.charAt(j) != c && src.charAt(j) != '\n') {
                    j += src.charAt(j) == '\\' ? 2 : 1;
                }
                j = Math.min(n, j + 1);
                if (c == '"') {
                    r.add(new int[] {i, j});
                }
                i = j;
            } else {
                i++;
            }
        }
        return r;
    }

    private static boolean dentroDeLiteral(String src, int pos) {
        for (int[] l : literais(src)) {
            if (pos >= l[0] && pos < l[1]) {
                return true;
            }
        }
        return false;
    }

    /** Texto de {@code inicio} até o primeiro {@code fim} fora de literal e de parênteses. */
    private static String ate(String src, int inicio, char fim) {
        int prof = 0;
        int i = inicio;
        List<int[]> lits = literais(src);
        while (i < src.length()) {
            int[] lit = null;
            for (int[] l : lits) {
                if (l[0] == i) {
                    lit = l;
                    break;
                }
            }
            if (lit != null) {
                i = lit[1];
                continue;
            }
            char c = src.charAt(i);
            if (c == '(' || c == '{' || c == '[') {
                prof++;
            } else if (c == ')' || c == '}' || c == ']') {
                if (prof == 0) {
                    break;
                }
                prof--;
            } else if (c == fim && prof == 0) {
                break;
            } else if (fim == ',' && c == ',' && prof == 0) {
                break;
            }
            i++;
        }
        return src.substring(inicio, i);
    }

    private static String primeiroArgumento(String src, int inicio) {
        return ate(src, inicio, ',');
    }

    // ------------------------------------------------------------- I-20 nos .sql do repositório

    static final List<Path> RAIZES_SQL = List.of(Path.of("src/main/resources"), Path.of("infra/db"));

    /**
     * {@code EXECUTE format(... %s ...)} aceitos, com motivo: o argumento não vem de contexto nem de
     * usuário. Contagem exata por arquivo.
     */
    static final Map<String, Integer> FORMAT_S_ACEITOS = Map.of(
            // f é regprocedure lido do catálogo; a saída do tipo já vem citada.
            "src/main/resources/db/reversao/V1__modelo_v2.sql", 1,
            // atributos de papel vêm da lista VALUES fixa do próprio arquivo.
            "infra/db/bootstrap.sql", 2);

    @Test
    void sqlDoRepositorioNaoMontaValorNemGravaContexto() throws IOException {
        Map<String, String> sqls = new TreeMap<>();
        for (Path raiz : RAIZES_SQL) {
            try (Stream<Path> s = Files.walk(raiz)) {
                for (Path p : s.filter(p -> p.toString().endsWith(".sql")).toList()) {
                    sqls.put(p.toString().replace('\\', '/'), Files.readString(p, StandardCharsets.UTF_8));
                }
            }
        }
        assertThat(sqls).containsKey("src/main/resources/db/migration/V1__modelo_v2.sql").containsKey("infra/db/bootstrap.sql");
        Map<String, List<String>> defeitos = new TreeMap<>();
        Map<String, Integer> formatS = new TreeMap<>();
        for (Map.Entry<String, String> f : sqls.entrySet()) {
            List<String> d = verificaSql(f.getValue(), formatS, f.getKey());
            if (!d.isEmpty()) {
                defeitos.put(f.getKey(), d);
            }
        }
        assertThat(defeitos).isEmpty();
        assertThat(formatS).isEqualTo(FORMAT_S_ACEITOS);
    }

    @Test
    void controleNegativoVerificadorDeSqlDosArquivos() {
        for (String ruim : List.of(
                "SELECT set_config('app.sessao', 'abc', true);",
                "PERFORM set_config('saas.transicao', 'T2', false);",
                "SET LOCAL app.papel = 'ADMIN';",
                "set app.clinica_id to 'x';",
                "EXECUTE 'SELECT * FROM t WHERE id = ' || p_id;",
                "EXECUTE format('SELECT %s', current_setting('app.sessao'));",
                "EXECUTE format('DELETE FROM t WHERE c = %s', v);")) {
            Map<String, Integer> fs = new TreeMap<>();
            List<String> d = verificaSql(ruim, fs, "mutante.sql");
            assertThat(!d.isEmpty() || !fs.isEmpty()).as(ruim).isTrue();
        }
        Map<String, Integer> fs = new TreeMap<>();
        assertThat(verificaSql("-- EXECUTE 'x' || y\nGRANT EXECUTE ON FUNCTION f() TO saas_app;\n"
                + "CREATE TRIGGER t AFTER INSERT ON x FOR EACH ROW EXECUTE FUNCTION g();\n"
                + "PERFORM set_config('saas.transicao', 'T3', true);\n"
                + "EXECUTE format('ALTER TABLE saas.%I ENABLE ROW LEVEL SECURITY', t);\n"
                + "SELECT nullif(current_setting('app.papel', true), '');", fs, "bom.sql")).isEmpty();
        assertThat(fs).isEmpty();
    }

    static List<String> verificaSql(String bruto, Map<String, Integer> formatS, String nome) {
        String sql = semComentariosSql(bruto);
        List<String> d = new ArrayList<>();
        Matcher m = Pattern.compile("(?i)set_config\\s*\\(([^;]*?)\\)\\s*[;,)]").matcher(sql);
        while (m.find()) {
            String args = m.group(1);
            if (args.matches("(?is)\\s*'app\\..*")) {
                d.add("set_config de contexto em SQL: " + trecho(m.group(), 0));
            }
            if (!args.matches("(?is).*,\\s*true\\s*")) {
                d.add("set_config nao local: " + trecho(m.group(), 0));
            }
        }
        Matcher set = Pattern.compile("(?i)\\b(SET|RESET)\\s+(LOCAL\\s+|SESSION\\s+)?\"?app\"?\\.").matcher(sql);
        if (set.find()) {
            d.add("SET de contexto em SQL: " + trecho(sql, set.start()));
        }
        Matcher ex = Pattern.compile("(?i)\\bEXECUTE\\s+(?!FUNCTION\\b|PROCEDURE\\b|ON\\b)").matcher(sql);
        while (ex.find()) {
            int fim = sql.indexOf(';', ex.end());
            String cmd = sql.substring(ex.end(), fim < 0 ? sql.length() : fim);
            if (cmd.contains("||")) {
                d.add("EXECUTE com concatenacao: " + trecho(cmd, 0));
            }
            if (cmd.matches("(?is).*current_setting\\s*\\(.*")) {
                d.add("EXECUTE com valor de contexto: " + trecho(cmd, 0));
            }
            if (!cmd.matches("(?is)^(format\\s*\\(|'|\\$).*")) {
                d.add("EXECUTE de texto nao fixo: " + trecho(cmd, 0));
            }
            if (cmd.matches("(?is)^format\\s*\\(\\s*'[^']*%s.*")) {
                formatS.merge(nome, 1, Integer::sum);
            }
        }
        return d;
    }

    /** Tira comentários {@code --} e {@code /* * /} fora de literais com aspas simples. */
    static String semComentariosSql(String s) {
        StringBuilder out = new StringBuilder(s.length());
        boolean aspas = false;
        int i = 0;
        while (i < s.length()) {
            char c = s.charAt(i);
            if (aspas) {
                out.append(c);
                if (c == '\'') {
                    aspas = false;
                }
                i++;
            } else if (c == '\'') {
                aspas = true;
                out.append(c);
                i++;
            } else if (s.startsWith("--", i)) {
                int fim = s.indexOf('\n', i);
                i = fim < 0 ? s.length() : fim;
            } else if (s.startsWith("/*", i)) {
                int fim = s.indexOf("*/", i + 2);
                i = fim < 0 ? s.length() : fim + 2;
                out.append(' ');
            } else {
                out.append(c);
                i++;
            }
        }
        return out.toString();
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
