# Raiz "conta": recursos da conta AWS que não pertencem a um ambiente. Hoje só o orçamento mensal
# (F10.10; ADR-0013: teto de R$ 800 para infraestrutura e WhatsApp somados). AWS Budgets é serviço
# global e aceita o provider em sa-east-1; não há provider extra nem alias (spec, seção 3.6).

terraform {
  required_version = ">= 1.9.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.80"
    }
  }
}

provider "aws" {
  region = "sa-east-1" # ADR-0012

  default_tags {
    tags = {
      Projeto  = "saas-agenda"
      Ambiente = "conta"
      Gerencia = "terraform"
    }
  }
}

locals {
  # Limite em USD = teto em R$ / cotação, arredondado PARA BAIXO com duas casas, para nunca passar
  # do teto quando convertido de volta. Nunca um valor fixo em USD: a cotação muda e o teto não.
  teto_mensal_usd = format("%.2f", floor(var.teto_mensal_brl / var.cotacao_usd_brl * 100) / 100)
}

resource "aws_budgets_budget" "teto_mensal" {
  name         = "saas-agenda-teto-mensal"
  budget_type  = "COST"
  time_unit    = "MONTHLY"
  limit_unit   = "USD"
  limit_amount = local.teto_mensal_usd

  # Conta inteira (sem cost_filter): o teto do ADR-0013 é da conta, não de um ambiente.
  time_period_start = "2026-11-01_00:00"

  # Gasto real: aviso em 50% e 80%, estouro em 100%.
  notification {
    notification_type          = "ACTUAL"
    comparison_operator        = "GREATER_THAN"
    threshold                  = 50
    threshold_type             = "PERCENTAGE"
    subscriber_email_addresses = [var.email_alerta]
  }

  notification {
    notification_type          = "ACTUAL"
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    subscriber_email_addresses = [var.email_alerta]
  }

  notification {
    notification_type          = "ACTUAL"
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    subscriber_email_addresses = [var.email_alerta]
  }

  # Previsão do mês: avisa antes de estourar.
  notification {
    notification_type          = "FORECASTED"
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    subscriber_email_addresses = [var.email_alerta]
  }
}

output "teto_mensal_usd" {
  description = "Limite do orçamento em USD na cotação informada"
  value       = local.teto_mensal_usd
}
