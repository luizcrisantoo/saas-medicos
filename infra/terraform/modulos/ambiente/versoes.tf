# Módulo "ambiente": tudo que um ambiente (dev, homolog, prod) do SaaS precisa na AWS sa-east-1
# (ADR-0012, ADR-0014). O provider "aws" vem da raiz que chama o módulo (herança do provider
# padrão); o módulo não declara provider nem alias, para o plan sem credenciais do aceite
# (acceptance/F10) continuar cobrindo tudo com um único override.

terraform {
  required_version = ">= 1.9.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.80"
    }
  }
}
