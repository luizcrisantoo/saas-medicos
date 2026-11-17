# ADR-0003: Um PostgreSQL gerenciado com migrações Flyway

Status: Aceito (decisão do briefing)
Data: 2026-11-10
Tarefa: t-fase1-arquitetura

## Contexto
Uma fonte de verdade, backup automático e histórico de schema versionado. A definição de pronto exige migração com caminho de reversão testado.

## Decisão
Um único PostgreSQL gerenciado (versão 16 como alvo do rascunho `modelo-v2.sql`), com todas as mudanças de schema por migração Flyway versionada. A migração roda com o papel dono (`saas_owner`); a aplicação conecta com `saas_app` (ADR-0004).

## Alternativas descartadas
- Um banco por clínica: multiplica operação, migração e backup.
- Banco não relacional: perde RLS, chaves estrangeiras compostas e restrições de exclusão usadas no modelo.
- Schema gerado pelo ORM: sem histórico revisável nem reversão.

## Consequências
- Cada migração precisa de script de reversão testado (briefing, Definição de pronto).
- Extensões usadas pelo modelo (`btree_gist`) precisam existir no serviço gerenciado escolhido no ADR-0012 [SUPOSIÇÃO a conferir].
- Backup com recuperação a ponto no tempo e restauração testada a cada trimestre (briefing, Operação).

## Fontes
- docs/briefing.md: Decisões de arquitetura, Banco; Definição de pronto; Operação e resposta a incidente
- docs/arquitetura/modelo-dados-v2.md
