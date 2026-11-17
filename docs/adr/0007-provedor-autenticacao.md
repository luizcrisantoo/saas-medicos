# ADR-0007: Escolha do provedor de autenticação

Status: Aceito (Luiz, 2026-11-17): AWS Cognito
Data: 2026-11-10
Tarefa: t-fase1-arquitetura

## Contexto
O briefing manda decidir na Fase 1, comparando custo por usuário, MFA, código de uso único e esforço de operação. O Orquestrador não decide.

## Decisão
Nenhuma. Opções levantadas pelo Pesquisador (preços lidos em 2026-11-10):

| Opção | A favor | Riscos |
|---|---|---|
| AWS Cognito (sa-east-1) | Região São Paulo; 10.000 MAU grátis; TOTP, SMS, passkey (Essentials); gatilho Custom SMS sender permite entregar o código por outro canal | UI de login e fluxos customizados dão trabalho [SUPOSIÇÃO]; envio pelo WhatsApp seria código nosso; código chega cifrado com KMS |
| Supabase Auth (sa-east-1) | Região São Paulo; 50.000 MAU grátis; TOTP grátis; Send SMS hook cita WhatsApp como canal | MFA por telefone é add-on de US$ 75/mês; acopla Auth ao Postgres do projeto e a RLS dele usa o JWT do Supabase, o que interage com o ADR-0004 [SUPOSIÇÃO] |
| Google Identity Platform | 50.000 MAU grátis | Região de dados não verificada; sem gancho de envio customizado encontrado; SMS US$ 0,02 no Brasil |
| Auth0 | Passwordless em todos os planos; WebAuthn | Sem região no Brasil |
| Clerk | Simples; Pro US$ 25/mês com MFA | Sem região, dados nos EUA (risco LGPD de transferência internacional) |
| Keycloak gerenciado | Sem custo por usuário [SUPOSIÇÃO] | Operação alta; região BR não confirmada |

Pergunta prévia para o Luiz: o paciente precisa ter conta no provedor, ou o código de uso único do paciente fica no módulo `encaminhamentos` (modelo atual: `link_paciente.codigo_hash`) e o provedor atende só a equipe? Isso muda a contagem de usuários e o critério de escolha.

## Alternativas descartadas
- (nenhuma descartada; Auth0 e Clerk ficam com a ressalva de não ter região no Brasil)

## Consequências
- Bloqueia a Fase 2 (briefing: "Provedor de autenticação com MFA").
- Se a escolha for Supabase Auth, o ADR-0004 precisa ser revisto para o formato de contexto do Supabase.

## Fontes
- docs/briefing.md: Perguntas em aberto, Provedor de autenticação
- docs/agents/pesquisador-t-fase1-arquitetura.md: seção 1


## Decisão do Negócio (2026-11-17)

Luiz escolheu AWS Cognito, região sa-east-1, user pool com MFA obrigatório para ADMIN e MEDICO. Código de uso único do paciente pelo WhatsApp via Custom SMS sender (Lambda + KMS), conforme opções levantadas em docs/agents/pesquisador-t-fase1-arquitetura.md. Passwordless de Cognito exige o plano Essentials [fonte no relatório do Pesquisador].
