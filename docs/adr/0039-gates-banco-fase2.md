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
1. R-08 (`infra/db/bootstrap.sql`, gatilho de evento, exige superusuário): `saas_alerta_ddl` grava `ALERTA_DDL_SAAS`, também com ROLLBACK (o log não participa da transação), quando qualquer uma destas vale. O que o PostgreSQL 16 devolve em cada caso foi conferido no servidor (tentativa 2), não de memória:
   - schema do objeto é `saas`, ou a tabela alvo está em `saas` (`pg_policy.polrelid`, `pg_trigger.tgrelid`, `pg_rewrite.ev_class`, lidos direto no catálogo, porque política, gatilho e regra vêm com schema nulo), ou a identidade é `... on saas.<tabela>`; no DROP, também o primeiro nome do endereço;
   - o comando não tem identidade resolvível (`object_identity` ou `objid` nulos). O PG 16 devolve schema, identidade e objeto nulos para GRANT, REVOKE e ALTER DEFAULT PRIVILEGES (só o tipo: TABLE, SCHEMA, TABLES). Vale para qualquer etiqueta, sem lista literal; a linha leva `(sem identidade, tipo X)`;
   - o objeto é um schema (ALTER SCHEMA RENAME e OWNER, COMMENT ON SCHEMA, DROP SCHEMA): o PG 16 informa tipo `schema`, schema nulo e a identidade com o nome (o novo, no RENAME), então o filtro é pelo tipo, não pelo nome;
   - quem executa é papel do schema: `current_user` em `saas_owner`, `saas_funcoes` ou um papel de login da aplicação, ou `session_user` em `saas_migracao`, `saas_app`, `saas_jobs`, `saas_auth`. Todo DDL desses papéis alerta, seja qual for o comando. Cobre `ALTER ... SET SCHEMA outro` feito pelo dono, que o PG 16 informa com o schema NOVO;
   - o objeto (tabela, função ou tipo) pertence a `saas_owner` ou `saas_funcoes`: cobre o SET SCHEMA para fora de `saas` feito pelo superusuário.
   A linha leva só etiqueta, identidade (ou tipo) do objeto e papéis. Consequência aceita: a migração pelo pipeline e um novo bootstrap também geram linhas (o alarme se correlaciona com a execução do pipeline); DDL comum do superusuário fora de `saas` não gera.
2. I-21 (`V3__gates_banco.sql`): `rede_ligada` devolve falso sem sessão válida. O EXECUTE do papel web permanece (a lista de funções executáveis pela web é conferida pela regressão N1); as demais funções SECURITY DEFINER do papel web já exigem sessão (`consentimento_ativo`, `pode_contrarreferenciar`, `transicao_cancelamento`, `catalogo_rede`) ou são a entrada pública por token e código por desenho (link, pedido e confirmação de código).
3. O3: as políticas `profissional_ver` e `profissional_especialidade_ver` mostram a paciente e encaminhador só profissional com `canal_verificado_em` ou `usuario_id` (a mesma regra de `jobs_envio_link_paciente`). A equipe continua vendo o cadastro inteiro (nome e CRM), porque o admin cadastra profissional antes da verificação.
4. Envios após cancelamento (tentativa 2): o envio só "sai" depois do preparo (`PREPARADO`, segredo e contato já entregues ao worker, provedor ainda não chamado) e só é confirmado por `jobs_envio_resultado`. Por isso:
   - gatilho `agendamento_cancela_envios` (AFTER UPDATE OF status, inicio, fim, profissional_clinica_id; SECURITY DEFINER): agendamento que sai de AGENDADO/CONFIRMADO (CANCELADO direto ou em cascata por T9, T10 e T11; REALIZADO; FALTOU) marca FALHOU a confirmação e o lembrete PENDENTES e PREPARADOS; reagendamento (horário ou profissional) marca FALHOU os PREPARADOS, que levariam o horário velho, e deixa os PENDENTES, porque o preparo relê o agendamento;
   - gatilho `encaminhamento_derruba_envios`: encaminhamento em estado final (CONTRARREFERIDO, EXPIRADO, CANCELADO) marca FALHOU os envios do caso (link, código, confirmação, lembrete) PENDENTES e PREPARADOS (a V1 só derrubava link e código pendentes);
   - `envio_caso_ativo(envio)` relê o caso na fonte: link só para CRIADO ou ENVIADO_AO_PACIENTE; código só com encaminhamento aberto; confirmação e lembrete só com agendamento AGENDADO ou CONFIRMADO, do mesmo caso, do mesmo paciente destinatário e com o encaminhamento aberto. `jobs_envio_prepara` usa essa regra antes de gerar segredo; `jobs_envio_resultado` também: envio já FALHOU devolve falso sem mudar nada, e PREPARADO de caso que não admite mais o envio vira FALHOU e devolve falso. ACEITO e ENTREGUE nunca são gravados para caso cancelado, e não há T2 de link de caso cancelado.
   FALHOU segue o precedente de `jobs_envio_prepara` (r2-1); não se cria status novo em `envio_notificacao`. Resíduo: o worker que já chamou o provedor antes do cancelamento não tem como desfazer a mensagem; o banco fecha o que depende dele (nada novo é preparado e nada é confirmado). O worker (F7) chama o provedor logo após o preparo.
