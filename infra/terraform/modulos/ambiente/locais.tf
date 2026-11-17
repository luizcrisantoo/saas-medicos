locals {
  nome = "${var.prefixo}-${var.ambiente}"
  prod = var.ambiente == "prod"

  # Namespace das métricas e nomes conhecidos no plan (o aceite lê esses valores direto do plano).
  namespace_metricas = "SaasAgenda/${var.ambiente}"
  rds_identifier     = local.nome
  bucket_anexos      = "${local.nome}-anexos"
  log_group_postgres = "/aws/rds/instance/${local.rds_identifier}/postgresql"

  # Papéis de login do banco (ADR-0024, infra/db/bootstrap.sql): um segredo por papel.
  papeis_banco = ["saas_app", "saas_jobs", "saas_auth", "saas_migracao"]
}
