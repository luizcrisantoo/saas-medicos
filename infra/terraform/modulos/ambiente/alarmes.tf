# Alarmes (F10.8): as linhas ALERTA_DDL_SAAS (gatilho de evento, infra/db/bootstrap.sql) e
# ALERTA_PREPARO_VOLUME (E-09, F4) saem no log do PostgreSQL, que o RDS exporta ao CloudWatch. Um
# filtro de métrica por marcador, um alarme por métrica, e-mail pelo SNS. A linha nunca traz contato,
# token ou código, então o tópico só carrega o nome do alarme.

resource "aws_sns_topic" "alertas" {
  name = "${local.nome}-alertas"
}

resource "aws_sns_topic_subscription" "alertas_email" {
  topic_arn = aws_sns_topic.alertas.arn
  protocol  = "email"
  endpoint  = var.email_alerta
}

locals {
  marcadores = {
    ddl = {
      marcador  = "ALERTA_DDL_SAAS"
      metrica   = "AlertaDdlSaas"
      descricao = "DDL no schema saas fora do pipeline de migracao (R-07, R-08)"
    }
    preparo_volume = {
      marcador  = "ALERTA_PREPARO_VOLUME"
      metrica   = "AlertaPreparoVolume"
      descricao = "volume anormal de preparos de envio (E-09)"
    }
  }
}

resource "aws_cloudwatch_log_metric_filter" "marcador" {
  for_each = local.marcadores

  name           = "${local.nome}-${each.key}"
  log_group_name = aws_cloudwatch_log_group.postgresql.name
  pattern        = "\"${each.value.marcador}\""

  metric_transformation {
    name          = each.value.metrica
    namespace     = local.namespace_metricas
    value         = "1"
    default_value = 0
  }
}

resource "aws_cloudwatch_metric_alarm" "marcador" {
  for_each = local.marcadores

  alarm_name        = "${local.nome}-${each.key}"
  alarm_description = "${each.value.marcador} no log do PostgreSQL ${local.rds_identifier}: ${each.value.descricao}"

  namespace           = local.namespace_metricas
  metric_name         = each.value.metrica
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.alertas.arn]
}
