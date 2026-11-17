package saasagenda.arquivos.storage;

import java.time.Duration;
import java.time.Instant;
import java.util.Base64;
import java.util.List;
import java.util.Map;
import java.util.TreeMap;
import java.util.regex.Pattern;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.DisposableBean;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Profile;
import org.springframework.stereotype.Component;
import saasagenda.arquivos.ArquivosApi;
import software.amazon.awssdk.auth.credentials.AwsCredentialsProvider;
import software.amazon.awssdk.auth.credentials.DefaultCredentialsProvider;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.s3.model.GetObjectRequest;
import software.amazon.awssdk.services.s3.model.PutObjectRequest;
import software.amazon.awssdk.services.s3.model.ServerSideEncryption;
import software.amazon.awssdk.services.s3.presigner.S3Presigner;
import software.amazon.awssdk.services.s3.presigner.model.GetObjectPresignRequest;
import software.amazon.awssdk.services.s3.presigner.model.PresignedGetObjectRequest;
import software.amazon.awssdk.services.s3.presigner.model.PresignedPutObjectRequest;
import software.amazon.awssdk.services.s3.presigner.model.PutObjectPresignRequest;

/**
 * Pré-assinatura SigV4 de URLs do S3 com o SDK v2, sem chamada à nuvem (ADR-0010, ADR-0011).
 * <p>
 * Configuração do ambiente ({@code application-web.properties}): bucket, chave KMS, região
 * (obrigatoriamente {@code sa-east-1}) e validade (1 a 300 s). Credenciais pela cadeia padrão do SDK
 * (variáveis de ambiente da AWS no contrato; papel da tarefa em produção); nunca lidas nem logadas
 * aqui. Sem bucket e sem chave KMS, o storage fica indisponível (as rotas de anexo respondem 503) e
 * o resto do processo web sobe; configuração parcial ou inválida derruba a partida.
 * <p>
 * PUT: {@code Content-Type}, {@code Content-Length}, {@code x-amz-checksum-sha256} e SSE-KMS
 * ({@code x-amz-server-side-encryption: aws:kms} com a chave do ambiente) entram nos cabeçalhos
 * assinados: o S3 recusa o envio sem eles ou com outro valor. GET: resposta forçada a
 * {@code attachment} e {@code no-store} (STRIDE I-11). Nada daqui vai para log.
 */
@Component
@Profile("web")
public class AssinadorS3 implements DisposableBean {

    public static final String REGIAO = "sa-east-1";

    private static final Logger LOG = LoggerFactory.getLogger(AssinadorS3.class);
    private static final Pattern BUCKET = Pattern.compile("[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]");
    private static final Pattern CHAVE_KMS = Pattern.compile("[A-Za-z0-9:/_.-]{1,2048}");
    private static final Pattern CHAVE_OBJETO = Pattern.compile("[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}");

    private final String bucket;
    private final String chaveKms;
    private final Duration validade;
    private final S3Presigner presigner;

    @Autowired
    public AssinadorS3(
            @Value("${saas.s3.bucket:}") String bucket,
            @Value("${saas.s3.kms-key-id:}") String chaveKms,
            @Value("${saas.s3.regiao:}") String regiao,
            @Value("${saas.s3.validade-segundos:300}") long validadeSegundos) {
        this(bucket, chaveKms, regiao, validadeSegundos, null);
    }

