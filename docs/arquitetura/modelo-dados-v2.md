# Modelo de dados v2 (revisão r2)

Tarefa: t-fase1-arquitetura, critério 2. DDL completo: `docs/arquitetura/modelo-v2.sql` (rascunho de especificação, não migração de produção). Rodada 1: responde ao veto do Red Team (`docs/agents/red-team-t-fase1-arquitetura.md`, itens 1 a 19), às falhas do Testador e às lacunas do Avaliador. Rastreio item a item: fim de `docs/tasks/t-fase1-arquitetura.md`.

Evidência em PostgreSQL 16.15 limpo (porta 5497, usuário não-root `pgtest`, diretório `.pgexec`):
- Execução do SQL: `docs/arquitetura/evidencias/modelo-v2-execucao-r1.log` (`ON_ERROR_STOP=1`, exit 0).
- Isolamento: `docs/arquitetura/evidencias/teste-rls-r1.log` (1422 sondas, 0 falhas; 1281 sondas de ataque negadas; 116 controles positivos).
- Sondas do Red Team: `docs/seguranca/evidencias/red-team-sondas-r1.log` (26 de 26 negadas; 2 controles positivos).
- Logs da rodada 0 ficam como estavam (`modelo-v2-execucao.log`, `teste-rls.log`, `red-team-sondas.log`).

Rodada 2 (PostgreSQL 16.15 limpo, porta 5494, usuário não-root `pgtest`, diretório `.pgexec2`; runner `docs/arquitetura/evidencias/teste-r2.sh`, um cluster novo por bateria):
- Execução do SQL: `modelo-v2-execucao-r2.log` (exit 0).
- `teste-rls-r2.log` (bateria r1 com 2 ajustes de controle declarados no cabeçalho de `teste-rls-r2.sql`): 1423 sondas, 0 falhas, 1281 ataques negados, 117 controles positivos, 24 INFO. Sem os ajustes: `teste-rls-r1-sem-ajuste-r2.log` (2 falhas, exatamente os dois controles cujo pressuposto mudou).
- `teste-r1-independente-r2.log` (bateria do Testador, cópia `-r2.sql` com adaptações A1 a A6 no cabeçalho): 3613 casos, 0 falhas.
- `docs/seguranca/evidencias/red-team-sondas-r1-r2.log`: 26 de 26 negadas. `red-team-sondas-r1-novas-r2.log`: N4c, N6a, N6b, N7a NEGADO.
- `sondas-r2.log` (sondas novas dos itens desta rodada): 70 de 70.

Mudanças visíveis do modelo na rodada 2 (sem tabela nova; funções, políticas e gatilhos):
- `sessao_valida` recusa sessão EQUIPE de usuário inativo (Testador F3).
- `ator_encaminhamento()`: a sessão do paciente vale para o caso do link (Red Team I-19).
- `mesma_pessoa` e `nome_normalizado`: telefone é contato, não identidade (Red Team T-18, ADR-0036).
- `encaminhamento_aberto` e revogação por gatilho: link e envio não sobrevivem a estado final (Testador F1).
- `agendamento_marca_autor`: REALIZADO, FALTOU e CANCELADO finais; CONFIRMADO não volta (Testador F2).
- Papéis de login com `track_activities = off` e sem parâmetro em log (Red Team I-20, ADR-0026 item 7).
- Gatilhos de evento `saas_alerta_ddl_*` (Red Team R-07, ADR-0027).

Fontes: `docs/briefing.md`; `docs/agents/pesquisador-t-fase1-arquitetura.md` (RLS do PostgreSQL 16, Spring Modulith, LGPD, Lei 13.787).

## 1. Regras gerais

| Regra | Como aparece no modelo | Fonte |
|---|---|---|
| UUID em todo id | Toda PK é `uuid DEFAULT gen_random_uuid()` | briefing, Decisões: Identificadores |
| Tenant | `clinica_id` nas tabelas da clínica | briefing, Glossário e Decisões: Multi-tenant |
| Pessoa global separada do vínculo | `profissional`/`profissional_clinica`, `paciente`/`paciente_clinica`, `usuario`/`usuario_clinica` | briefing, Mudanças 1 |
| Identidade verificável no banco | Tabela `sessao` conferida por hash do token em toda política (ADR-0023) | Red Team, item 1 |
| Coerência entre tenants | FK composta em toda referência a dado de tenant (tabela da seção 4) | Red Team, item 5 |
| Escrita por coluna | GRANT por coluna em toda tabela que a web altera; colunas de identidade sem GRANT | Red Team, item 9 |
| Campos sensíveis cifrados na aplicação | `cpf_cifrado`, `motivo_cifrado`, `conduta_cifrada`, `nome_original_cifrado` (bytea) | briefing, Proteção de dados; ADR-0026 |
| Auditoria e histórico só de inclusão | Sem GRANT de UPDATE, DELETE, TRUNCATE; gatilho barra todo papel que respeita gatilho (web, jobs, funções); dono das tabelas e superusuário contornam, com alerta de DDL no log e controle operacional (ADR-0027, rodada 2); histórico sem INSERT para a web | briefing, Proteção de dados; ADR-0027 |
| Nenhum benefício a quem encaminha, nenhuma cobrança por paciente | Nenhuma coluna ou tabela desse tipo | briefing, Regras inegociáveis |

