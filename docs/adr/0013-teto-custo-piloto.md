# ADR-0013: Teto de custo mensal do piloto

Status: Aceito (Luiz, 2026-11-17): até R$ 800/mês
Data: 2026-11-10
Tarefa: t-fase1-arquitetura

## Contexto
O Luiz define um valor máximo para infraestrutura e WhatsApp somados; os agentes escolhem a solução mais simples que caiba nele. Decidir na Fase 1.

## Decisão
Nenhuma: o valor é do Luiz. Insumos levantados: banco gerenciado entre US$ 25 e 38/mês conforme a nuvem; AWS com aplicação entre US$ 50 e 80/mês [SUPOSIÇÃO]; Supabase com PITR perto de US$ 125/mês [SUPOSIÇÃO]; SMS do Google a US$ 0,02 por mensagem no Brasil.

## Alternativas descartadas
- (não se aplica)

## Consequências
- Faltam para fechar a conta: tarifa do WhatsApp por mensagem no Brasil (não obtida), tarifa de SMS do plano B e computação da aplicação.
- O plano B de mensagens (ADR-0018) tem custo por mensagem que entra no teto.

## Fontes
- docs/briefing.md: Perguntas em aberto, Teto de custo
- docs/agents/pesquisador-t-fase1-arquitetura.md: seções 2 e 3 (WhatsApp)


## Decisão do Negócio (2026-11-17)

Teto de R$ 800 por mês para infraestrutura e WhatsApp somados no piloto. Os agentes escolhem a solução mais simples que caiba. Exige alarme de orçamento na conta AWS.
