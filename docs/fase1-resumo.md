# Fase 1 (Arquitetura): resumo para o Luiz

Tarefa: `docs/tasks/t-fase1-arquitetura.md`, critério 12. Data: 2026-11-10.

## 1. Veredito

O Red Team aprovou a arquitetura v2 com ressalvas após 2 das 3 rodadas permitidas (`docs/agents/red-team-t-fase1-arquitetura-r2.md`). O critério do briefing para avançar à Fase 2 ("arquitetura revisada antes de qualquer código novo", `docs/tasks/t-fase1-arquitetura.md`) está cumprido no desenho, mas a Fase 2 só começa com quatro correções obrigatórias (seção 5) e três decisões suas (seção 4): sem elas a aprovação vira veto (Red Team r2) e o provedor de login e a nuvem bloqueiam a Fase 2 (ADR-0007, ADR-0012).

## 2. O que mudou do v1 para o v2

Fonte: `docs/arquitetura/diff-v1-v2.md`.

1. **Agenda própria é o núcleo.** O v1 era "camada que não cria agenda" e entregava o link do sistema da clínica. O briefing manda o contrário. O link externo sai e vira leitura de horários na Fase 9; até lá a clínica que usa outro sistema recebe no modo PEDIDO (ADR-0015).
2. **Identidade global.** Paciente e profissional são pessoas únicas, com vínculo por clínica (`paciente_clinica`, `profissional_clinica`).
3. **Encaminhamento com máquina de 8 estados** (T1 a T11), imposta por gatilho no banco, com histórico de data e autor (ADR-0027).
4. **Isolamento em duas barreiras:** filtro no código e RLS no banco. O encaminhamento atravessa clínicas só para origem, destino (com consentimento) e paciente.
5. **Monolito modular Spring Modulith**, 8 módulos, eventos por outbox só com ids (`docs/arquitetura/mapa-modulos.md`).
6. **Notificações em módulo único,** com plano B por SMS ou e-mail e registro de envio sem o corpo da mensagem (ADR-0018, ADR-0034).
7. **Sai até a Fase 8:** Motor de IA e Base de conhecimento (ADR-0021). Entram feature flags por clínica (ADR-0019).
8. **Sessão verificável no banco** para toda pessoa, inclusive o paciente por link (ADR-0023).

## 3. Decisões mais importantes

Índice completo, 36 ADRs: `docs/adr/README.md`.

| ADR | Título | Em uma linha |
|---|---|---|
| 0001 | Monolito modular | Um deploy, 8 módulos, sem ciclos |
| 0004 | Multi-tenant com RLS | `clinica_id` mais RLS forçada, app sem BYPASSRLS |
| 0015 | Agenda própria | Substitui a premissa do v1 |
| 0023 | Sessão verificável | Banco ignora identidade vinda do cliente |
| 0024 | Papéis web, jobs e login | Jobs só por funções estreitas |
| 0027 | Transições por gatilho | Histórico não forjável; dono do banco ainda contorna (alerta de DDL) |
| 0030 | Link e código do paciente | Tamanho, validade e limites de tentativa |
| 0036 | Telefone é contato | Telefone sozinho nunca funde pessoas |

## 4. Decisões que são suas

Os agentes não decidiram nenhuma. Nenhum ADR traz recomendação dos agentes; só opções e riscos.

| Decisão | Opções | Prazo | Fonte |
|---|---|---|---|
| Provedor de autenticação | Cognito sa-east-1; Supabase Auth; Google Identity; Auth0 e Clerk (sem região no Brasil); Keycloak gerenciado. Pergunta prévia: o paciente precisa de conta, ou só a equipe? | Bloqueia a Fase 2 | ADR-0007 |
| Nuvem e serviços | AWS sa-east-1; Google Cloud; Azure; Supabase; Fly.io | Bloqueia a Fase 2 | ADR-0012 |
| Teto de custo mensal | Valor seu (infra mais WhatsApp). Referência: banco de US$ 25 a 38; AWS com app de US$ 50 a 80 [SUPOSIÇÃO]. Faltam tarifas de WhatsApp e SMS | Fase 1 | ADR-0013 |
| Titularidade do CRM | 1) conferir no CFM e revisar à mão; 2) aceitar o risco no piloto por escrito; 3) primeiro cadastro só via clínica cliente | Antes da Fase 5 | ADR-0025 |
| Segundo elemento do paciente | 1) pedir data de nascimento (idoso pode errar); 2) aceitar o risco com tela mínima; 3) dado clínico só na clínica | Antes da Fase 5 | ADR-0035 |
| Menores e responsável (T-20) | Médico encaminha o filho com o "CPF do responsável" [SUPOSIÇÃO: prática comum]. A correção do Red Team nunca funde por CPF com nome ou nascimento diferentes. Falta você dizer como o produto identifica menor sem CPF e quem é o titular do vínculo. [SUPOSIÇÃO: isso é decisão de produto] | Antes da migração de `paciente` | `docs/seguranca/stride-encaminhamento.md`, T-20 |
| Retenção de anexos e encaminhamentos | Sem prazo definido; Lei 13.787 cita 20 anos para prontuário, qualificação vai ao advogado | Antes da Fase 5 | ADR-0010, briefing (Definição de pronto) |

