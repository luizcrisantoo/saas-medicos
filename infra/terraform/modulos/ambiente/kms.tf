# Uma chave KMS por finalidade, todas com rotação anual ligada (F10.5; ADR-0026, chave mestra na
# nuvem). Política da chave: a padrão da AWS (conta dona com acesso total via IAM), porque o plan de
# aceite roda sem o id da conta e uma política própria sem o principal raiz trancaria a chave.

resource "aws_kms_key" "banco" {
  description             = "RDS PostgreSQL ${local.nome}: cifra em repouso"
  enable_key_rotation     = true
  deletion_window_in_days = 30
}

resource "aws_kms_alias" "banco" {
  name          = "alias/${var.prefixo}/${var.ambiente}/banco"
  target_key_id = aws_kms_key.banco.key_id
}

resource "aws_kms_key" "anexos" {
  description             = "Bucket de anexos ${local.bucket_anexos}: SSE-KMS (ADR-0010)"
  enable_key_rotation     = true
  deletion_window_in_days = 30
}

resource "aws_kms_alias" "anexos" {
  name          = "alias/${var.prefixo}/${var.ambiente}/anexos"
  target_key_id = aws_kms_key.anexos.key_id
}

resource "aws_kms_key" "segredos" {
  description             = "Secrets Manager ${local.nome}: credenciais dos papeis do banco e senha mestra"
  enable_key_rotation     = true
  deletion_window_in_days = 30
}

resource "aws_kms_alias" "segredos" {
  name          = "alias/${var.prefixo}/${var.ambiente}/segredos"
  target_key_id = aws_kms_key.segredos.key_id
}
