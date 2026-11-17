# shellcheck shell=bash
# F8: storage S3 (SSE-KMS, URL assinada curta, tipo e tamanho) testavel sem nuvem, e auditoria do acesso ao anexo.
TITULO="Storage S3 com SSE-KMS e URL assinada curta, validacao de tipo e tamanho, auditoria de acesso a dado de saude"
aceite() {
  declara F8.1 "upload valido: anexo registrado (PENDENTE) e URL PUT SigV4 de ate 5 min, sa-east-1, no bucket do ambiente, na chave opaca, com SSE-KMS assinado"
  declara F8.2 "tipo fora de PDF, JPEG e PNG recusado sem registro nem URL"
  declara F8.3 "tamanho acima de 20 MiB, zero ou negativo recusado; limites aceitos"
  declara F8.4 "upload em encaminhamento que o ator nao ve ou sem sessao recusado"
  declara F8.5 "download de anexo LIMPO devolve URL GET assinada de ate 5 min para a chave do anexo"
  declara F8.6 "anexo PENDENTE, INFECTADO, alheio ou sem sessao: recusado sem URL"
  declara F8.7 "cada download concedido grava um EventoAuditoria do anexo"
  declara F8.8 "se a auditoria falhar, nenhuma URL e entregue (acesso sem registro nao acontece)"
  declara F8.9 "nenhuma URL assinada no log da aplicacao"
  app_prepara f8 "$ACC/F8/semente-f8.sql" || return 0
  local out; out=$(python3 "$ACC/F8/teste_f8.py" 2>&1); echo "$out" >>"$LOGF"
  agrega_py "$out"
  pendentes_vermelhos "teste nao produziu resultado (ver $LOGF)"
}