Também em aberto no briefing, fora da Fase 1: migração dos dados do Rodrigo (antes da Fase 3) e papéis na LGPD (antes da Fase 5).

## 5. Gates obrigatórios da Fase 2

Fonte: Red Team r2, seção 3; Testador r2.

| Origem | Gate |
|---|---|
| Red Team | T-20: CPF só funde com nome e nascimento iguais; recepção recebe sugestão, nunca id |
| Red Team | I-22: telefone informado não é descartado em silêncio |
| Red Team | R-08: gatilho de evento filtrado pela tabela alvo; CI recusa CREATE/ALTER POLICY e CREATE TRIGGER fora de migração revisada |
| Red Team | I-23: busca e escrita da recepção só por vínculo ou consentimento ativo |
| Red Team (r1) | E-09: credencial de jobs fora do processo web |
| Red Team (r1) | E-10: OIDC valida assinatura, iss, aud, exp, nonce e MFA; ADMIN e MEDICO sem MFA recusados |
| Red Team (r1) | I-21: oráculos de funções SECURITY DEFINER sem sessão |
| Red Team (r1) | O3: profissional sem canal verificado e sem usuário fora da visão pública |
| Red Team (r1) | T-19: REALIZADO e FALTOU só com `inicio <= now()`. Decisão do Verificador: gate da Fase 3, antes da migração de agendamento com tela (docs/agents/verificador-t-fase1-arquitetura.md, item 5) |
| Red Team (r1) | Gate de CI para R-07 e teste de código para I-20 |
| Testador | Cancelar agendamento deve derrubar envios CONFIRMACAO e LEMBRETE pendentes (latente, baixa; nenhuma função os cria hoje) |

Regressão obrigatória: N1 a N12, RT1 a RT10, R2N1 a R2N9, R2-1 a R2-7 e a matriz de 392 sondas.

## 6. Evidência

PostgreSQL 16.15 limpo, um cluster novo por bateria. Todos os caminhos em `docs/arquitetura/evidencias/`, salvo indicação.

| Bateria | Resultado | Log |
|---|---|---|
| `modelo-v2.sql` | exit 0, ON_ERROR_STOP | `modelo-v2-execucao-r2.log` |
| RLS (Executor) | 1423 sondas, 0 falhas, 1281 ataques negados | `teste-rls-r2.log` |
| Testador independente | 3613 casos, 0 falhas (cópia adaptada); o Testador reproduziu 1 falha latente | `teste-r1-independente-r2.log`, `teste-r2-independente.log` |
| Sondas desta rodada | 70 de 70 | `sondas-r2.log` |
| Red Team r1 | 26 de 26 negadas | `docs/seguranca/evidencias/red-team-sondas-r1-r2.log` |

Diagramas Archify (HTML e PNG, 4 gates do `finalize` em pass; revisão perceptual não feita): `docs/arquitetura/diagramas/` (arquitetura-v2, erd-modelo-v2, lifecycle-encaminhamento). Ameaças: `docs/seguranca/stride-encaminhamento.md`.

## 7. Build in public (Instagram)

Regras: briefing, seção "Build in public no Instagram".

| Pode | Nunca |
|---|---|
| Os três diagramas Archify, que não têm dado real | Tela com dado real de paciente, médico ou clínica (só homologação, dado fictício) |
| Decisões e aprendizados, como "por que a agenda virou o núcleo" | Chave, token, arquivo de configuração, painel da nuvem, URL de produção ou homologação |
| | Detalhe que ajude a atacar o sistema, como o formato dos links de paciente |

Antes de publicar, revisar cada print procurando abas do navegador e notificações na tela. [SUPOSIÇÃO: o ERD e as sondas citam nomes de funções e de campos de segurança; mostrar só o ERD simplificado ou o lifecycle.]
