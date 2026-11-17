# shellcheck shell=bash
# F10: Terraform AWS sa-east-1, 3 ambientes, validado e planejado sem credenciais (nada e provisionado).
TITULO="Terraform AWS sa-east-1: 3 ambientes, RDS com PITR, S3+KMS, Secrets Manager, Cognito com MFA, alarmes e orcamento"
aceite() {
  declara F10.1 "terraform fmt -check e validate passam em infra/terraform/ambientes/{dev,homolog,prod} (e conta, se existir)"
  declara F10.2 "terraform plan roda sem credenciais AWS reais (override de aceite) em todas as raizes, com duas cotacoes"
  declara F10.3 "os tres ambientes usam a regiao sa-east-1"
  declara F10.4 "RDS PostgreSQL 16 por ambiente: cifrado, privado, PITR, TLS obrigatorio (rds.force_ssl), logs exportados, protecao contra exclusao em prod, senha fora do codigo"
  declara F10.5 "S3 de anexos por ambiente: SSE-KMS com chave propria rotacionada, bloqueio publico total e politica que exige TLS e SSE-KMS"
  declara F10.6 "Secrets Manager: segredos separados de saas_app, saas_jobs, saas_auth e saas_migracao por ambiente, cifrados com KMS, sem valor no codigo"
  declara F10.7 "Cognito por ambiente: MFA TOTP habilitado, senha com 12+ caracteres, access token de ate 60 min, revogacao de token"
  declara F10.8 "alarmes do CloudWatch para as linhas ALERTA_DDL_SAAS e ALERTA_PREPARO_VOLUME do log do banco"
  declara F10.9 "ambientes isolados: buckets e instancias RDS com nomes distintos"
  declara F10.10 "orcamento mensal da conta coerente com o teto de R$ 800 (limite em USD = teto / cotacao), alertas real e previsto"
  local T="$RAIZ/infra/terraform"
  [ -d "$T/ambientes/dev" ] && [ -d "$T/ambientes/homolog" ] && [ -d "$T/ambientes/prod" ] || { pendentes_vermelhos "pre-requisito ausente: infra/terraform/ambientes/{dev,homolog,prod}"; return 0; }
  local C="$TMPA/F10-tf"; rm -rf "$C"; mkdir -p "$C"; cp -r "$T" "$C/terraform"
  local P="$TMPA/F10-planos"; rm -rf "$P"; mkdir -p "$P"
  export TF_PLUGIN_CACHE_DIR="$TMPA/tf-cache"; mkdir -p "$TF_PLUGIN_CACHE_DIR"
  export TF_IN_AUTOMATION=1 AWS_ACCESS_KEY_ID=AKIAACEITEFASE2TESTE AWS_SECRET_ACCESS_KEY=aceite-falso AWS_EC2_METADATA_DISABLED=true
  unset AWS_PROFILE AWS_SESSION_TOKEN
  local raizes="ambientes/dev ambientes/homolog ambientes/prod"; [ -d "$T/conta" ] && raizes="$raizes conta"
  local okfmt=1 okval=1 okplan=1 r cot EMAIL="alertas-orcamento@exemplo.invalid"
  terraform fmt -check -recursive "$T" >>"$LOGF" 2>&1 || okfmt=0
  for r in $raizes; do
    cat >"$C/terraform/$r/zz_aceite_override.tf" <<'TF'
# Override de aceite (acceptance/F10): planejar sem credenciais reais e sem estado remoto.
provider "aws" {
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
}
terraform {
  backend "local" {}
}
TF
    ( cd "$C/terraform/$r" && terraform init -input=false -no-color >>"$LOGF" 2>&1 && terraform validate -no-color >>"$LOGF" 2>&1 ) || { okval=0; continue; }
    for cot in 5.0 6.25; do
      ( cd "$C/terraform/$r" && terraform plan -input=false -no-color -lock=false -refresh=false -out=plano.bin \
          -var "cotacao_usd_brl=$cot" -var "email_alerta=$EMAIL" >>"$LOGF" 2>&1 \
        && terraform show -json plano.bin >"$P/${r//\//_}-$cot.json" ) || okplan=0
    done
  done
  [ $okfmt = 1 ] && [ $okval = 1 ] && verde F10.1 || vermelho F10.1 "fmt=$okfmt validate=$okval (ver $LOGF)"
  [ $okplan = 1 ] && [ $okval = 1 ] && verde F10.2 || vermelho F10.2 "plan falhou em alguma raiz (ver $LOGF)"
  local out; out=$(python3 "$ACC/F10/confere_plano.py" "$P" "$T" 5.0 6.25 "$EMAIL" 2>&1); echo "$out" >>"$LOGF"
  agrega_py "$out"
  rm -rf "$C"
  pendentes_vermelhos "sem plano para conferir (ver $LOGF)"
}
