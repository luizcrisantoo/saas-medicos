# ADR-0031: Modos VAGAS e AGENDA_NATIVA adiados para a Fase 6

Status: Aceito na revisão da Fase 1 (rodada 1)
Data: 2026-11-10
Tarefa: t-fase1-arquitetura

## Contexto
A rodada 0 modelou em detalhe vagas e agenda nativa (políticas para paciente, variantes de T4), embora o briefing as coloque na Fase 6. O Avaliador apontou como complexidade cedo demais; o Red Team provou que `agendamento_paciente_marca` deixava o paciente encher a agenda de qualquer clínica (RT7; item 15; T-11, E-07).

## Decisão
- `clinica.modo_recebimento` mantém os três valores do glossário, mas a restrição `modo_ate_fase6_so_pedido` só aceita PEDIDO até a Fase 6.
- `vaga_encaminhamento` fica no modelo só com a forma (entidade do briefing) e política da equipe; sem política para paciente.
- Paciente não insere agendamento. T4 só pelo modo PEDIDO (`destino_confirma_horario`).
- Requisitos para a Fase 6, já exigidos pelo Red Team: agendamento pelo paciente só por função que valide modo de recebimento, flag `REDE_ENCAMINHAMENTO` ligada, vaga livre e encaminhamento do próprio paciente em SOLICITADO; idempotência por (clínica, ator, chave) (T-12); horários livres sem expor linhas de agendamento.

## Alternativas descartadas
- Manter as políticas da rodada 0 desligadas por flag na aplicação: a flag só na aplicação é exatamente o que E-07 derrubou.

## Consequências
- Menos políticas e uma variante a menos de T4 para testar agora.
- A Fase 6 abre com migração que remove `modo_ate_fase6_so_pedido` e cria a função de agendamento pelo paciente, com ataque T-11 repetido.

## Fontes
- docs/briefing.md: Camada 2 (modos), Linha do tempo (Fase 6)
- docs/agents/avaliador-t-fase1-arquitetura.md (complexidade); docs/agents/red-team-t-fase1-arquitetura.md, item 15
