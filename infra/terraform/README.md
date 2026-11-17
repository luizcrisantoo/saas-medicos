# Infraestrutura AWS (sa-east-1) em Terraform

Infra como código da Fase 2 (F10): três ambientes isolados por nome (ADR-0014) na região de São Paulo
(ADR-0012) e o orçamento da conta (ADR-0013). Nada aqui é aplicado pela Operação: `terraform apply`
depende da conta AWS do Luiz e fica fora do escopo. O que o repositório garante é `fmt`, `validate` e
`plan` sem credenciais, conferidos por `acceptance/run.sh F10`.

## Raízes

| Raiz | O que cria |
|---|---|
| `ambientes/dev` | Um ambiente completo (módulo `modulos/ambiente`): classe mínima, PITR de 1 dia, sem proteção contra exclusão |
| `ambientes/homolog` | Mesmo desenho de prod, menor custo; só dado fictício (ADR-0014) |
| `ambientes/prod` | PITR de 35 dias, `deletion_protection` forçado pelo módulo, `db.t4g.small`, Multi-AZ por variável (desligado) |
| `conta` | `aws_budgets_budget` mensal da conta inteira, limite em USD derivado do teto em R$ |

O módulo `modulos/ambiente` cria, por ambiente: VPC sem internet com duas sub-redes privadas e grupos
de segurança (banco só recebe 5432 do grupo da aplicação); três chaves KMS com rotação anual (banco,
anexos, segredos); RDS PostgreSQL 16 cifrado, privado, com `rds.force_ssl=1`, backups automáticos
(PITR), log exportado ao CloudWatch e senha mestra gerada pelo RDS; bucket de anexos com SSE-KMS,
bloqueio público, versionamento e política que recusa acesso sem TLS e gravação sem SSE-KMS com a
chave do bucket; quatro segredos vazios (`saas_app`, `saas_jobs`, `saas_auth`, `saas_migracao`);
user pool do Cognito com TOTP, senha de 12+ caracteres e cliente web sem segredo com access token de
60 min e revogação; filtros de métrica e alarmes para `ALERTA_DDL_SAAS` e `ALERTA_PREPARO_VOLUME` com
e-mail pelo SNS; duas políticas IAM (web e jobs) de menor privilégio, sem papel ainda.

Nomes seguem `<prefixo>-<ambiente>` (`saas-agenda-dev`, `saas-agenda-dev-anexos`,
`saas-agenda/dev/saas_app`), o que torna os recursos distintos entre ambientes (F10.9).

## Variáveis

Todas as raízes aceitam `-var cotacao_usd_brl=<R$ por US$>` e `-var email_alerta=<e-mail>` (contrato
do runner, spec 3.6). O resto tem padrão.

| Variável | Raiz | Padrão | Uso |
|---|---|---|---|
| `cotacao_usd_brl` | todas | 5.0 | Só `conta/` a consome (limite do orçamento). Nos ambientes é aceita pelo contrato e não muda nada |
| `email_alerta` | todas | (obrigatória) | Alarmes do SNS nos ambientes; alertas do orçamento em `conta/` |
| `teto_mensal_brl` | todas | 800 | ADR-0013. Em `conta/` vira `limit_amount = floor(teto / cotação, 2 casas)` |
| `prefixo` | ambientes | `saas-agenda` | Nome de bucket é global: se estiver tomado, troque aqui (ex.: `saas-agenda-<sigla>`) |
| `mfa_configuration` | ambientes | `OPTIONAL` | `ON` ou `OPTIONAL`. Ver B2 abaixo |
| `rds_multi_az` | prod | `false` | Liga Multi-AZ quando o piloto exigir (dobra o custo do banco) |

Variáveis internas do módulo (classe do RDS, retenções, CIDR, zonas) são fixadas em cada raiz.

## Planejar sem credenciais

