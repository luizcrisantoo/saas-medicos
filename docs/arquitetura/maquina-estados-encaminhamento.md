# Máquina de estados do Encaminhamento (revisão r2)

Tarefa: t-fase1-arquitetura, critério 4. Fonte da verdade: `docs/briefing.md`, Mudanças 3 ("Criado, enviado ao paciente, solicitado, agendado, atendido, contrarreferido, expirado, cancelado. Toda mudança de status gera um registro com data e autor"). Grafia: `glossario-adicoes.md`. Imposição no banco: gatilhos `encaminhamento_valida` e `encaminhamento_apos_transicao` em `modelo-v2.sql` (ADR-0027). Módulos e eventos: `mapa-modulos.md`. Diagrama: `docs/arquitetura/diagramas/lifecycle-encaminhamento.html` (e `.png`).

Mudança da rodada 1: a tabela abaixo deixou de ser só regra da aplicação. O banco recusa qualquer par (de, para) fora dela e qualquer ator fora da coluna "Ator" (Red Team, item 10; Testador, máquina de estados não imposta; sugestão S3). Prova: `evidencias/teste-rls-r1.log`, seção matriz (56 pares por 7 atores, 392 sondas, só T9, T10 e T11 passam por UPDATE direto e só com o ator certo) e seções r1-10 e jobs (T2 a T8 pelas funções).

Mudanças da rodada 2 (provas em `evidencias/sondas-r2.log` e `teste-r1-independente-r2.log`):
- Estado final revoga o link e derruba envio pendente (Testador F1): ao entrar em CANCELADO, EXPIRADO ou CONTRARREFERIDO, o gatilho `encaminhamento_apos_transicao` revoga todo link ativo e marca FALHOU todo envio PENDENTE de link ou código; as funções de link e `jobs_envio_prepara` também releem o status (R2-1a a R2-1n).
- Invariante AGENDADO imposta também do lado da agenda (Testador F2): agendamento REALIZADO, FALTOU ou CANCELADO não muda mais, e CONFIRMADO não volta a AGENDADO. Assim "encaminhamento AGENDADO se e só se existe agendamento ativo" não se quebra por UPDATE na agenda depois de T5 ou T7 (R2-2a a R2-2p).
- T3 e T10 pelo paciente só no caso do link que abriu a sessão (Red Team I-19, R2-5a a R2-5m).

## 1. Os 8 status

| Status | Significado | Tipo |
|---|---|---|
| CRIADO | Profissional de origem preencheu motivo, urgência, especialidade e anexos | Inicial |
| ENVIADO_AO_PACIENTE | O provedor de mensagem aceitou o link do paciente | Intermediário |
| SOLICITADO | O paciente confirmou o código, consentiu e escolheu a clínica destino (modo PEDIDO) | Intermediário |
| AGENDADO | Existe Agendamento ativo com `origem = ENCAMINHAMENTO` deste encaminhamento | Intermediário |
| ATENDIDO | A agenda registrou a consulta como realizada | Estável, aguarda contrarreferência |
| CONTRARREFERIDO | Médico da clínica destino registrou a Contrarreferencia | Final |
| EXPIRADO | Venceu `expira_em` antes de AGENDADO | Final |
| CANCELADO | Origem, paciente ou clínica destino desistiu | Final |

Estados finais: CONTRARREFERIDO, EXPIRADO, CANCELADO. O gatilho recusa qualquer saída deles para todo papel que respeita gatilho. Correção da rodada 2 (Red Team R-07, ADR-0027): o dono das tabelas e o superusuário contornam o gatilho desligando-o; o desenho registra isso em alerta de DDL no log e restringe a credencial, não impede. Na entrada em estado final, links ativos são revogados e envios pendentes ao paciente viram FALHOU.

## 2. Transições

"Caminho" diz como a transição chega ao banco: UPDATE direto do papel web (só cancelamento) ou função do sistema, que declara a transição em `saas.transicao` e só vale dentro de `saas_funcoes`.

| # | De | Para | Gatilho de negócio | Ator (verificado pela sessão) | Caminho no banco | Evento emitido |
|---|---|---|---|---|---|---|
| T1 | (nenhum) | CRIADO | Profissional envia o formulário | ENCAMINHADOR (sessão) ou MEDICO com vínculo ativo | `encaminhamento_cria` | EncaminhamentoCriado |
| T2 | CRIADO | ENVIADO_AO_PACIENTE | Provedor aceitou o envio do link | SISTEMA (`saas_jobs`) | `jobs_envio_resultado` | nenhum (ADR-0032) |
| T3 | ENVIADO_AO_PACIENTE | SOLICITADO | Paciente escolhe clínica com a rede ligada e consente | PACIENTE (sessão aberta pelo código do link DESTE caso) | `paciente_solicita` | nenhum (painel lê por consulta) |
| T4 | SOLICITADO | AGENDADO | Recepção da clínica destino confirma horário (modo PEDIDO) | RECEPCAO ou ADMIN do destino | `destino_confirma_horario` | EncaminhamentoAgendado (e AgendamentoCriado da agenda) |
| T5 | AGENDADO | ATENDIDO | Agenda marcou REALIZADO | SISTEMA (`saas_jobs`); autor de negócio = quem marcou na agenda | `jobs_consulta_realizada` | nenhum (métrica por consulta) |
| T6 | ATENDIDO | CONTRARREFERIDO | Médico do destino grava a contrarreferência | MEDICO do destino, autor do agendamento REALIZADO | INSERT em `contrarreferencia` mais gatilho `contrarreferencia_t6` | EncaminhamentoContrarreferido |
| T7 | AGENDADO | SOLICITADO | Agendamento cancelado ou falta, sem outro agendamento ativo; `expira_em` renovado | SISTEMA (`saas_jobs`); autor de negócio = quem marcou na agenda | `jobs_agendamento_desfeito` | nenhum |
| T8 | CRIADO, ENVIADO_AO_PACIENTE ou SOLICITADO | EXPIRADO | `expira_em < now()` | SISTEMA (`saas_jobs`) | `jobs_expirar_encaminhamentos` (UPDATE com WHERE) | EncaminhamentoExpirado |
| T9 | CRIADO, ENVIADO_AO_PACIENTE, SOLICITADO ou AGENDADO | CANCELADO | Origem desiste | Profissional de origem | UPDATE direto de `status` | nenhum |
| T10 | ENVIADO_AO_PACIENTE, SOLICITADO ou AGENDADO | CANCELADO | Paciente escolhe outro especialista | PACIENTE, com sessão do link deste caso | UPDATE direto de `status` | nenhum |
| T11 | SOLICITADO ou AGENDADO | CANCELADO | Clínica destino não pode atender | RECEPCAO ou ADMIN do destino | UPDATE direto de `status` | nenhum |