## 2. Papéis de banco (ADR-0024)

| Papel | Login | Privilégios |
|---|---|---|
| `saas_owner` | não | Dono das tabelas; sujeito a FORCE RLS |
| `saas_funcoes` | não | BYPASSRLS; dono das funções `SECURITY DEFINER`; ninguém faz SET ROLE para ele |
| `saas_app` | sim | Web. NOBYPASSRLS, não é dono; GRANT por coluna; 27 funções executáveis (r2: mais `ator_encaminhamento`); `track_activities = off` |
| `saas_jobs` | sim | Jobs e listeners. Nenhum privilégio em tabela; 8 funções `jobs_*`; `track_activities = off` |
| `saas_auth` | sim | Login OIDC. Só `sessao_equipe_abre`; `track_activities = off` |

Prova no log de execução: os cinco papéis com `rolsuper = f`; só `saas_funcoes` com BYPASSRLS; 0 tabelas de papel de login; 0 funções executáveis por PUBLIC.

## 3. Entidades

Coluna "Briefing": entidade da tabela "Entidades novas ou alteradas" (S) ou termo novo (N, ver `glossario-adicoes.md`).

| Tabela | Briefing | Módulo | Campos principais | Quem acessa |
|---|---|---|---|---|
| `clinica` | S | clinicas | `nome`, `cnpj`, `modo_recebimento` (só PEDIDO até a Fase 6, ADR-0031) | Equipe da própria; rede só por `catalogo_rede()` |
| `clinica_especialidade` | S | clinicas | `clinica_id`, `especialidade_id` | Equipe da própria |
| `especialidade` | N | clinicas | `nome` | Catálogo global sem RLS |
| `profissional` | S | clinicas | `crm`, `crm_uf`, `nome`, `telefone`, `email`, `usuario_id`, `canal_verificado_em` | Qualquer sessão válida lê nome e CRM; telefone e e-mail sem GRANT |
| `profissional_especialidade` | S | clinicas | `profissional_id`, `especialidade_id` | Qualquer sessão válida |
| `profissional_clinica` | S | clinicas | `duracao_consulta_min`, `recebe_encaminhamento`, `ativo` | Equipe da clínica |
| `horario_atendimento` | N | agenda | `dia_semana`, `hora_inicio`, `hora_fim` | Equipe da clínica |
| `usuario` | N | identidade | `sub_oidc`, `nome`, `email`, `ativo` | O próprio; ADMIN vê a equipe |
| `usuario_clinica` | N | identidade | `papel` (ADMIN, RECEPCAO, MEDICO), `ativo` | O próprio; ADMIN da clínica |
| `sessao` | N | identidade | `token_hash`, `tipo` (EQUIPE, PACIENTE, ENCAMINHADOR), ator, origem, `expira_em`, `encerrada_em` | Só funções |
| `flag_clinica` | N | clinicas | `chave` (inclui REDE_ENCAMINHAMENTO), `ligada` | Equipe da clínica; banco confere por `rede_ligada()` |
| `paciente` | S | pacientes | `nome`, `telefone` (contato, não identidade: ADR-0036), `data_nascimento`, `cpf_cifrado`, `cpf_hash`, `cadastrado_por_clinica_id` | O próprio; clínica com vínculo; quem vê encaminhamento dele |
| `paciente_clinica` | N | pacientes | `paciente_id`, `clinica_id`, `encaminhamento_id` | Equipe da clínica; nasce só por função |
| `consentimento` | S | pacientes | `finalidade`, `texto_aceito`, `versao_texto`, `canal`, `aceito_em`, `revogado_em` | O próprio paciente; clínica que recebeu |
| `agendamento` | S | agenda | `origem`, `encaminhamento_id`, `status` (REALIZADO, FALTOU, CANCELADO finais), `status_alterado_por`, `chave_idempotencia` | Equipe da clínica; o paciente lê só o do caso da sessão |
| `vaga_encaminhamento` | S | agenda | `inicio`, `fim`, `liberar_automaticamente_em`, `liberada_em` | Equipe da clínica (paciente só na Fase 6) |
| `encaminhamento` | S | encaminhamentos | `profissional_origem_id`, `paciente_id`, `especialidade_destino_id`, `clinica_destino_id`, `profissional_destino_id`, `motivo_cifrado`, `urgencia`, `status`, `expira_em` | Origem, destino com consentimento, paciente |
| `historico_status_encaminhamento` | N | encaminhamentos | `transicao`, `ator_tecnico`, `ator_tipo`, `ator_papel`, `ator_id`, `autor_negocio_id` | Herda do encaminhamento; só gatilho grava |
| `contrarreferencia` | S | encaminhamentos | `autor_profissional_id`, `conduta_cifrada` (uma por encaminhamento) | Herda do encaminhamento |
| `link_paciente` | N | encaminhamentos | `token_hash`, `expira_em`, `usado_em`, `revogado_em`, `codigo_hash`, `tentativas_codigo` | Só funções |
| `desafio_encaminhador` | N | clinicas | `desafio_hash`, `codigo_hash`, `tentativas`, `expira_em`, `usado_em` | Só funções |
| `anexo_encaminhamento` | S | arquivos | `chave_storage` (gerada pelo servidor), `tipo_mime`, `tamanho_bytes`, `sha256`, `status_varredura` | Herda do encaminhamento |
| `envio_notificacao` | N | notificacoes | `finalidade`, `canal`, destinatário por id, `chave_idempotencia`, `status`, `tentativas` (sem corpo) | Só funções |
| `evento_auditoria` | S | auditoria | `ator_tecnico`, `ator_papel`, `ator_id`, `acao`, `recurso_tipo`, `recurso_id`, `clinica_id` | Inclusão com ator conferido; leitura do ADMIN |

