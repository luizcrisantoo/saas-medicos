# Cognito (F10.7; ADR-0007): user pool da equipe (ADMIN, MEDICO, RECEPCAO) com TOTP habilitado,
# senha de 12 ou mais caracteres (ASVS nível 2), e-mail como usuário e sem autocadastro (a equipe é
# convidada pelo ADMIN; o paciente não tem conta aqui, usa o código do link, ADR-0007).
#
# MFA ON ou OPTIONAL é a BLOQUEANTE B2 (spec, seção 7): o padrão OPTIONAL deixa as três opções de B2
# abertas; a decisão do Negócio troca var.mfa_configuration (e pode trazer um segundo pool ou um
# gatilho de pré-geração de token, que entram em F11).

resource "aws_cognito_user_pool" "equipe" {
  name = "${local.nome}-equipe"

  deletion_protection = local.prod ? "ACTIVE" : "INACTIVE"

  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  username_configuration {
    case_sensitive = false
  }

  mfa_configuration = var.mfa_configuration

  software_token_mfa_configuration {
    enabled = true
  }

  password_policy {
    minimum_length                   = 12
    require_lowercase                = true
    require_uppercase                = true
    require_numbers                  = true
    require_symbols                  = true
    temporary_password_validity_days = 3
  }

  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  admin_create_user_config {
    allow_admin_create_user_only = true
  }

  user_attribute_update_settings {
    attributes_require_verification_before_update = ["email"]
  }

  email_configuration {
    email_sending_account = "COGNITO_DEFAULT"
  }
}

# Cliente público (SPA/mobile): sem segredo, só SRP e refresh; sem fluxos legados com senha em claro.
resource "aws_cognito_user_pool_client" "web" {
  name         = "${local.nome}-web"
  user_pool_id = aws_cognito_user_pool.equipe.id

  generate_secret = false

  explicit_auth_flows = [
    "ALLOW_USER_SRP_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
  ]

  supported_identity_providers = ["COGNITO"]

  access_token_validity  = var.access_token_minutos
  id_token_validity      = var.access_token_minutos
  refresh_token_validity = var.refresh_token_horas

  token_validity_units {
    access_token  = "minutes"
    id_token      = "minutes"
    refresh_token = "hours"
  }

  enable_token_revocation       = true
  prevent_user_existence_errors = "ENABLED"

  read_attributes  = ["email", "email_verified"]
  write_attributes = ["email"]
}
