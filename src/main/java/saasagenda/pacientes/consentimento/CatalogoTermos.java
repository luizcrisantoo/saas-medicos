package saasagenda.pacientes.consentimento;

import java.io.IOException;
import java.io.InputStream;
import java.io.UncheckedIOException;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.HexFormat;
import java.util.Map;
import java.util.Optional;
import java.util.TreeMap;
import java.util.function.Function;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import saasagenda.pacientes.ConsentimentoApi;
import saasagenda.pacientes.ConsentimentoApi.Termo;

/**
 * Textos de consentimento versionados ({@code classpath:lgpd/consentimento/<FINALIDADE>.txt}).
 * <p>
 * Formato do arquivo: primeira linha {@code revisao: <n>}, uma linha em branco e o texto. A versão
 * publicada é {@code <n>.<12 primeiros dígitos do SHA-256 do texto>}: ela identifica exatamente um
 * texto, então qualquer mudança no texto (mesmo sem trocar a revisão) gera versão nova e o paciente
 * nunca aceita sob uma versão um texto que não viu. O texto aceito é gravado inteiro em
 * {@code consentimento.texto_aceito}.
 */
final class CatalogoTermos {

    private static final Pattern CABECALHO = Pattern.compile("\\Arevisao: ([1-9][0-9]{0,5})\\R\\R(.+)\\z",
            Pattern.DOTALL);

    private final Map<String, Termo> vigentes;

    private CatalogoTermos(Map<String, Termo> vigentes) {
        this.vigentes = Map.copyOf(vigentes);
    }

    /** Lê os textos do classpath; falta de texto para alguma finalidade impede a partida. */
    static CatalogoTermos doClasspath() {
        return de(f -> {
            String caminho = "lgpd/consentimento/" + f + ".txt";
            try (InputStream in = CatalogoTermos.class.getClassLoader().getResourceAsStream(caminho)) {
                if (in == null) {
                    throw new IllegalStateException("texto de consentimento ausente: " + f);
                }
                return new String(in.readAllBytes(), StandardCharsets.UTF_8);
            } catch (IOException e) {
                throw new UncheckedIOException(e);
            }
        });
    }

    /** Monta o catálogo a partir do conteúdo bruto de cada finalidade. */
    static CatalogoTermos de(Function<String, String> conteudo) {
        Map<String, Termo> m = new TreeMap<>();
        for (String f : ConsentimentoApi.FINALIDADES) {
            m.put(f, termo(f, conteudo.apply(f)));
        }
        return new CatalogoTermos(m);
    }

    static Termo termo(String finalidade, String bruto) {
        String normalizado = bruto.replace("\r\n", "\n").strip();
        Matcher m = CABECALHO.matcher(normalizado);
        if (!m.matches()) {
            throw new IllegalStateException("texto de consentimento fora do formato: " + finalidade);
        }
        String texto = m.group(2).strip();
        return new Termo(finalidade, m.group(1) + "." + resumo(texto), texto);
    }

    Optional<Termo> vigente(String finalidade) {
        return Optional.ofNullable(finalidade == null ? null : vigentes.get(finalidade));
    }

    private static String resumo(String texto) {
        try {
            byte[] h = MessageDigest.getInstance("SHA-256").digest(texto.getBytes(StandardCharsets.UTF_8));
            return HexFormat.of().formatHex(h, 0, 6);
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException(e);
        }
    }
}