## 4. Integridade entre tenants (FK composta, Red Team item 5)

| Tabela | Referência | Alvo |
|---|---|---|
| `horario_atendimento`, `vaga_encaminhamento`, `agendamento` | `(clinica_id, profissional_clinica_id)` | `profissional_clinica(clinica_id, id)` |
| `agendamento` | `(clinica_id, paciente_id)` | `paciente_clinica(clinica_id, paciente_id)`: só paciente vinculado à clínica |
| `agendamento` | `(clinica_id, paciente_id, encaminhamento_id)` | `encaminhamento(clinica_destino_id, paciente_id, id)` |
| `agendamento` | `(clinica_id, vaga_encaminhamento_id)` | `vaga_encaminhamento(clinica_id, id)` |
| `paciente_clinica` | `(clinica_id, paciente_id, encaminhamento_id)` | `encaminhamento(clinica_destino_id, paciente_id, id)` |
| `consentimento` | `(paciente_id, encaminhamento_id)` e `(clinica_id, encaminhamento_id)` | `encaminhamento(paciente_id, id)` e `encaminhamento(clinica_destino_id, id)` |
| `link_paciente` | `(paciente_id, encaminhamento_id)` | `encaminhamento(paciente_id, id)` |
| `contrarreferencia` | `(clinica_id, encaminhamento_id)` | `encaminhamento(clinica_destino_id, id)` |

Mais: um agendamento ativo por encaminhamento, um link ativo por encaminhamento, uma contrarreferência por encaminhamento (índices únicos).

## 5. Row-Level Security e contexto

- Contexto por transação (`set_config(..., true)`): `app.sessao` (token em claro do cookie), `app.clinica_id` e `app.papel` (só para a equipe escolher clínica e papel). Nada mais é lido.
- Funções de contexto (`SECURITY DEFINER`, `search_path` fixo): `sessao_valida` (r2: recusa EQUIPE de usuário inativo), `ator_tipo`, `ator_usuario`, `ator_paciente`, `ator_encaminhamento` (r2: caso do link da sessão do paciente), `ator_profissional` (derivado), `eh_equipe`, `papel_efetivo`, `ator_id_efetivo`, `rede_ligada`, `consentimento_ativo`, `pode_contrarreferenciar`.
- Nenhuma política testa `app.papel` sozinho. ENABLE e FORCE em 23 tabelas; `especialidade` sem RLS.

