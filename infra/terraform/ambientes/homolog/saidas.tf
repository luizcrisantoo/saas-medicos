output "ambiente" {
  description = "Valores que a aplicação e o operador usam (nenhum sensível)"
  value = {
    rds_endpoint             = module.ambiente.rds_endpoint
    rds_identifier           = module.ambiente.rds_identifier
    bucket_anexos            = module.ambiente.bucket_anexos
    kms_anexos_key_id        = module.ambiente.kms_anexos_key_id
    segredos_arns            = module.ambiente.segredos_arns
    cognito_issuer           = module.ambiente.cognito_issuer
    cognito_user_pool_id     = module.ambiente.cognito_user_pool_id
    cognito_client_id_web    = module.ambiente.cognito_client_id_web
    vpc_id                   = module.ambiente.vpc_id
    subnets_privadas         = module.ambiente.subnets_privadas
    security_group_aplicacao = module.ambiente.security_group_aplicacao
    politica_iam_web_arn     = module.ambiente.politica_iam_web_arn
    politica_iam_jobs_arn    = module.ambiente.politica_iam_jobs_arn
    sns_alertas_arn          = module.ambiente.sns_alertas_arn
  }
}
