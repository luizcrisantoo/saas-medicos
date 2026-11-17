# Raiz do ambiente prod (ADR-0014: único ambiente com dado real de paciente). Planeja sem
# credenciais: nenhum data source que chame a API da AWS, provider padrão sem alias e sem
# assume_role (spec, seção 3.6). Backend: local por padrão; o remoto entra por `terraform init
# -backend-config` quando a conta existir (README).

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
      Ambiente = "prod"
      Gerencia = "terraform"
    }
  }
}

module "ambiente" {
  source = "../../modulos/ambiente"

  ambiente     = "prod"
  prefixo      = var.prefixo
  email_alerta = var.email_alerta

  cidr_vpc = "10.30.0.0/16"

  # Piloto (ADR-0013): classe pequena, single-AZ (Multi-AZ dobra o custo do banco; liga por variável
  # quando o piloto exigir), PITR de 35 dias, proteção contra exclusão (o módulo força true em prod),
  # logs por 90 dias.
  rds_classe               = "db.t4g.small"
  rds_multi_az             = var.rds_multi_az
  rds_retencao_backup_dias = 35
  rds_protecao_exclusao    = true
  retencao_logs_dias       = 90

  mfa_configuration = var.mfa_configuration
}