| Quem vê o encaminhamento | Política | Condição |
|---|---|---|
| Origem | `encaminhamento_origem` | `profissional_origem_id = ator_profissional()` (sessão ENCAMINHADOR, ou MEDICO com vínculo ativo) |
| Clínica destino | `encaminhamento_destino` | `eh_equipe` e consentimento COMPARTILHAR_CASO ativo para a clínica |
| Paciente | `encaminhamento_paciente` | `paciente_id = ator_paciente() AND id = ator_encaminhamento()` (sessão PACIENTE vale para o caso do link, não para a pessoa; r2, I-19) |
| Jobs | nenhuma | Só funções `jobs_*` |

Escrita direta do papel web, depois do GRANT por coluna e da RLS:

| Tabela | Colunas com UPDATE | Quem |
|---|---|---|
| `encaminhamento` | `status`, `urgencia` | Gatilho: só T9, T10, T11 e urgência pela origem antes de SOLICITADO |
| `paciente` | `nome`, `data_nascimento` | Clínica que cadastrou |
| `agendamento` | `status`, `inicio`, `fim`, `profissional_clinica_id`, `vaga_encaminhamento_id` | Equipe; INSERT direto só sem `encaminhamento_id`; gatilho: só AGENDADO para CONFIRMADO e de ativo para REALIZADO, FALTOU ou CANCELADO; final não muda (r2) |
| `consentimento` | `revogado_em` | O próprio paciente, no caso da sessão |
| `clinica` | `nome`, `cnpj`, `modo_recebimento` | ADMIN |
| `profissional_clinica`, `horario_atendimento`, `vaga_encaminhamento` | Colunas de agenda | Equipe (ADMIN ou RECEPCAO) |

Tudo o mais passa por função: criar encaminhamento e paciente, vincular paciente, trocar telefone, escolher destino (T3), confirmar horário (T4), link e código, desafio do encaminhador, catálogo.

## 6. Decisões tomadas neste modelo

- D1. Contexto por `set_config(..., true)`, nunca `SET` de sessão (ADR-0004).
- D2. Papéis de banco: substituída pelo ADR-0024 (cinco papéis).
- D3. Papel de acesso em `usuario_clinica` (ADR-0016). Na rodada 1 o MEDICO fica amarrado ao profissional pelo banco: `profissional.usuario_id` da sessão com `profissional_clinica` ativo.
- D4. `cpf_hash` sem UNIQUE (ADR-0017); escopo da deduplicação no ADR-0029; critério no ADR-0036 (r2): CPF igual, ou nome normalizado + nascimento + telefone; telefone sozinho nunca.
- D5. Destino só com consentimento (ADR-0022).
- D6. Eventos só com ids (ADR-0020); só com consumidor (ADR-0032).
- D7. Transições e histórico por gatilho: ADR-0027.
- D8. Enumerações `text` com CHECK: ADR-0028.
- D9 (r1). Sessão verificável para todo ator: ADR-0023.
- D10 (r1). Registro de envio sem corpo: ADR-0034.
- D11 (r2). Sessão de paciente com escopo de caso: ADR-0023 (rodada 2).
- D12 (r2). Link e envio só com encaminhamento aberto: ADR-0030 (rodada 2).
- D13 (r2). Token só por parâmetro ligado; papéis de login fora de `pg_stat_activity`: ADR-0026, item 7.
- D14 (r2). Dono e superusuário contornam gatilho e RLS; alerta de DDL e controle operacional: ADR-0027.

## 7. Pendências e riscos que este modelo não resolve

- Retenção de anexos, encaminhamento e `envio_notificacao`: PERGUNTA ABERTA (Lei 13.787 fala em 20 anos para prontuário; advogado).
- Exclusão a pedido do titular (LGPD): sem DELETE para nenhum papel de login; rotina própria em ADR futuro.
- Leitura de dado de saúde auditada pela aplicação (sem gatilho de SELECT). Granularidade: um evento por registro exibido (STRIDE R-04), teste na Fase 2.
- Titularidade do CRM no cadastro pelo formulário: ADR-0025, decisão do Luiz.
- Segundo elemento antes de mostrar caso ao paciente: ADR-0035, decisão do Luiz.
- Custo das funções de contexto chamadas por linha nas políticas: medir na Fase 2.
- Provisionamento de clínica, equipe, flags e ligação `profissional.usuario_id`: papel de operação fora da aplicação [SUPOSIÇÃO].
- Tabela `event_publication`: criada pelo starter na Fase 2, sem GRANT ao papel web (ADR-0033).
- Pendências da Fase 2 do Red Team r1 (E-09, E-10, I-21, ajuste da O3): ver fim de `docs/tasks/t-fase1-arquitetura.md`.
- Reconciliação de duplicatas de paciente (consequência do ADR-0036): tela na Fase 3, ação humana auditada.
