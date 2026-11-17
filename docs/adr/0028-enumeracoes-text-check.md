# ADR-0028: Enumerações como text com CHECK

Status: Aceito na revisão da Fase 1 (rodada 1)
Data: 2026-11-10
Tarefa: t-fase1-arquitetura
Registra: a decisão D8 da rodada 0, apontada pelo Avaliador como decisão sem ADR.

## Contexto
Status, papel, origem, finalidade, canal e afins têm conjunto fechado de valores e vão mudar com as fases (ex.: modos VAGAS e AGENDA_NATIVA na Fase 6).

## Decisão
Colunas `text` com `CHECK (col IN (...))`. Valores em MAIÚSCULAS sem acento (glossario-adicoes.md). Restrições temporárias de fase ganham nome próprio (ex.: `modo_ate_fase6_so_pedido`), para a migração que as remove ser explícita.

## Alternativas descartadas
- `CREATE TYPE ... AS ENUM`: remover ou renomear valor exige recriar o tipo; adicionar valor não roda dentro de transação em versões antigas [SUPOSIÇÃO: comportamento de versões anteriores ao PostgreSQL 12; não verificado na doc nesta rodada].
- Tabela de domínio com FK: mais uma junção e mais uma tabela com RLS para pouco ganho.

## Consequências
- O código Java espelha os valores em `enum`; um teste compara o enum com o CHECK do banco na Fase 2.

## Fontes
- docs/agents/avaliador-t-fase1-arquitetura.md (D8); docs/arquitetura/modelo-v2.sql
