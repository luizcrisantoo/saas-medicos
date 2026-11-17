# ADR-0004: Multi-tenant com schema compartilhado, clinica_id e Row-Level Security

Status: Aceito (decisão do briefing)
Data: 2026-11-10
Tarefa: t-fase1-arquitetura

## Contexto
O tenant é a Clínica. Se o código esquecer um filtro, o banco ainda precisa bloquear. Paciente e Profissional são globais e o Encaminhamento atravessa tenants.

## Decisão
Schema compartilhado com coluna `clinica_id` (o tenant_id do briefing) e RLS com `ENABLE` e `FORCE` em toda tabela com dado de clínica ou pessoa. A aplicação conecta com `saas_app` (NOSUPERUSER, NOBYPASSRLS, sem posse de tabela). Contexto da requisição gravado com `set_config(..., true)`, local à transação, nunca `SET` de sessão. Exceção explícita: o Encaminhamento é visível por relacionamento (origem, clínica destino com consentimento, paciente).

## Alternativas descartadas
- Só filtro no código: uma consulta esquecida vaza dados entre clínicas.
- Schema por clínica ou banco por clínica: operação e migração multiplicadas, e o encaminhamento entre clínicas fica difícil.
- `SET` de sessão: persiste na conexão devolvida ao pool.

## Consequências
- Testes de isolamento com Postgres real (Testcontainers) para toda política (briefing, Testes).
- Checagens de unicidade e chave estrangeira ignoram RLS; restrição UNIQUE sobre dado pessoal pode virar oráculo (ADR-0017).
- Jobs e listeners precisam de contexto SISTEMA com política própria e mínima.
- Rodada 1: a identidade de todo ator passou a vir de sessão verificada no banco (ADR-0023) e jobs usam papel próprio sem privilégio em tabela (ADR-0024). O contexto por `set_config(..., true)` continua, mas só com `app.sessao`, `app.clinica_id` e `app.papel`.

## Fontes
- docs/briefing.md: Decisões de arquitetura, Multi-tenant; Mudanças 1 e 5
- docs/agents/pesquisador-t-fase1-arquitetura.md: Row-Level Security do PostgreSQL 16 (seção 5.8, SET, set_config)
- docs/arquitetura/modelo-dados-v2.md, seção 3 e D1, D2