Efeito de T9, T10 e T11 a partir de AGENDADO: o gatilho `encaminhamento_apos_transicao` cancela o agendamento ativo na mesma transação (a origem e o paciente não têm privilégio na agenda; S1, item d). A agenda publica AgendamentoCancelado; `jobs_agendamento_desfeito` não faz nada porque o encaminhamento já está CANCELADO.

Outras regras do gatilho:
- `motivo_cifrado`, `paciente_id`, `profissional_origem_id`, `especialidade_destino_id` e `criado_em` são imutáveis para todo papel que respeita gatilho (Red Team, item 9; ressalva do dono e do superusuário no ADR-0027).
- Destino (`clinica_destino_id`, `profissional_destino_id`) só muda em T3; `expira_em` só em T7.
- `urgencia` só pela origem, antes de SOLICITADO.

Não é transição: reenvio do link mantém ENVIADO_AO_PACIENTE, revoga o link anterior (índice de um link ativo por encaminhamento) e vira linha de `envio_notificacao`, não de histórico.

Liberdade de escolha do paciente (briefing, Regras inegociáveis): T10 existe em todo estado não final antes do atendimento.

Valores ainda abertos: prazo de `expira_em` na criação e em T7 [SUPOSIÇÃO: 30 dias, validar com a recepção do Rodrigo]; motivo codificado em T11 [SUPOSIÇÃO].

## 3. Expiração (T8)

- Quem: job do módulo `encaminhamentos`, papel de banco `saas_jobs`, função `jobs_expirar_encaminhamentos()`.
- O que faz: `UPDATE ... WHERE expira_em < now() AND status IN ('CRIADO','ENVIADO_AO_PACIENTE','SOLICITADO')` e devolve quantos expirou. Funciona com WHERE (falha 6 do Testador corrigida; Red Team, item 16). Prova: seção jobs, "T8 com WHERE: expira exatamente 1 (E7)" e "segunda chamada = 0".
- AGENDADO não expira. Se o agendamento cair, T7 devolve a SOLICITADO com prazo renovado.
- `link_paciente.expira_em` (3 dias) é separado do prazo do encaminhamento. Rodada 2: T8 revoga o link ativo do caso (R2-1l).
- O papel web declarando SISTEMA não vê nem altera nada (sondas `[r1] saas_app declarando SISTEMA`).

## 3a. Status do Agendamento ligado ao encaminhamento (rodada 2)

| De | Para permitido | Quem |
|---|---|---|
| AGENDADO | CONFIRMADO, REALIZADO, FALTOU, CANCELADO | Equipe da clínica (e cascata de T9 a T11) |
| CONFIRMADO | REALIZADO, FALTOU, CANCELADO | Equipe da clínica (e cascata) |
| REALIZADO, FALTOU, CANCELADO | nenhum (nem horário muda) | ninguém |

Gatilho `agendamento_marca_autor`. Reabrir atendimento é agendamento novo; para encaminhamento, só por T4 depois de T7.

## 4. VagaEncaminhamento

Adiada para a Fase 6 (ADR-0031): até lá só existe o modo PEDIDO, a tabela `vaga_encaminhamento` fica só com a forma e a política da equipe, e nenhuma transição usa vaga. Na Fase 6, a variante de T4 pelo paciente nasce como função que valida modo, flag da rede, vaga livre e encaminhamento do próprio paciente em SOLICITADO.

## 5. Histórico (data e autor)

- Tabela `historico_status_encaminhamento`: `status_anterior`, `status_novo`, `transicao` (T1 a T11), `ator_tecnico` (papel de login: `saas_app` ou `saas_jobs`), `ator_tipo` (EQUIPE, PACIENTE, ENCAMINHADOR, SISTEMA, OPERACAO), `ator_papel`, `ator_id`, `autor_negocio_id`, `alterado_em`.
- Único caminho de escrita: gatilho `encaminhamento_apos_transicao` (`SECURITY DEFINER`). O papel web não tem INSERT (falha 4 do Testador corrigida; Red Team, item 12).
- Ator vem da sessão verificada, nunca de parâmetro. Em T5 e T7 o autor de negócio é lido de `agendamento.status_alterado_por`, que o gatilho da agenda preenche a partir da sessão de quem marcou; o evento não carrega autor (STRIDE R-05).
- Só inclusão: sem GRANT de UPDATE, DELETE, TRUNCATE e gatilho `bloqueia_alteracao`.
- Visibilidade igual à do encaminhamento.
- Leitura do encaminhamento e do histórico por pessoa gera EventoAuditoria pela aplicação (motivo é dado de saúde).
