# Raiz do ambiente dev (ADR-0014). Planeja sem credenciais: nenhum data source que chame a API da
# AWS, provider padrão sem alias e sem assume_role (spec, seção 3.6). Backend: local por padrão; o
# remoto (S3 + bloqueio) entra por `terraform init -backend-config` quando a conta existir (README).

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
      Ambiente = "dev"
      Gerencia = "terraform"
    }
  }
}

module "ambiente" {
  source = "../../modulos/ambiente"

  ambiente     = "dev"
  prefixo      = var.prefixo
  email_alerta = var.email_alerta

  cidr_vpc = "10.10.0.0/16"

  # Mínimo que cumpre o spec (ADR-0013): menor classe, single-AZ, PITR curto, sem proteção
  # contra exclusão (ambiente recriado com frequência).
  rds_classe               = "db.t4g.micro"
  rds_multi_az             = false
  rds_retencao_backup_dias = 1
  rds_protecao_exclusao    = false
  retencao_logs_dias       = 14

  mfa_configuration = var.mfa_configuration
}
