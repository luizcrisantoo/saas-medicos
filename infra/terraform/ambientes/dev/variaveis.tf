# Contrato do runner (spec, seção 3.6): toda raiz aceita -var cotacao_usd_brl e -var email_alerta;
# o resto tem padrão.

variable "cotacao_usd_brl" {
  description = "R$ por US$ usado no orçamento da conta (raiz conta/). Aceita aqui pelo contrato das raízes; este ambiente não a consome."
  type        = number
  default     = 5.0

  validation {
    condition     = var.cotacao_usd_brl > 0
    error_message = "cotacao_usd_brl deve ser positiva."
  }
}

variable "email_alerta" {
  description = "E-mail que recebe os alarmes do ambiente (SNS)."
  type        = string
}

variable "teto_mensal_brl" {
  description = "Teto mensal do piloto em R$ (ADR-0013). Aplicado no orçamento da raiz conta/; aqui só documenta o limite que dimensionou os recursos."
  type        = number
  default     = 800
}

variable "prefixo" {
  description = "Prefixo dos nomes de recurso (nome de bucket é global; troque se o padrão estiver tomado)."
  type        = string
  default     = "saas-agenda"
}

variable "mfa_configuration" {
  description = "MFA do user pool (ON ou OPTIONAL). Valor final depende da BLOQUEANTE B2."
  type        = string
  default     = "OPTIONAL"
}
