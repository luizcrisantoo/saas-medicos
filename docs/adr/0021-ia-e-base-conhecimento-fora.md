# ADR-0021: Motor de IA e Base de conhecimento do v1 saem até a Fase 8

Status: Aceito (decisão do briefing)
Data: 2026-11-10
Tarefa: t-fase1-arquitetura

## Contexto
O v1 tinha Motor de IA e Base de conhecimento para responder dúvidas. O briefing põe IA fora do escopo antes da Fase 8.

## Decisão
Os componentes `motor` e `kb` do v1 saem. O chatbot do site vira marcação pelo site (origem SITE). IA volta na Fase 8 como resumo de consulta por áudio, resumo do caso e contrarreferência gerada.

## Alternativas descartadas
- Manter o motor desligado no desenho: complica o mapa sem uso.

## Consequências
- Endereço e preparos podem voltar como texto de template de notificação [SUPOSIÇÃO].

## Fontes
- docs/briefing.md: Camada 3; Fora do escopo (IA antes da Fase 8)
- docs/arquitetura/diff-v1-v2.md, seção 2
