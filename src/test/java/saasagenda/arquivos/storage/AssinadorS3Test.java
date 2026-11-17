package saasagenda.arquivos.storage;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.net.URI;
import java.net.URLDecoder;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneOffset;
import java.time.format.DateTimeFormatter;
import java.util.Base64;
import java.util.HexFormat;
import java.util.Map;
import java.util.TreeMap;
import java.util.UUID;
import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;
import org.junit.jupiter.api.Test;
import saasagenda.arquivos.ArquivosApi;
import software.amazon.awssdk.auth.credentials.AwsBasicCredentials;
import software.amazon.awssdk.auth.credentials.StaticCredentialsProvider;

/**
 * URL pré-assinada do S3 conferida sem nuvem: região, bucket, chave opaca, validade, cabeçalhos
 * assinados (SSE-KMS, tipo, tamanho, SHA-256) e a própria assinatura SigV4, recalculada aqui de
 * forma independente do SDK. Credenciais fictícias.
 */
public class AssinadorS3Test {

    static final String BUCKET = "anexos-ficticio-dev";
    static final String KMS = "arn:aws:kms:sa-east-1:000000000000:key/11111111-2222-3333-4444-555555555555";
    /** Credenciais fictícias geradas a cada execução (nenhum valor fixo no repositório). */
    public static final String ID = "ficticio-" + aleatorio(8);
    public static final String SEGREDO = aleatorio(20);

    static AssinadorS3 assinador(long validade) {
        return new AssinadorS3(BUCKET, KMS, "sa-east-1", validade,
                StaticCredentialsProvider.create(AwsBasicCredentials.create(ID, SEGREDO)));
    }

    @Test
    void putAssinaSseKmsTipoTamanhoEHashNaChaveOpaca() throws Exception {
        String chave = UUID.randomUUID().toString();
        byte[] sha = MessageDigest.getInstance("SHA-256").digest("conteudo ficticio".getBytes(StandardCharsets.UTF_8));
        Instant antes = Instant.now();
        AssinadorS3.UrlAssinada u = assinador(300).assinaPut(chave, "application/pdf", 1234, sha);
        URI url = URI.create(u.url());
        Map<String, String> q = query(url);
        assertThat(url.getScheme()).isEqualTo("https");
        assertThat(url.getHost()).isEqualTo(BUCKET + ".s3.sa-east-1.amazonaws.com");
        assertThat(url.getRawPath()).isEqualTo("/" + chave);
        assertThat(q.get("X-Amz-Algorithm")).isEqualTo("AWS4-HMAC-SHA256");
        assertThat(q.get("X-Amz-Credential")).startsWith(ID + "/").endsWith("/sa-east-1/s3/aws4_request");
        assertThat(Long.parseLong(q.get("X-Amz-Expires"))).isBetween(1L, 300L);
        assertThat(u.expiraEm()).isBefore(antes.plusSeconds(301)).isAfter(antes);
        assertThat(q.get("X-Amz-SignedHeaders").split(";")).contains("host", "content-type", "content-length",
                "x-amz-server-side-encryption", "x-amz-server-side-encryption-aws-kms-key-id", "x-amz-checksum-sha256");
        assertThat(u.cabecalhos()).containsEntry("x-amz-server-side-encryption", "aws:kms")
                .containsEntry("x-amz-server-side-encryption-aws-kms-key-id", KMS)
                .containsEntry("content-type", "application/pdf")
                .containsEntry("content-length", "1234")
                .containsEntry("x-amz-checksum-sha256", Base64.getEncoder().encodeToString(sha))
                .doesNotContainKey("host");
        // Nenhum segredo ou valor de cabeçalho assinado vai na URL além do esperado.
        assertThat(u.url()).doesNotContain(SEGREDO).doesNotContain("kms-key-id=");
        assertThat(u.toString()).doesNotContain(chave).doesNotContain("X-Amz");
        confereAssinatura("PUT", url, u.cabecalhos());
    }

    @Test
    void getAssinadoComoAnexoSemCache() throws Exception {
        String chave = UUID.randomUUID().toString();
        AssinadorS3.UrlAssinada u = assinador(300).assinaGet(chave);
        URI url = URI.create(u.url());
        Map<String, String> q = query(url);
        assertThat(url.getHost()).isEqualTo(BUCKET + ".s3.sa-east-1.amazonaws.com");
        assertThat(url.getRawPath()).isEqualTo("/" + chave);
        assertThat(Long.parseLong(q.get("X-Amz-Expires"))).isBetween(1L, 300L);
        assertThat(q).containsEntry("response-content-disposition", "attachment")
                .containsEntry("response-cache-control", "no-store");
        confereAssinatura("GET", url, u.cabecalhos());
    }

    @Test
    void validadeMenorRespeitada() throws Exception {
        AssinadorS3.UrlAssinada u = assinador(60).assinaGet(UUID.randomUUID().toString());
        assertThat(query(URI.create(u.url())).get("X-Amz-Expires")).isEqualTo("60");
    }

