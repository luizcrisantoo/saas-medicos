# RDS PostgreSQL 16 (F10.4): cifrado com chave própria, só em sub-rede privada, PITR pelos backups
# automáticos, TLS obrigatório (rds.force_ssl), log do servidor exportado ao CloudWatch e senha
# mestra gerada e guardada pelo próprio RDS no Secrets Manager (nenhuma senha no código).

# O grupo de logs nasce antes do banco, com retenção definida; o RDS passa a escrever nele.
resource "aws_cloudwatch_log_group" "postgresql" {
  name              = local.log_group_postgres
  retention_in_days = var.retencao_logs_dias
}

resource "aws_db_parameter_group" "postgres16" {
  name        = "${local.nome}-postgres16"
  family      = "postgres16"
  description = "PostgreSQL 16 do ${local.nome}: TLS obrigatorio e log de conexoes"

  # Conexão sem TLS é recusada (ADR-0026, item 2).
  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }

  # Quem conectou e quando, para a investigação de um ALERTA_DDL_SAAS; sem texto de comando.
  parameter {
    name  = "log_connections"
    value = "1"
  }

  parameter {
    name  = "log_disconnections"
    value = "1"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_db_instance" "postgres" {
  identifier = local.rds_identifier

  engine                     = "postgres"
  engine_version             = var.rds_versao
  auto_minor_version_upgrade = true
  instance_class             = var.rds_classe
  parameter_group_name       = aws_db_parameter_group.postgres16.name

  db_name  = "saas_agenda"
  username = "saas_admin"
  # Senha fora do código: o RDS gera e guarda no Secrets Manager, cifrada com a chave dos segredos.
  manage_master_user_password   = true
  master_user_secret_kms_key_id = aws_kms_key.segredos.arn

  allocated_storage     = var.rds_armazenamento_gb
  max_allocated_storage = var.rds_armazenamento_max_gb
  storage_type          = "gp3"
  storage_encrypted     = true
  kms_key_id            = aws_kms_key.banco.arn

  db_subnet_group_name   = aws_db_subnet_group.banco.name
  vpc_security_group_ids = [aws_security_group.banco.id]
  publicly_accessible    = false
  multi_az               = var.rds_multi_az

  backup_retention_period = var.rds_retencao_backup_dias
  backup_window           = "05:00-06:00" # 02h a 03h em Recife (UTC-3)
  maintenance_window      = "sun:06:00-sun:07:00"
  copy_tags_to_snapshot   = true

  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]

  # Em prod a proteção não se desliga por variável (F10.4).
  deletion_protection       = local.prod ? true : var.rds_protecao_exclusao
  skip_final_snapshot       = !local.prod
  final_snapshot_identifier = local.prod ? "${local.rds_identifier}-final" : null
  apply_immediately         = false

  depends_on = [aws_cloudwatch_log_group.postgresql]
}
