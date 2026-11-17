# Rede privada do ambiente. Sem internet gateway e sem NAT: o banco só é alcançável de dentro da
# VPC, pelo grupo de segurança da aplicação. A computação da aplicação (P3) entra nesta VPC quando
# for decidida.

resource "aws_vpc" "esta" {
  cidr_block           = var.cidr_vpc
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = local.nome }
}

resource "aws_subnet" "privada" {
  count = length(var.zonas)

  vpc_id                  = aws_vpc.esta.id
  cidr_block              = cidrsubnet(var.cidr_vpc, 8, count.index)
  availability_zone       = var.zonas[count.index]
  map_public_ip_on_launch = false

  tags = { Name = "${local.nome}-privada-${count.index}" }
}

resource "aws_db_subnet_group" "banco" {
  name        = "${local.nome}-banco"
  description = "Sub-redes privadas do RDS (${var.ambiente})"
  subnet_ids  = aws_subnet.privada[*].id
}

# Grupo da aplicação: sem regra própria; só serve de origem permitida no grupo do banco.
resource "aws_security_group" "aplicacao" {
  name        = "${local.nome}-aplicacao"
  description = "Processos da aplicacao (web e jobs) que falam com o banco"
  vpc_id      = aws_vpc.esta.id

  tags = { Name = "${local.nome}-aplicacao" }
}

resource "aws_security_group" "banco" {
  name        = "${local.nome}-banco"
  description = "RDS PostgreSQL: so 5432 vindo do grupo da aplicacao"
  vpc_id      = aws_vpc.esta.id

  tags = { Name = "${local.nome}-banco" }
}

resource "aws_vpc_security_group_ingress_rule" "banco_da_aplicacao" {
  security_group_id            = aws_security_group.banco.id
  description                  = "PostgreSQL a partir da aplicacao"
  referenced_security_group_id = aws_security_group.aplicacao.id
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
}

# Saída da aplicação para o banco (a saída para a internet é decisão da computação, P3).
resource "aws_vpc_security_group_egress_rule" "aplicacao_para_banco" {
  security_group_id            = aws_security_group.aplicacao.id
  description                  = "PostgreSQL no grupo do banco"
  referenced_security_group_id = aws_security_group.banco.id
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
}