5. I-22 mantido: quando confirmação ou lembrete se referem a agendamento de um caso (pelo envio ou pelo agendamento), o contato é o telefone de contato do caso, nunca o telefone do cadastro. Só o envio a paciente sem caso nenhum usa o telefone do cadastro.
6. E-09: `envio_notificacao.preparado_em` (sem contato, ADR-0034 mantido) é gravado no preparo bem-sucedido. O limite vem da spec (F4.5: 20 ou mais em 1 hora) e fica num único lugar nomeado, as constantes `c_volume_limite` e `c_volume_janela_horas` de `jobs_envio_prepara`. Conta-se, na janela e contando o preparo atual: (a) por destinatário (tipo e id); (b) pelo telefone normalizado (`telefone_normalizado`: só dígitos, sem zeros à esquerda, número nacional de 10 ou 11 dígitos ganha o 55), somando pacientes, casos e profissionais com o mesmo número. O contato de cada envio da janela é resolvido de novo por `envio_contato` (a mesma regra do preparo, I-22), nunca gravado nem logado. Linhas: `ALERTA_PREPARO_VOLUME: N preparos em 1 hora para destinatario_tipo=... destinatario_id=... (envio=... finalidade=...)` quando (a) atinge o limite; `ALERTA_PREPARO_VOLUME: N preparos em 1 hora para o mesmo contato, K destinatarios (envio=... finalidade=... destinatario_tipo=... destinatario_id=...)` quando (b) atinge o limite e soma mais que (a). Nunca contato, token ou código. Preparo que falha (sem contato, fora de estado) não conta. Limitação aceita: a contagem por telefone usa o contato atual de cada envio; trocar o telefone do caso no meio da janela tira os envios anteriores da soma.
## Alternativas descartadas
- Tirar o EXECUTE de `rede_ligada` do papel web: muda a lista de funções executáveis da web conferida pela regressão N1 sem ganho sobre a exigência de sessão.
- Status CANCELADO em `envio_notificacao`: muda a enumeração do ADR-0034 e o plano B; FALHOU já é o estado de "nada sai" do modelo.
- Gravar o telefone ou um hash dele no envio para contar volume: contra o ADR-0034; o contato é resolvido de novo na contagem.
- Filtro do alerta de DDL por lista de etiquetas (GRANT, REVOKE...): deixa passar etiqueta esquecida; vale a falta de identidade e quem executa.

## Consequências
- A migração V3 cria gatilhos (CREATE TRIGGER) e altera política (ALTER POLICY): pela guarda de CI (F5) precisa de aprovação registrada.
- Reverter a V3 reabre I-21, O3, E-09 (alerta de volume) e os envios após cancelamento; o alerta de DDL fica no bootstrap e não reverte com o schema.
- Roteamento das linhas `ALERTA_DDL_SAAS` e `ALERTA_PREPARO_VOLUME` para fora do banco: F10.
- Provas: `acceptance/run.sh F4` (F4.1 a F4.5), `src/test/java/saasagenda/GatesBancoTest.java`.

## Fontes
- docs/fase2/spec.md, F4 e seções 3.2 e 5
- docs/seguranca/stride-encaminhamento.md, R-07, R-08, I-21, E-09
- docs/agents/red-team-t-fase1-arquitetura-r1.md (O3, N11a, N11d) e -r2.md (seção 3)
- docs/arquitetura/evidencias/teste-r2-independente.sql (N3-cancelamento)
- docs/adr/0024, 0027, 0034, 0038
