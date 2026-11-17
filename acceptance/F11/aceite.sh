# shellcheck shell=bash
# F11: MFA obrigatorio para ADMIN e MEDICO (ADR-0006, ADR-0007, E-10). BLOQUEADA: decisao B2 do spec
# (como o token do Cognito prova MFA). O Arquiteto escreve os testes quando B2 for decidida; ate la, VERMELHO.
TITULO="MFA obrigatorio para ADMIN e MEDICO (BLOQUEADA: B2)"
aceite() {
  declara F11.1 "token de ADMIN ou MEDICO sem prova de MFA e recusado e nenhuma sessao e criada"
  declara F11.2 "token de ADMIN ou MEDICO com prova de MFA abre sessao; RECEPCAO continua sem exigencia"
  declara F11.3 "E-10 no banco: sessao_equipe_abre recebe e grava o fator e recusa ADMIN e MEDICO sem MFA"
  pendentes_vermelhos "BLOQUEADO: decisao B2 pendente (docs/fase2/spec.md, secao 7)"
}
