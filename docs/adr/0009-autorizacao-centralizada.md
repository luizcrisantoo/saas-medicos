# ADR-0009: Autorização centralizada, nega por padrão

Status: Aceito (decisão do briefing)
Data: 2026-11-10
Tarefa: t-fase1-arquitetura

## Contexto
Regra espalhada por vários controllers é onde nasce o vazamento entre clínicas. Há papéis por clínica e uma regra por relacionamento no encaminhamento.

## Decisão
Um único `ServicoAutorizacao` no módulo `identidade`, chamado em toda entrada, nega o que não estiver explicitamente permitido. Papéis por clínica vêm de `usuario_clinica`. Regras por relacionamento entram como implementação da SPI `PoliticaRelacionamento` (a de Encaminhamento fica em `encaminhamentos`). A RLS repete a regra no banco como segunda barreira.

## Alternativas descartadas
- Anotações de permissão espalhadas nos controllers: sem visão única nem teste de matriz.
- Só RLS: erro de autorização viraria erro de banco, e regras de ação (quem pode cancelar) não cabem bem em política.

## Consequências
- Matriz de autorização: cada endpoint testado com cada papel (briefing, Testes).
- O módulo `arquivos` autoriza anexos perguntando ao `ServicoAutorizacao`, sem depender de `encaminhamentos`.

## Fontes
- docs/briefing.md: Decisões de arquitetura, Autorização; Mudanças 5
- docs/arquitetura/mapa-modulos.md (identidade)
