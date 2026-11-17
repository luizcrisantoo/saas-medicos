# Políticas IAM de menor privilégio para os processos da aplicação, separadas por processo (E-09,
# ADR-0024). Só as políticas: o papel (role) que as recebe depende da computação escolhida (P3) e
# entra com ela. Nenhuma referência a id de conta: tudo por ARN dos recursos deste módulo.

locals {
  via_s3       = "s3.${var.regiao}.amazonaws.com"
  via_segredos = "secretsmanager.${var.regiao}.amazonaws.com"
}

resource "aws_iam_policy" "web" {
  name        = "${local.nome}-web"
  description = "Processo web: anexos no bucket do ambiente e segredos saas_app e saas_auth"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "AnexosObjetos"
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:GetObject", "s3:DeleteObject", "s3:AbortMultipartUpload"]
        Resource = "${aws_s3_bucket.anexos.arn}/*"
      },
      {
        Sid      = "AnexosBucket"
        Effect   = "Allow"
        Action   = ["s3:ListBucket", "s3:ListBucketMultipartUploads"]
        Resource = aws_s3_bucket.anexos.arn
      },
      {
        Sid      = "ChaveDosAnexosViaS3"
        Effect   = "Allow"
        Action   = ["kms:GenerateDataKey", "kms:Decrypt"]
        Resource = aws_kms_key.anexos.arn
        Condition = {
          StringEquals = { "kms:ViaService" = local.via_s3 }
        }
      },
      {
        Sid    = "SegredosWeb"
        Effect = "Allow"
        Action = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
        Resource = [
          aws_secretsmanager_secret.papel_banco["saas_app"].arn,
          aws_secretsmanager_secret.papel_banco["saas_auth"].arn,
        ]
      },
      {
        Sid      = "ChaveDosSegredos"
        Effect   = "Allow"
        Action   = ["kms:Decrypt"]
        Resource = aws_kms_key.segredos.arn
        Condition = {
          StringEquals = { "kms:ViaService" = local.via_segredos }
        }
      },
    ]
  })
}

resource "aws_iam_policy" "jobs" {
  name        = "${local.nome}-jobs"
  description = "Processo de jobs: so o segredo saas_jobs (nenhum acesso aos anexos)"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "SegredoJobs"
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
        Resource = aws_secretsmanager_secret.papel_banco["saas_jobs"].arn
      },
      {
        Sid      = "ChaveDosSegredos"
        Effect   = "Allow"
        Action   = ["kms:Decrypt"]
        Resource = aws_kms_key.segredos.arn
        Condition = {
          StringEquals = { "kms:ViaService" = local.via_segredos }
        }
      },
    ]
  })
}
