# Secrets Manager (F10.6; ADR-0024, ADR-0011): um segredo por papel de login do banco, cifrado com a
# chave KMS dos segredos. Nenhum valor aqui: a versão (usuário, senha, host, porta, banco) é gravada
# pelo operador depois do bootstrap.sql (ou por rotação), nunca pelo Terraform. A senha mestra do RDS
# é outro segredo, criado e rotacionado pelo próprio RDS (banco.tf).

resource "aws_secretsmanager_secret" "papel_banco" {
  for_each = toset(local.papeis_banco)

  name        = "${var.prefixo}/${var.ambiente}/${each.key}"
  description = "Credencial do papel ${each.key} no PostgreSQL ${local.rds_identifier} (ADR-0024)"
  kms_key_id  = aws_kms_key.segredos.arn

  # Em prod, 30 dias para desfazer uma exclusão; fora de prod, o mínimo, para recriar sem esperar.
  recovery_window_in_days = local.prod ? 30 : 7
}
