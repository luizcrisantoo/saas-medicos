# shellcheck shell=bash
# F6: autenticacao Cognito como resource server (JWKS local) e sessao de equipe no banco. MFA: F11 (BLOQUEANTE B2).
TITULO="Autenticacao Cognito (resource server) e sessao de equipe verificavel no banco"
aceite() {
  declara F6.1 "aplicacao sobe com o ambiente do contrato (sem credencial de jobs) e /actuator/health responde 200"
  declara F6.2 "access token valido (RS256, iss, client_id permitido, token_use=access, exp) abre sessao: cookie SESSAO HttpOnly/Secure/SameSite com o token da tabela sessao; GET /api/sessao devolve EQUIPE"
  declara F6.3 "token com assinatura errada, kid desconhecido, iss ou client_id errados, expirado, token_use=id, alg none, HS256, malformado, sem client_id, usuario inexistente ou inativo: recusado e nenhuma sessao criada"
  declara F6.4 "cookie ausente, desconhecido ou nao hexadecimal: 401 sem detalhe interno"
  declara F6.5 "logout encerra a sessao no banco e o cookie deixa de valer"
  declara F6.6 "nenhum JWT nem cookie nos logs da aplicacao e do PostgreSQL"
  declara F6.7 "sessao aberta pela credencial saas_auth; consultas da web por saas_app"
  app_prepara f6 "$ACC/F6/semente-f6.sql" || return 0
  verde F6.1
  local out; out=$(python3 "$ACC/F6/teste_f6.py" 2>&1); echo "$out" >>"$LOGF"
  agrega_py "$out"
  pendentes_vermelhos "teste nao produziu resultado (ver $LOGF)"
}
