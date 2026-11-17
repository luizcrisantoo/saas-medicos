# ADR-0015: Agenda própria como núcleo; link do sistema externo sai até a integração da Camada 3

Status: Aceito na revisão da Fase 1, sujeito ao Avaliador
Data: 2026-11-10
Tarefa: t-fase1-arquitetura

## Contexto
O Arquify v1 era uma camada de atendimento que "não cria agenda" e entregava o link do sistema que a clínica já usa. O briefing diz que a agenda continua sendo o núcleo do produto (Camada 1). Divergência detalhada em `docs/arquitetura/diff-v1-v2.md`, seção 1.

## Decisão
Substitui a premissa do v1. O módulo `agenda` (HorarioAtendimento, Agendamento, VagaEncaminhamento) é o núcleo e o destino de toda marcação. O link para sistema externo sai do fluxo. Clínica destino que usa outro sistema recebe encaminhamentos no modo PEDIDO (secretária confirma olhando o sistema dela) até a Fase 9, quando a leitura de horários externos entra como integração da Camada 3, atrás de flag. Não existe quarto modo de recebimento.

## Alternativas descartadas
- Manter o link externo como destino da marcação: contraria o briefing e impede medir a taxa de chegada.
- Criar um quarto valor de ModoRecebimento (LINK_EXTERNO): exigiria mudar o glossário do briefing, que fixa PEDIDO, VAGAS e AGENDA_NATIVA.

## Consequências
- Nenhuma tabela guarda URL de sistema externo até o ADR da integração da Fase 9.
- O modo PEDIDO cobre clínicas com outro sistema sem integração [SUPOSIÇÃO a validar com o Avaliador].

## Fontes
- docs/briefing.md: O produto em camadas; Linha do tempo (Agenda núcleo, Integrações externas); Fora do escopo
- docs/arquitetura/diff-v1-v2.md, seção 1
- docs/arquitetura/archify-v1-candidate.json