```sh
export PATH=$PWD/acceptance/.bin:$PATH        # terraform 1.9.8 fixado pelo aceite
acceptance/run.sh F10                          # fmt, validate, plan das 4 raízes com cotações 5.0 e 6.25
```

À mão, em qualquer raiz: copie a raiz para um diretório temporário, acrescente um arquivo
`*_override.tf` com `provider "aws" { skip_credentials_validation = true
skip_requesting_account_id = true skip_metadata_api_check = true }` e `terraform { backend "local" {} }`,
exporte `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` falsas e `AWS_EC2_METADATA_DISABLED=true`, e rode
`terraform init && terraform plan -refresh=false -var cotacao_usd_brl=5.0 -var email_alerta=x@exemplo.invalid`.
Para isso funcionar o código não usa data source que chame a API (`aws_caller_identity`,
`aws_availability_zones`, `aws_region`), `assume_role`, provider com alias nem `timestamp()` em nome;
as zonas de disponibilidade são fixas por variável (`sa-east-1a`, `sa-east-1b`).

Os `.terraform.lock.hcl` estão versionados (provider `hashicorp/aws` 5.x pinado); `.terraform/`,
estados e planos estão no `.gitignore`.

## Com a conta AWS (fora da Operação)

1. Escolher o backend remoto (bucket de estado + bloqueio) e passar por `terraform init -backend-config`;
   o código não fixa backend.
2. `terraform apply` em `conta/` com a cotação do dia; depois em cada ambiente.
3. Confirmar as assinaturas de e-mail (SNS e Budgets mandam um e-mail de confirmação).
4. Rodar `infra/db/bootstrap.sql` no RDS com a senha mestra (segredo gerado pelo RDS, saída
   `rds_senha_mestra_secret_arn`) e gravar nos quatro segredos o JSON com usuário, senha, host, porta e
   banco de cada papel. O Terraform não grava nem lê esses valores.
5. Levar para a aplicação as saídas `bucket_anexos` (`SAAS_S3_BUCKET`), `kms_anexos_key_id`
   (`SAAS_S3_KMS_KEY_ID`), `cognito_issuer` (`SAAS_AUTH_ISSUER`) e `cognito_client_id_web`.

## O que fica fora (de propósito)

- `terraform apply` e qualquer chamada à conta (spec, seção 8).
- Computação da aplicação (ECS, App Runner, EC2, Lightsail): pendência P3, decidir antes do primeiro
  deploy. O módulo já deixa o grupo de segurança `aplicacao`, as sub-redes privadas e as políticas IAM
  `web` e `jobs` para a computação se encaixar; falta o papel (role) que recebe as políticas e a saída
  para a internet (NAT ou endpoints), que dependem da escolha.
- Conta única com nomes distintos ou uma conta por ambiente: pendência P5. O código funciona nos dois
  casos (cada raiz tem estado e provider próprios).
- CloudTrail, alerta de login em massa, WAF, varredura de vírus dos anexos e retenção dos anexos (P7):
  operação antes do lançamento.
- Chave KMS da cifra de aplicação (ADR-0026, item 1) e da HMAC do CPF: entram quando o módulo que as usa
  existir no código.

## Decisões tomadas aqui (o spec não decidia)

- **MFA `OPTIONAL` por padrão.** A BLOQUEANTE B2 (ON para todos, pools separados ou claim própria por
  gatilho) é do Negócio. `OPTIONAL` com TOTP habilitado cumpre F10.7 sem fechar nenhuma das três opções;
  `OFF` é recusado pela validação da variável. B2 define o valor final e o que mais F11 precisa.
- **Senha mestra do RDS gerida pelo RDS** (`manage_master_user_password`, cifrada com a chave dos
  segredos): zero senha no código ou no estado em claro. Os quatro segredos dos papéis nascem vazios.
