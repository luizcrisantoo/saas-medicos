# ADR-0002: Eventos de domínio com registro persistente (outbox)

Status: Aceito (decisão do briefing)
Data: 2026-11-10
Tarefa: t-fase1-arquitetura

## Contexto
Notificação e encaminhamento não podem se perder se o sistema cair no meio. A rede deve reagir a eventos da agenda em vez de chamar o código dela.

## Decisão
Eventos de domínio publicados na transação do negócio e entregues por `@ApplicationModuleListener`, com o Event Publication Registry do Spring Modulith (starter JDBC sobre o mesmo PostgreSQL) como outbox. Reenvio das pendentes no reinício ligado. Lista de eventos, publicadores e consumidores em `docs/arquitetura/mapa-modulos.md`, seção 4.

## Alternativas descartadas
- Broker externo (Kafka, RabbitMQ, SQS): mais um serviço para operar e outra fonte de verdade.
- Chamada síncrona entre módulos para tudo: acopla a agenda à rede e perde a ação se o envio falhar depois do commit.
- Outbox feito à mão: reimplementa o que o Modulith já oferece com teste.

## Consequências
- Listener precisa ser idempotente: o registro pode reentregar.
- A tabela do registro é criada pela migração Flyway da Fase 2; entradas concluídas precisam de limpeza periódica (modo de conclusão a definir na Fase 2).
- O payload fica gravado nessa tabela; por isso só ids (ADR-0020).

## Fontes
- docs/briefing.md: Mudanças 7; Decisões de arquitetura, Eventos
- docs/agents/pesquisador-t-fase1-arquitetura.md: Spring Modulith, Event Publication Registry (doc versão 2.1.1)
