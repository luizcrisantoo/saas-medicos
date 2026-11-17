variable "ambiente" {
  description = "Nome do ambiente (ADR-0014). Entra em todo nome de recurso, o que garante nomes distintos entre ambientes (F10.9)."
  type        = string

  validation {
    condition     = contains(["dev", "homolog", "prod"], var.ambiente)
    error_message = "ambiente deve ser dev, homolog ou prod."
  }
}

variable "prefixo" {
  description = "Prefixo dos nomes de recurso. Nome de bucket S3 é global: se o padrão já estiver tomado, troque aqui (ex.: saas-agenda-<sigla-da-conta>)."
  type        = string
  default     = "saas-agenda"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,30}$", var.prefixo))
    error_message = "prefixo: minúsculas, dígitos e hífen, começando por letra, até 31 caracteres."
  }
}

variable "regiao" {
  description = "Região da AWS. Fixa em sa-east-1 (ADR-0012); usada só em condições de política (kms:ViaService)."
  type        = string
  default     = "sa-east-1"
}

variable "email_alerta" {
  description = "E-mail que recebe os alarmes do CloudWatch (ALERTA_DDL_SAAS, ALERTA_PREPARO_VOLUME)."
  type        = string

  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.email_alerta))
    error_message = "email_alerta precisa ser um endereço de e-mail."
  }
}

variable "cidr_vpc" {
  description = "CIDR da VPC do ambiente. Sem gateway de internet: as sub-redes são privadas."
  type        = string
  default     = "10.10.0.0/16"
}

variable "zonas" {
  description = "Zonas de disponibilidade das sub-redes privadas (duas, exigência do grupo de sub-redes do RDS). Fixas por variável porque o plan de aceite não consulta a API da AWS."
  type        = list(string)
  default     = ["sa-east-1a", "sa-east-1b"]

  validation {
    condition     = length(var.zonas) >= 2
    error_message = "zonas precisa de pelo menos duas zonas de disponibilidade."
  }
}

variable "rds_classe" {
  description = "Classe da instância RDS. db.t4g.micro é o mínimo que cabe no teto (ADR-0013)."
  type        = string
  default     = "db.t4g.micro"
}

variable "rds_armazenamento_gb" {
  description = "Armazenamento inicial do RDS em GB (gp3, mínimo 20)."
  type        = number
  default     = 20
}

variable "rds_armazenamento_max_gb" {
  description = "Teto do crescimento automático do armazenamento (0 desliga)."
  type        = number
  default     = 50
}

variable "rds_versao" {
  description = "Versão do PostgreSQL no RDS. Só a maior (16): o RDS escolhe a menor mais recente e auto_minor_version_upgrade acompanha."
  type        = string
  default     = "16"

  validation {
    condition     = startswith(var.rds_versao, "16")
    error_message = "O modelo v2 é PostgreSQL 16 (ADR-0012)."
  }
}

variable "rds_multi_az" {
  description = "Multi-AZ no RDS. Desligado por padrão em todos os ambientes (dobra o custo do banco, ADR-0013)."
  type        = bool
  default     = false
}

variable "rds_retencao_backup_dias" {
  description = "Dias de retenção dos backups automáticos (PITR). Mínimo 1."
  type        = number
  default     = 7

  validation {
    condition     = var.rds_retencao_backup_dias >= 1 && var.rds_retencao_backup_dias <= 35
    error_message = "rds_retencao_backup_dias entre 1 e 35."
  }
}

variable "rds_protecao_exclusao" {
  description = "deletion_protection do RDS. Obrigatório true em prod (F10.4)."
  type        = bool
  default     = true
}

variable "retencao_logs_dias" {
  description = "Retenção, em dias, do grupo de logs do PostgreSQL no CloudWatch."
  type        = number
  default     = 30
}

variable "mfa_configuration" {
  description = "MFA do user pool do Cognito: ON (todo usuário) ou OPTIONAL. O padrão OPTIONAL não fecha nenhuma opção da BLOQUEANTE B2 (spec, seção 7), que define o valor final."
  type        = string
  default     = "OPTIONAL"

  validation {
    condition     = contains(["ON", "OPTIONAL"], var.mfa_configuration)
    error_message = "mfa_configuration deve ser ON ou OPTIONAL (OFF viola o ADR-0007)."
  }
}

variable "access_token_minutos" {
  description = "Validade do access token do Cognito, em minutos (até 60, F10.7)."
  type        = number
  default     = 60

  validation {
    condition     = var.access_token_minutos >= 5 && var.access_token_minutos <= 60
    error_message = "access_token_minutos entre 5 e 60."
  }
}

variable "refresh_token_horas" {
  description = "Validade do refresh token do Cognito, em horas (um turno de trabalho por padrão)."
  type        = number
  default     = 12

  validation {
    condition     = var.refresh_token_horas >= 1 && var.refresh_token_horas <= 24
    error_message = "refresh_token_horas entre 1 e 24."
  }
}