    @Test
    void configuracaoInvalidaDerrubaAPartida() {
        var cred = StaticCredentialsProvider.create(AwsBasicCredentials.create(ID, SEGREDO));
        assertThatThrownBy(() -> new AssinadorS3(BUCKET, KMS, "us-east-1", 300, cred)).isInstanceOf(IllegalStateException.class);
        assertThatThrownBy(() -> new AssinadorS3(BUCKET, KMS, "", 300, cred)).isInstanceOf(IllegalStateException.class);
        assertThatThrownBy(() -> new AssinadorS3(BUCKET, "", "sa-east-1", 300, cred)).isInstanceOf(IllegalStateException.class);
        assertThatThrownBy(() -> new AssinadorS3("", KMS, "sa-east-1", 300, cred)).isInstanceOf(IllegalStateException.class);
        assertThatThrownBy(() -> new AssinadorS3("Bucket_Invalido", KMS, "sa-east-1", 300, cred)).isInstanceOf(IllegalStateException.class);
        assertThatThrownBy(() -> new AssinadorS3(BUCKET, KMS, "sa-east-1", 301, cred)).isInstanceOf(IllegalStateException.class);
        assertThatThrownBy(() -> new AssinadorS3(BUCKET, KMS, "sa-east-1", 0, cred)).isInstanceOf(IllegalStateException.class);
    }

    @Test
    void semConfiguracaoFicaIndisponivel() {
        AssinadorS3 a = new AssinadorS3("", "", "", 300, null);
        assertThat(a.disponivel()).isFalse();
        assertThatThrownBy(() -> a.assinaGet(UUID.randomUUID().toString()))
                .isInstanceOfSatisfying(ArquivosApi.RecusaException.class,
                        e -> assertThat(e.motivo()).isEqualTo(ArquivosApi.Motivo.INDISPONIVEL));
    }

    @Test
    void soChaveOpaca() {
        AssinadorS3 a = assinador(300);
        for (String ruim : new String[] {"exame-maria.pdf", "../outro", "", null, "pacientes/123"}) {
            assertThatThrownBy(() -> a.assinaGet(ruim)).as(String.valueOf(ruim)).isInstanceOf(IllegalStateException.class);
        }
    }

    // ------------------------------------------------------------- SigV4 independente do SDK

    public static Map<String, String> query(URI url) {
        Map<String, String> r = new TreeMap<>();
        for (String par : url.getRawQuery().split("&")) {
            int i = par.indexOf('=');
            r.put(URLDecoder.decode(par.substring(0, i), StandardCharsets.UTF_8),
                    URLDecoder.decode(par.substring(i + 1), StandardCharsets.UTF_8));
        }
        return r;
    }

    /** Recalcula a assinatura de URL pré-assinada (SigV4, serviço s3) e compara com a da URL. */
    public static void confereAssinatura(String metodo, URI url, Map<String, String> cabecalhos) throws Exception {
        Map<String, String> q = query(url);
        String assinatura = q.remove("X-Amz-Signature");
        Map<String, String> canonica = new TreeMap<>();
        q.forEach((k, v) -> canonica.put(enc(k), enc(v)));
        String query = canonica.entrySet().stream().map(e -> e.getKey() + "=" + e.getValue())
                .reduce((a, b) -> a + "&" + b).orElse("");
        Map<String, String> h = new TreeMap<>();
        h.put("host", url.getHost());
        cabecalhos.forEach((k, v) -> h.put(k.toLowerCase(), v.trim()));
        String assinados = q.get("X-Amz-SignedHeaders");
        assertThat(String.join(";", h.keySet())).isEqualTo(assinados);
        String linhas = h.entrySet().stream().map(e -> e.getKey() + ":" + e.getValue() + "\n")
                .reduce("", (a, b) -> a + b);
        String pedido = metodo + "\n" + url.getRawPath() + "\n" + query + "\n" + linhas + "\n" + assinados
                + "\nUNSIGNED-PAYLOAD";
        String data = q.get("X-Amz-Date");
        String escopo = q.get("X-Amz-Credential").substring(ID.length() + 1);
        String paraAssinar = "AWS4-HMAC-SHA256\n" + data + "\n" + escopo + "\n"
                + HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(pedido.getBytes(StandardCharsets.UTF_8)));
        String dia = DateTimeFormatter.ofPattern("yyyyMMdd").withZone(ZoneOffset.UTC).format(Instant.now());
        assertThat(escopo).isEqualTo(data.substring(0, 8) + "/sa-east-1/s3/aws4_request");
        assertThat(data.substring(0, 8)).isIn(dia, DateTimeFormatter.ofPattern("yyyyMMdd").withZone(ZoneOffset.UTC)
                .format(Instant.now().minus(Duration.ofMinutes(1))));
        byte[] k = hmac(("AWS4" + SEGREDO).getBytes(StandardCharsets.UTF_8), data.substring(0, 8));
        k = hmac(k, "sa-east-1");
        k = hmac(k, "s3");
        k = hmac(k, "aws4_request");
        assertThat(HexFormat.of().formatHex(hmac(k, paraAssinar))).isEqualTo(assinatura);
    }

    private static byte[] hmac(byte[] chave, String dado) throws Exception {
        Mac m = Mac.getInstance("HmacSHA256");
        m.init(new SecretKeySpec(chave, "HmacSHA256"));
        return m.doFinal(dado.getBytes(StandardCharsets.UTF_8));
    }

    private static String aleatorio(int bytes) {
        byte[] b = new byte[bytes];
        new java.security.SecureRandom().nextBytes(b);
        return HexFormat.of().formatHex(b);
    }

    private static String enc(String s) {
        String r = java.net.URLEncoder.encode(s, StandardCharsets.UTF_8);
        return r.replace("+", "%20").replace("*", "%2A").replace("%7E", "~");
    }
}
