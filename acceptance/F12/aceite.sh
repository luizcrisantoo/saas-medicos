# shellcheck shell=bash
# F12: paciente menor com cadastro proprio ligado a responsavel (ADR-0037). BLOQUEADA: decisao B1 do spec
# (nome da entidade no glossario, dados pedidos no encaminhamento do menor, criterio de menoridade).
TITULO="Menor com cadastro proprio ligado a responsavel, ADR-0037 (BLOQUEADA: B1)"
aceite() {
  declara F12.1 "menor nasce como Paciente proprio, ligado a um ou mais responsaveis por vinculo explicito"
  declara F12.2 "CPF informado como do responsavel e gravado no responsavel, nunca no menor"
  declara F12.3 "link e codigo do caso do menor vao ao WhatsApp do responsavel"
  declara F12.4 "sessao do responsavel vale para o caso do menor e so para ele; nunca ha fusao de cadastro entre menor e responsavel"
  pendentes_vermelhos "BLOQUEADO: decisao B1 pendente (docs/fase2/spec.md, secao 7)"
}
