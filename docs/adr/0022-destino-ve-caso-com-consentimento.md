# ADR-0022: Clínica destino só vê o caso com consentimento COMPARTILHAR_CASO ativo

Status: Aceito na revisão da Fase 1, sujeito ao Avaliador
Data: 2026-11-10
Tarefa: t-fase1-arquitetura

## Contexto
Regra inegociável: consentimento explícito do paciente para compartilhar o caso com a clínica destino; acesso mínimo.

## Decisão
A política `encaminhamento_destino` (e por composição histórico, anexos e contrarreferência) exige consentimento `COMPARTILHAR_CASO` não revogado para aquele encaminhamento e aquela clínica. Revogar tira a visibilidade na hora, sem listener.

## Alternativas descartadas
- Visibilidade da clínica destino só por estar escolhida: contraria a regra de consentimento.
- Consentimento genérico por paciente: não é "específico e destacado" para a finalidade.

## Consequências
- O paciente precisa aceitar o consentimento na transição para SOLICITADO (máquina de estados, T3).
- Hipótese do art. 11, II, f da LGPD (tutela da saúde) como base alternativa fica para o advogado.

## Fontes
- docs/briefing.md: Regras inegociáveis, LGPD
- docs/agents/pesquisador-t-fase1-arquitetura.md: LGPD art. 11
- docs/arquitetura/modelo-dados-v2.md, D5
