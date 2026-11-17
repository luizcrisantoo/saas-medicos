# Contrato do runner (spec, seção 3.6): -var cotacao_usd_brl e -var email_alerta; o resto com padrão.

variable "cotacao_usd_brl" {
  description = "R$ por US$ no dia do apply (o orçamento da AWS só aceita USD). Reaplicar quando a cotação mudar muito."
  type        = number
  default     = 5.0

  validation {
    condition     = var.cotacao_usd_brl > 0
    error_message = "cotacao_usd_brl deve ser positiva."
  }
}

variable "email_alerta" {
  description = "E-mail que recebe os alertas do orçamento."
  type        = string

  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.email_alerta))
    error_message = "email_alerta precisa ser um endereço de e-mail."
  }
}

variable "teto_mensal_brl" {
  description = "Teto mensal do piloto em R$, infraestrutura e WhatsApp somados (ADR-0013)."
  type        = number
  default     = 800

  validation {
    condition     = var.teto_mensal_brl > 0
    error_message = "teto_mensal_brl deve ser positivo."
  }
}
