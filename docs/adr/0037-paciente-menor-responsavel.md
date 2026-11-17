# ADR-0037: Paciente menor de idade com cadastro próprio ligado a responsável

Status: Aceito (Luiz, 2026-11-17)

## Contexto
Red Team T-20 (docs/agents/red-team-t-fase1-arquitetura-r2.md): menor encaminhado com o "CPF do responsável" fundia o cadastro do filho no da mãe. A decisão de produto ficou com o Luiz (docs/fase1-resumo.md, seção 4).

## Decisão
O menor é um Paciente próprio, identificado por nome e data de nascimento, CPF opcional. Ele é ligado a um ou mais responsáveis (outro Paciente) por um vínculo explícito. Link e código de uso único do caso do menor vão para o WhatsApp do responsável. Nunca há fusão de cadastro entre menor e responsável, nem por CPF, nem por telefone (ADR-0036).

## Alternativas descartadas
Excluir menores do piloto (ortopedia atende muitas crianças).

## Consequências
Entidade nova de vínculo responsável-menor (glossário). O CPF informado como "do responsável" é gravado no responsável, nunca no menor. Sessão do responsável vale para o caso do menor (ADR-0030, sessão por caso). Gate T-20 da Fase 2 implementado por esta regra.
