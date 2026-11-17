# ADR-0012: Escolha da nuvem e dos serviços gerenciados

Status: Aceito (Luiz, 2026-11-17): AWS São Paulo (sa-east-1)
Data: 2026-11-10
Tarefa: t-fase1-arquitetura

## Contexto
O briefing manda decidir na Fase 1 qual nuvem e quais serviços, com região no Brasil. O Orquestrador não decide.

## Decisão
Nenhuma. Opções levantadas pelo Pesquisador:

| Opção | A favor | Riscos |
|---|---|---|
| AWS sa-east-1 | Conjunto completo na região: RDS PostgreSQL, S3, KMS, Secrets Manager, Cognito; banco mínimo perto de US$ 33/mês [SUPOSIÇÃO de soma], US$ 50 a 80 com a aplicação [SUPOSIÇÃO] | PITR e URL pré-assinada não lidos nesta rodada [SUPOSIÇÃO]; mais serviços para configurar |
| Google Cloud southamerica-east1 | Cloud SQL db-g1-small perto de US$ 25,5/mês | Instância shared-core sem SLA; PITR não citado; preço por região a confirmar |
| Azure Brazil South | Regiões BR listadas | Sem preço levantado; serviços não lidos |
| Supabase (AWS sa-east-1) | Postgres, Auth e Storage num produto; Pro US$ 25/mês | PITR é add-on de US$ 100/mês (7 dias); sem KMS nem gerenciador de segredos equivalente [SUPOSIÇÃO]; acesso a BYPASSRLS do projeto a checar |
| Fly.io (gru) | Managed Postgres a partir de US$ 38/mês | Sem storage de objetos nem KMS lidos |

## Alternativas descartadas
- Railway e Render: sem região no Brasil (Pesquisador).

## Consequências
- Bloqueia a Fase 2 (ambientes, segredos, storage).
- Precisa confirmar `btree_gist` no Postgres gerenciado (ADR-0003).

## Fontes
- docs/briefing.md: Perguntas em aberto, Hospedagem
- docs/agents/pesquisador-t-fase1-arquitetura.md: seção 2


## Decisão do Negócio (2026-11-17)

Luiz escolheu AWS sa-east-1: RDS PostgreSQL 16 com PITR, S3 privado com SSE-KMS e URL assinada, KMS, Secrets Manager. Infra como código; provisionamento real depende da conta AWS do Luiz.
