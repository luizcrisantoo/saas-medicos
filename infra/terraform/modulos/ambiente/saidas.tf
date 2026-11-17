# Valores que a aplicação recebe por variável de ambiente (src/main/resources/application-web.properties)
# e que o operador usa para preencher os segredos. Nenhum valor sensível.

output "rds_endpoint" {
  description = "host:porta do PostgreSQL (vai no campo host dos segredos dos papéis)"
  value       = aws_db_instance.postgres.endpoint
}

output "rds_identifier" {
  value = aws_db_instance.postgres.identifier
}

output "rds_senha_mestra_secret_arn" {
  description = "Segredo da senha mestra gerado pelo RDS (só para o bootstrap.sql e emergência)"
  value       = one(aws_db_instance.postgres.master_user_secret[*].secret_arn)
}

output "bucket_anexos" {
  description = "SAAS_S3_BUCKET"
  value       = aws_s3_bucket.anexos.bucket
}

output "kms_anexos_key_id" {
  description = "SAAS_S3_KMS_KEY_ID"
  value       = aws_kms_key.anexos.arn
}

output "segredos_arns" {
  description = "ARN do segredo de cada papel do banco"
  value       = { for k, s in aws_secretsmanager_secret.papel_banco : k => s.arn }
}

output "cognito_issuer" {
  description = "SAAS_AUTH_ISSUER"
  value       = "https://${aws_cognito_user_pool.equipe.endpoint}"
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.equipe.id
}

output "cognito_client_id_web" {
  description = "client_id aceito pelo validador de access token"
  value       = aws_cognito_user_pool_client.web.id
}

output "vpc_id" {
  value = aws_vpc.esta.id
}

output "subnets_privadas" {
  value = aws_subnet.privada[*].id
}

output "security_group_aplicacao" {
  description = "Grupo que a computação da aplicação (P3) deve usar para alcançar o banco"
  value       = aws_security_group.aplicacao.id
}

output "politica_iam_web_arn" {
  value = aws_iam_policy.web.arn
}

output "politica_iam_jobs_arn" {
  value = aws_iam_policy.jobs.arn
}

output "sns_alertas_arn" {
  value = aws_sns_topic.alertas.arn
}