- **Política das chaves KMS é a padrão da AWS.** Uma política própria precisa do principal raiz da conta
  (`arn:aws:iam::<conta>:root`), e o plan de aceite não tem id de conta. Consequência: grupo de logs e
  tópico SNS ficam com a cifra padrão do serviço (CloudWatch Alarms não publica em tópico cifrado com
  chave gerenciada pela AWS, e uma chave própria exigiria a política acima). O log do PostgreSQL não
  traz contato, token ou código (ADR-0026, bootstrap.sql), então não há dado de saúde nesses dois lugares.
- **Bucket exige o cabeçalho SSE-KMS com a chave do bucket em todo PutObject** (três Deny: sem
  cabeçalho, algoritmo diferente de `aws:kms`, chave diferente). A aplicação já assina o upload com
  SSE-KMS (F8). Objeto único por dono (`BucketOwnerEnforced`), versionamento ligado, multipart
  incompleto descartado em 7 dias.
- **Rede sem internet.** VPC só com sub-redes privadas, sem IGW nem NAT; o banco só aceita 5432 do grupo
  `aplicacao`. Saída para a internet é decisão de P3.
- **`engine_version = "16"`** (só a maior) com `auto_minor_version_upgrade`: o RDS escolhe a menor
  vigente e não quebra quando a AWS aposenta uma menor fixada.
- **Parameter group** além de `rds.force_ssl`: `log_connections` e `log_disconnections` (quem conectou
  quando, para investigar um `ALERTA_DDL_SAAS`; nenhum texto de comando no log).
- **Cognito sem autocadastro** (`allow_admin_create_user_only`): a equipe é convidada pelo ADMIN; o
  paciente não tem conta (ADR-0007). Cliente web sem segredo, só `USER_SRP_AUTH` e `REFRESH_TOKEN_AUTH`
  (sem `USER_PASSWORD_AUTH`), refresh de 12 h, access e id token de 60 min, revogação ligada,
  `prevent_user_existence_errors`.
- **Alarmes:** métrica por marcador (`Sum`, 60 s, limiar 1, `notBreaching` quando não há linha), e-mail
  pelo SNS. Padrão do filtro é o termo literal entre aspas.
- **Orçamento:** limite arredondado para baixo com duas casas (`floor(x*100)/100`), alertas de gasto
  real em 50, 80 e 100% e previsto em 100%, conta inteira (sem `cost_filter`), período a partir de
  2026-11-01. Reaplicar `conta/` quando a cotação mudar muito.
- **Políticas IAM `web` e `jobs`** separadas (E-09, ADR-0024): web lê e grava anexos e lê os segredos
  `saas_app` e `saas_auth`; jobs só lê `saas_jobs`. Sem papel por enquanto (P3).

## Estimativa grosseira de custo (sa-east-1, por mês, antes de impostos)

[SUPOSIÇÃO] Preços de lista lidos de memória, não conferidos nesta rodada; conferir na calculadora da
AWS antes do apply.

| Item | dev | homolog | prod |
|---|---|---|---|
| RDS db.t4g.micro / small, single-AZ | ~US$ 16 | ~US$ 16 | ~US$ 32 |
| gp3 20 GB + backups dentro da franquia | ~US$ 3 | ~US$ 3 | ~US$ 3 a 6 |
| 3 chaves KMS (US$ 1 cada) + requisições | ~US$ 3 | ~US$ 3 | ~US$ 3 |
| Secrets Manager (4 + 1 do RDS, US$ 0,40 cada) | ~US$ 2 | ~US$ 2 | ~US$ 2 |
| S3, CloudWatch, SNS, Cognito (até 10.000 MAU grátis) | ~US$ 1 | ~US$ 1 | ~US$ 2 |
| **Total** | **~US$ 25** | **~US$ 25** | **~US$ 45** |

Soma aproximada de US$ 95/mês (~R$ 475 a R$ 600 conforme a cotação) sem computação da aplicação (P3)
nem WhatsApp, que também entram no teto de R$ 800. Dev pode ficar desligado (`terraform destroy`)
quando não estiver em uso; Multi-AZ em prod dobra a linha do RDS.
