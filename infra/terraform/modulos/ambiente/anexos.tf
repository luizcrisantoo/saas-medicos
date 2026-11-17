# Bucket privado de anexos (F10.5; ADR-0010): SSE-KMS com chave própria rotacionada, bloqueio
# público total, versionamento, dono único dos objetos e política que recusa acesso sem TLS e
# gravação sem SSE-KMS com a chave do bucket. O acesso de leitura é só por URL pré-assinada curta
# emitida pela aplicação (F8).

resource "aws_s3_bucket" "anexos" {
  bucket = local.bucket_anexos

  # Em prod o bucket não se destrói com objeto dentro.
  force_destroy = false
}

resource "aws_s3_bucket_ownership_controls" "anexos" {
  bucket = aws_s3_bucket.anexos.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "anexos" {
  bucket = aws_s3_bucket.anexos.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "anexos" {
  bucket = aws_s3_bucket.anexos.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "anexos" {
  bucket = aws_s3_bucket.anexos.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.anexos.arn
    }
    # Chave de bucket: menos chamadas ao KMS (custo), mesma chave.
    bucket_key_enabled = true
  }
}

# Uploads interrompidos não ficam cobrando; a retenção dos anexos em si é pergunta aberta (P7).
resource "aws_s3_bucket_lifecycle_configuration" "anexos" {
  bucket = aws_s3_bucket.anexos.id

  rule {
    id     = "aborta-multipart-incompleto"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  depends_on = [aws_s3_bucket_versioning.anexos]
}

resource "aws_s3_bucket_policy" "anexos" {
  bucket = aws_s3_bucket.anexos.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "RecusaSemTLS"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.anexos.arn,
          "${aws_s3_bucket.anexos.arn}/*",
        ]
        Condition = {
          Bool = { "aws:SecureTransport" = "false" }
        }
      },
      {
        Sid       = "RecusaGravacaoSemSSEKMS"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.anexos.arn}/*"
        Condition = {
          StringNotEquals = { "s3:x-amz-server-side-encryption" = "aws:kms" }
        }
      },
      {
        Sid       = "RecusaGravacaoSemCabecalhoSSE"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.anexos.arn}/*"
        Condition = {
          Null = { "s3:x-amz-server-side-encryption" = "true" }
        }
      },
      {
        Sid       = "RecusaGravacaoComOutraChave"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.anexos.arn}/*"
        Condition = {
          StringNotEquals = { "s3:x-amz-server-side-encryption-aws-kms-key-id" = aws_kms_key.anexos.arn }
        }
      },
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.anexos]
}
