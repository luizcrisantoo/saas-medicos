# ADR-0039: Alerta de DDL pela tabela alvo; funções sem sessão; diretório sem cadastro não verificado; envios derrubados no cancelamento; alerta de volume de preparo

Status: Proposto (Fase 2, F4), sujeito à revisão do Red Team
Data: 2026-11-17
Tarefa: Fase 2, F4 (docs/fase2/spec.md)
Completa: ADR-0024 (E-09), ADR-0027 (alerta de DDL, R-07), ADR-0034 (registro de envio)

## Contexto
Gates de banco do Red Team da Fase 2 (docs/agents/red-team-t-fase1-arquitetura-r1.md, seção 3 e 4; -r2.md, seção 3; docs/seguranca/stride-encaminhamento.md):
- R-08: o alerta de DDL filtrava por `schema_name = 'saas'`, mas o PostgreSQL 16 informa schema nulo para política, gatilho e regra. CREATE POLICY `USING (true)`, ALTER POLICY e CREATE TRIGGER passavam calados (R2N9a, R2N9b, R2N9e, R2N9g).
- I-21: `rede_ligada(uuid)` respondia sem sessão por qualquer clínica (N11a).
- O3: paciente e encaminhador listavam cadastros de profissional sem canal verificado e sem usuário, inclusive de quem tomou um CRM alheio (N11d).
- Testador r2 (N3-cancelamento): envio CONFIRMACAO_AGENDAMENTO ou LEMBRETE pendente de agendamento cancelado ainda saía ao paciente.
- E-09: resíduo aceito da credencial `saas_jobs`; compensação exigida: alerta de 20 preparos para o mesmo destinatário em 1 hora.

## Decisão
1. R-08 (`infra/db/bootstrap.sql`, gatilho de evento, exige superusuário): `saas_alerta_ddl` grava `ALERTA_DDL_SAAS` quando o schema do objeto é `saas` ou quando a tabela alvo do objeto está em `saas` (`pg_policy.polrelid`, `pg_trigger.tgrelid`, `pg_rewrite.ev_class`, lidos direto no catálogo, sem função auxiliar, porque o gatilho roda com o papel de quem faz o DDL) ou quando a identidade do objeto é `... on saas.<tabela>`; no DROP, também pelo primeiro nome do endereço do objeto. Cobre CREATE, ALTER e RENAME de política, CREATE TRIGGER, CREATE RULE, ALTER TABLE (DISABLE TRIGGER, NO FORCE e DISABLE RLS) e DROP de política, gatilho e regra. O log não participa do ROLLBACK. A linha leva só etiqueta, identidade do objeto e papéis.
2. I-21 (`V3__gates_banco.sql`): `rede_ligada` devolve falso sem sessão válida. O EXECUTE do papel web permanece (a lista de funções executáveis pela web é conferida pela regressão N1); as demais funções SECURITY DEFINER do papel web já exigem sessão (`consentimento_ativo`, `pode_contrarreferenciar`, `transicao_cancelamento`, `catalogo_rede`) ou são a entrada pública por token e código por desenho (link, pedido e confirmação de código).
3. O3: as políticas `profissional_ver` e `profissional_especialidade_ver` mostram a paciente e encaminhador só profissional com `canal_verificado_em` ou `usuario_id` (a mesma regra de `jobs_envio_link_paciente`). A equipe continua vendo o cadastro inteiro (nome e CRM), porque o admin cadastra profissional antes da verificação.
4. Envios após cancelamento: gatilho `agendamento_cancela_envios` (AFTER UPDATE OF status, SECURITY DEFINER) marca FALHOU os envios PENDENTE de CONFIRMACAO_AGENDAMENTO e LEMBRETE do agendamento que passa a CANCELADO, pelo papel web ou em cascata por T9, T10 e T11. FALHOU segue o precedente de `jobs_envio_prepara` (r2-1: envio fora de estado vira FALHOU e nada sai); não se cria status novo em `envio_notificacao`. Além disso, `jobs_envio_prepara` relê o agendamento: confirmação e lembrete só saem com agendamento AGENDADO ou CONFIRMADO, do mesmo caso e do mesmo paciente destinatário.
5. I-22 mantido: quando confirmação ou lembrete se referem a agendamento de um caso (pelo envio ou pelo agendamento), o contato é o telefone de contato do caso, nunca o telefone do cadastro. Só o envio a paciente sem caso nenhum usa o telefone do cadastro.
6. E-09: `envio_notificacao.preparado_em` (sem contato, ADR-0034 mantido) é gravado no preparo bem-sucedido. A partir do 20º preparo para o mesmo destinatário (tipo e id) em 1 hora, contando o atual, `jobs_envio_prepara` grava `ALERTA_PREPARO_VOLUME` no log do servidor com a contagem, o tipo e o id do destinatário, o id e a finalidade do envio; nunca contato, token ou código. Preparo que falha (sem contato, fora de estado) não conta, porque nenhum segredo sai.

## Alternativas descartadas
- Tirar o EXECUTE de `rede_ligada` do papel web: muda a lista de funções executáveis da web conferida pela regressão N1 sem ganho sobre a exigência de sessão.
- Status CANCELADO em `envio_notificacao`: muda a enumeração do ADR-0034 e o plano B; FALHOU já é o estado de "nada sai" do modelo.
- Contar volume por telefone: exigiria gravar o contato ou um hash dele, contra o ADR-0034.

## Consequências
- A migração V3 cria gatilho (CREATE TRIGGER) e altera política (ALTER POLICY): pela guarda de CI (F5) precisa de aprovação registrada.
- Reverter a V3 reabre I-21, O3, E-09 (alerta de volume) e os envios após cancelamento; o alerta de DDL fica no bootstrap e não reverte com o schema.
- Roteamento das linhas `ALERTA_DDL_SAAS` e `ALERTA_PREPARO_VOLUME` para fora do banco: F10.
- Provas: `acceptance/run.sh F4` (F4.1 a F4.5), `src/test/java/saasagenda/GatesBancoTest.java`.

## Fontes
- docs/fase2/spec.md, F4 e seções 3.2 e 5
- docs/seguranca/stride-encaminhamento.md, R-07, R-08, I-21, E-09
- docs/agents/red-team-t-fase1-arquitetura-r1.md (O3, N11a, N11d) e -r2.md (seção 3)
- docs/arquitetura/evidencias/teste-r2-independente.sql (N3-cancelamento)
- docs/adr/0024, 0027, 0034, 0038