    /** Para teste: credenciais explícitas em vez da cadeia padrão. */
    public AssinadorS3(String bucket, String chaveKms, String regiao, long validadeSegundos,
            AwsCredentialsProvider credenciais) {
        this.bucket = bucket == null ? "" : bucket.trim();
        this.chaveKms = chaveKms == null ? "" : chaveKms.trim();
        if (validadeSegundos < 1 || validadeSegundos > ArquivosApi.VALIDADE_MAXIMA_SEGUNDOS) {
            throw new IllegalStateException("validade da URL assinada fora de 1.."
                    + ArquivosApi.VALIDADE_MAXIMA_SEGUNDOS + " s");
        }
        this.validade = Duration.ofSeconds(validadeSegundos);
        if (this.bucket.isEmpty() && this.chaveKms.isEmpty()) {
            LOG.warn("storage de anexos nao configurado: rotas de anexo indisponiveis");
            this.presigner = null;
            return;
        }
        if (!BUCKET.matcher(this.bucket).matches() || !CHAVE_KMS.matcher(this.chaveKms).matches()) {
            throw new IllegalStateException("storage de anexos com configuracao incompleta ou invalida");
        }
        if (!REGIAO.equals(regiao == null ? "" : regiao.trim())) {
            throw new IllegalStateException("storage de anexos so em " + REGIAO);
        }
        this.presigner = S3Presigner.builder()
                .region(Region.SA_EAST_1)
                .credentialsProvider(credenciais != null ? credenciais : DefaultCredentialsProvider.builder().build())
                .build();
    }

    public boolean disponivel() {
        return presigner != null;
    }

    /** URL PUT da chave exata, com tipo, tamanho, SHA-256 e SSE-KMS assinados. */
    public UrlAssinada assinaPut(String chave, String tipoMime, long tamanhoBytes, byte[] sha256) {
        exigeDisponivel();
        exigeChave(chave);
        PutObjectRequest put = PutObjectRequest.builder()
                .bucket(bucket)
                .key(chave)
                .contentType(tipoMime)
                .contentLength(tamanhoBytes)
                .checksumSHA256(Base64.getEncoder().encodeToString(sha256))
                .serverSideEncryption(ServerSideEncryption.AWS_KMS)
                .ssekmsKeyId(chaveKms)
                .build();
        PresignedPutObjectRequest p = presigner.presignPutObject(PutObjectPresignRequest.builder()
                .signatureDuration(validade)
                .putObjectRequest(put)
                .build());
        return new UrlAssinada(p.url().toString(), cabecalhos(p.signedHeaders()), p.expiration());
    }

    /** URL GET da chave exata, como anexo para salvar e sem cache. */
    public UrlAssinada assinaGet(String chave) {
        exigeDisponivel();
        exigeChave(chave);
        GetObjectRequest get = GetObjectRequest.builder()
                .bucket(bucket)
                .key(chave)
                .responseContentDisposition("attachment")
                .responseCacheControl("no-store")
                .build();
        PresignedGetObjectRequest p = presigner.presignGetObject(GetObjectPresignRequest.builder()
                .signatureDuration(validade)
                .getObjectRequest(get)
                .build());
        return new UrlAssinada(p.url().toString(), cabecalhos(p.signedHeaders()), p.expiration());
    }

    private void exigeDisponivel() {
        if (presigner == null) {
            throw new ArquivosApi.RecusaException(ArquivosApi.Motivo.INDISPONIVEL);
        }
    }

    /** Só a chave opaca gerada pelo banco (UUID): nunca nome de arquivo nem dado do paciente. */
    private static void exigeChave(String chave) {
        if (chave == null || !CHAVE_OBJETO.matcher(chave).matches()) {
            throw new IllegalStateException("chave de objeto fora do formato opaco");
        }
    }

    /** Cabeçalhos assinados que o cliente envia ({@code host} o próprio cliente HTTP põe). */
    private static Map<String, String> cabecalhos(Map<String, List<String>> assinados) {
        Map<String, String> r = new TreeMap<>(String.CASE_INSENSITIVE_ORDER);
        assinados.forEach((nome, valores) -> {
            if (!"host".equalsIgnoreCase(nome) && valores != null && !valores.isEmpty()) {
                r.put(nome.toLowerCase(java.util.Locale.ROOT), valores.get(0));
            }
        });
        return r;
    }

    @Override
    public void destroy() {
        if (presigner != null) {
            presigner.close();
        }
    }

    /** URL, cabeçalhos a enviar e expiração. {@code toString} sem a URL. */
    public record UrlAssinada(String url, Map<String, String> cabecalhos, Instant expiraEm) {
        public UrlAssinada {
            cabecalhos = Map.copyOf(cabecalhos);
        }

        @Override
        public String toString() {
            return "UrlAssinada[expiraEm=" + expiraEm + "]";
        }
    }
}
