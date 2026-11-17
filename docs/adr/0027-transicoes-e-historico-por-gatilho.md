# ADR-0027: Transições de status e histórico impostos por gatilho no banco

Status: Aceito na revisão da Fase 1 (rodada 1); corrigido na rodada 2 (Red Team R-07)
Data: 2026-11-10
Tarefa: t-fase1-arquitetura
Substitui: a decisão D7 da rodada 0 (histórico por gatilho), apontada pelo Avaliador como decisão sem ADR.

## Contexto
Na rodada 0 o histórico era gravado por gatilho, mas a RLS aceitava qualquer par de status e qualquer ator, e o histórico aceitava INSERT direto com autor livre (Testador, falhas 4 e máquina de estados; Red Team, itens 10 e 12; sugestão S3 do Executor).

## Decisão
- Gatilho `encaminhamento_valida` (BEFORE, `SECURITY INVOKER` de propósito, para enxergar o `current_user` real):
  - UPDATE direto do papel web só pode cancelar: T9 (origem), T10 (paciente), T11 (recepção ou admin do destino), cada um a partir dos estados da tabela da máquina; e a origem pode mudar `urgencia` antes de SOLICITADO.
  - T2 a T8 só acontecem dentro de funções do sistema (`current_user = saas_funcoes`), e o par tem que bater com a transição que a função declarou em `saas.transicao`.
  - Colunas imutáveis para todo papel que respeita gatilho (web, jobs e funções): `motivo_cifrado`, `paciente_id`, `profissional_origem_id`, `especialidade_destino_id`, `criado_em`. Destino só muda em T3; `expira_em` só em T7. Estados finais sem saída.
  - Correção da rodada 2 (Red Team R-07): o texto da rodada 1 dizia "até superusuário". Está errado. O dono das tabelas (`saas_owner`) contorna gatilho e RLS com `ALTER TABLE ... DISABLE TRIGGER` e `NO FORCE ROW LEVEL SECURITY`, e o superusuário contorna tudo (`session_replication_role`, `BYPASSRLS` implícito). Prova: `red-team-sondas-r1-novas-r2.log`, N5b e N5c (o ataque ainda funciona; o alerta abaixo registra).
- Gatilho `encaminhamento_apos_transicao` (AFTER, `SECURITY DEFINER`) é o único caminho de escrita no histórico; o papel web não tem INSERT. Grava `transicao` (T1 a T11), `ator_tecnico` (papel de login), `ator_tipo`, `ator_papel` e `ator_id` lidos da sessão verificada, e `autor_negocio_id` em T5 e T7 lido de `agendamento.status_alterado_por` (preenchido por gatilho a partir da sessão), nunca do evento.
- Em T9, T10 e T11 a partir de AGENDADO, o mesmo gatilho cancela o agendamento ativo (S1, item d).
- Coluna de grant: o papel web só tem UPDATE em `status` e `urgencia` de `encaminhamento`.
- Agendamento (rodada 2, Testador F2): REALIZADO, FALTOU e CANCELADO são finais (nem status nem horário mudam) e CONFIRMADO não volta a AGENDADO, no gatilho `agendamento_marca_autor`. Mantém a invariante "encaminhamento AGENDADO se e só se existe agendamento ativo": reabrir a agenda exige agendamento novo, que para encaminhamento só nasce em T4.

## Mitigação do dono e do superusuário (rodada 2, R-07)
No banco:
- Gatilhos de evento `saas_alerta_ddl_fim` (ddl_command_end) e `saas_alerta_ddl_drop` (sql_drop), criados pelo superusuário, gravam `ALERTA_DDL_SAAS` no log do servidor para todo DDL em objeto do schema `saas`, com `session_user` e `current_user`. O log não participa do ROLLBACK: o ataque N5 desfeito por ROLLBACK fica registrado. O dono das tabelas não desliga nem apaga gatilho de evento (sondas R2-6b, R2-6c em `sondas-r2.log`).

Operacional (requisito da Fase 2, bloqueia o fechamento da fase):
- Dono separado: `saas_owner` é NOLOGIN e só dono; nenhuma pessoa nem processo da aplicação tem a credencial. A migração entra por um papel de pipeline que assume `saas_owner` só durante a migração.
- Migração só pelo pipeline (Flyway no CI, ADR-0003), nunca de máquina de desenvolvedor contra produção.
- O CI recusa migração que contenha `DISABLE TRIGGER`, `NO FORCE ROW LEVEL SECURITY`, `DISABLE ROW LEVEL SECURITY`, `DROP POLICY`, `DROP TRIGGER` ou `session_replication_role` sem aprovação explícita registrada.
- A linha `ALERTA_DDL_SAAS` do log do servidor vira alerta fora do banco (ferramenta de log do provedor); DDL fora da janela de migração é incidente.
- Superusuário: só o do provedor gerenciado, sem uso no dia a dia. [SUPOSIÇÃO: o Postgres gerenciado escolhido permite gatilho de evento ao papel administrativo; checar no ADR-0012.]

## Alternativas descartadas
- Validar só na aplicação: falha de autorização vira dado de saúde adulterado (taxa de chegada falsa, estado final ressuscitado).
- Tabela de pares consultada por política RLS: a RLS não vê OLD e NEW juntos.

## Consequências
- Matriz de 56 pares por 7 atores provada no banco (`teste-rls-r1.log`, seção matriz: 392 sondas, só T9, T10 e T11 passam com o ator certo).
- Seeds de teste que precisam de estado intermediário usam `session_replication_role = replica` ou gatilho desligado só na fixture, como superusuário. Isso só funciona porque o superusuário contorna o gatilho: é a mesma razão da correção acima.
- Resíduo aceito até a Fase 2: quem tem a credencial do dono ou do superusuário apaga trilha; a defesa é detectar (alerta) e restringir a credencial, não impedir.

## Fontes
- docs/agents/red-team-t-fase1-arquitetura.md, itens 9, 10, 12; docs/agents/testador-t-fase1-arquitetura.md; docs/agents/avaliador-t-fase1-arquitetura.md (D7)
- docs/agents/red-team-t-fase1-arquitetura-r1.md, R-07 e N5; docs/agents/testador-t-fase1-arquitetura-r1.md, F2
- PostgreSQL 16, documentação de ALTER TABLE (DISABLE TRIGGER exige ser dono) e de Event Triggers (criação exige superusuário): https://www.postgresql.org/docs/16/sql-altertable.html, https://www.postgresql.org/docs/16/event-triggers.html
- docs/arquitetura/maquina-estados-encaminhamento.md; docs/arquitetura/modelo-v2.sql, seção 11
