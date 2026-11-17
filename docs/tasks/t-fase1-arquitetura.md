# t-fase1-arquitetura

Classificação: GRANDE (mudança de arquitetura). Fluxo do briefing (docs/briefing.md, seção "Como trabalhar"): GSD Discutir, Planejar, Executar, Verificar; máximo 3 rodadas de revisão; Red Team com veto em autenticação, autorização, tenant, arquivos, links de paciente e dado de saúde. Painel de Personas não entra (só a partir da Fase 3, com telas). Claude Design não entra (Fase 1 não tem tela).

## Pedido original
O Luiz colou o briefing (docs/briefing.md), cuja instrução é: "Usando o time de agentes descrito abaixo, revise a arquitetura do Arquify com base neste briefing e siga a linha do tempo a partir da Fase 1."

Fase 1 do briefing: "Arquitetura (concluída, revisar agora). Aplicar as mudanças da seção anterior ao desenho do Arquify. Entregáveis: modelo de dados v2, mapa de módulos, máquina de estados do encaminhamento, modelagem de ameaças feita pelo Red Team e as decisões da seção de arquitetura e segurança registradas. Critério pra avançar: arquitetura revisada antes de qualquer código novo."

Desenho atual do Arquify (v1): docs/arquitetura/archify-v1-candidate.json e docs/arquitetura/archify-v1.png. ATENÇÃO: o v1 foi desenhado como "camada de atendimento que NÃO cria agenda e entrega o link do sistema que a clínica já usa"; o briefing coloca a Agenda como núcleo. Essa divergência precisa ser explicitada.

## Critérios de aceite
1. docs/arquitetura/diff-v1-v2.md: tabela comparando cada elemento do Arquify v1 com o v2 (mantém, muda, sai, entra), cobrindo os 9 itens de "Mudanças na arquitetura do Arquify" do briefing, e a divergência agenda própria vs link externo com a decisão tomada e o que acontece com o link externo (vira modo de recebimento? integração da Camada 3?).
2. docs/arquitetura/modelo-dados-v2.md + docs/arquitetura/modelo-v2.sql: todas as entidades da tabela do briefing com campos, tipos, chaves, tenant_id onde couber, separação pessoa global vs vínculo por clínica, UUID em todo id exposto, consentimento, auditoria só de inclusão, campos sensíveis marcados para criptografia na aplicação, e políticas de Row-Level Security. O SQL é rascunho de especificação (não migração de produção) e precisa rodar num PostgreSQL 16 limpo.
3. docs/arquitetura/mapa-modulos.md: os 8 módulos (identidade, clínicas, agenda, pacientes, encaminhamentos, notificações, arquivos, auditoria), o que cada um possui (entidades), a API pública de cada um, as dependências permitidas e os eventos que cada um publica e consome (incluindo AgendamentoCriado, ConsultaRealizada, EncaminhamentoAgendado), com outbox, sem ciclos.
4. docs/arquitetura/maquina-estados-encaminhamento.md: os 8 status do briefing, todas as transições com gatilho, ator autorizado e evento emitido, estados finais, expiração, e o registro de histórico (data e autor) por transição.
5. Diagramas Arquify v2 gerados com a skill archify (instalada em /home/claude/archify-src/repo/archify, ver SKILL.md): arquitetura v2, ERD do modelo v2 e lifecycle do encaminhamento, cada um passando o `finalize` com ARCHIFY_CHROME=/opt/pw-browsers/chromium-1243/chrome-linux64/chrome, HTML + PNG exportado em docs/arquitetura/diagramas/.
6. docs/seguranca/stride-encaminhamento.md feito pelo Red Team: STRIDE do fluxo de encaminhamento (médico que encaminha sem conta, link do paciente, secretária, contrarreferência, anexos), cada ameaça com mitigação no desenho v2 e um caso de teste que vira lista de ataques das fases seguintes.
7. docs/adr/: um ADR curto por decisão da tabela "Decisões de arquitetura" do briefing e por decisão nova tomada na revisão (contexto, decisão, alternativas descartadas, consequências, status). As perguntas em aberto que o briefing manda decidir na Fase 1 (provedor de autenticação, hospedagem, teto de custo) ficam como ADR com status "Proposto: decisão do Luiz", com opções e riscos levantados pelo Pesquisador; o Orquestrador não decide.
8. Glossário respeitado: nomes de entidades e campos iguais ao glossário do briefing; termo novo listado em docs/arquitetura/glossario-adicoes.md.
9. Evidência de teste: o Testador roda o modelo-v2.sql num PostgreSQL 16 local e prova o isolamento por RLS (usuário da clínica A não lê, edita nem lista dados da clínica B; encaminhamento visível só a origem, clínica destino e paciente), com comandos e saídas.
10. Regras inegociáveis do briefing refletidas no desenho (sem campo ou fluxo que permita benefício a quem encaminha ou cobrança por paciente; nenhum dado clínico em mensagem de WhatsApp; anexos criptografados; retenção definida ou marcada como pergunta).
11. Nenhum código de aplicação (Java/React) escrito nesta fase. Toda afirmação factual com fonte ou [SUPOSIÇÃO]. Texto sem travessão.
12. Resumo final em docs/fase1-resumo.md: o que mudou, decisões tomadas, decisões pendentes do Luiz, veto/aprovação do Red Team, e se o critério para avançar à Fase 2 foi cumprido.

## Sugestões do Executor (tarefa 2: critérios 3, 4, 5, 7, 10). Não alteram o modelo; decidir na próxima rodada

- S1. Contexto SISTEMA dos listeners e de `notificacoes` sem política no `modelo-v2.sql`. Hoje o SISTEMA só lê e grava `EXPIRADO` em `encaminhamento` e não lê `paciente`. Faltam: (a) T2 (`registrarEnvio`, CRIADO para ENVIADO_AO_PACIENTE) e emissão de `link_paciente` pelo listener (a política `link_emite` exige ver o encaminhamento); (b) T5 e T7 vindos de ConsultaRealizada, AgendamentoCancelado e PacienteFaltou, com `app.clinica_id` do evento e `autorId` real no histórico; (c) leitura só de telefone e e-mail do paciente para envio (função SECURITY DEFINER estreita ou política por coluna); (d) cancelamento de Agendamento de clínica destino pedido pela origem ou pelo paciente (T9 e T10 em AGENDADO): hoje só a equipe da clínica pode alterar `agendamento`. Ver `docs/arquitetura/mapa-modulos.md`, seção 5, e `maquina-estados-encaminhamento.md`.
- S2. `notificacoes` não tem tabela no modelo v2: falta registro de envio (evento de origem, destinatário por id, canal, status, tentativas, chave de idempotência, sem corpo da mensagem). Necessário para idempotência no envio (briefing, Segurança da aplicação) e para o plano B (ADR-0018).
- S3. A RLS não restringe o par (de, para) de status. Defesa em profundidade sugerida: gatilho que valide as transições T1 a T11 de `maquina-estados-encaminhamento.md`.

## Rodada de revisão 1 (Executor): o que foi resolvido

Evidência (PostgreSQL 16.15 descartável, porta 5497, usuário não-root `pgtest`, `.pgexec`, runner `docs/arquitetura/evidencias/teste-rls-r1.sh`):
- `docs/arquitetura/evidencias/modelo-v2-execucao-r1.log`: `modelo-v2.sql` com `ON_ERROR_STOP=1`, exit 0.
- `docs/arquitetura/evidencias/teste-rls-r1.log` (bateria do Testador adaptada em `teste-rls-r1.sql`, nenhuma sonda removida ou enfraquecida; mudanças listadas no cabeçalho): 1422 sondas, 0 falhas, 1281 sondas de ataque negadas, 116 controles positivos, 24 INFO; 0 tabelas alteradas ao fim.
- `docs/seguranca/evidencias/red-team-sondas-r1.log` (`red-team-sondas-r1.sql`): 26 de 26 sondas de ataque negadas (RT1 a RT10, cada uma com e sem sessão válida), 2 controles positivos.
- Diagramas: os três `finalize` com os 4 gates em pass; recibos da raiz substituídos; `.review/` antigo removido; PNG reexportados pelo menu Exportar do viewer. Revisão perceptual não feita (só gates automáticos).

Red Team (docs/agents/red-team-t-fase1-arquitetura.md):
1. Item 1, sessão verificável para todo ator: tabela `sessao` e funções `ator_*`; GUCs de identidade ignoradas (ADR-0023; r1-1, RT4, RT5).
2. Item 2, papel separado para jobs: `saas_jobs` sem privilégio em tabela, `saas_auth`, `saas_funcoes` (ADR-0024; seção jobs, r1-2, RT3).
3. Item 3, profissional amarrado ao usuário: `ator_profissional()` derivado, MEDICO exige `profissional_clinica` ativo (r1-3, RT8).
4. Item 4, autenticação do encaminhador: desafio com código no telefone verificado, sem oráculo, cadastro isolado (ADR-0025; r1-4, RT5c, RT5d, RT9b). Titularidade do CRM: decisão do Luiz.
5. Item 5, FK composta em toda referência com tenant (modelo-dados-v2.md, seção 4; r1-5 e sondas FK da seção f).
6. Item 6, vínculo e `paciente_id` nunca do cliente: só funções; sem INSERT/UPDATE da web (ADR-0029; r1-6, RT1a).
7. Item 7, telefone imutável: sem GRANT; troca só presencial pela clínica que cadastrou, auditada (r1-7, RT1b, RT1c, RT10).
8. Item 8, deduplicação: busca só entre pacientes ligados ao ator (ADR-0029; r1-8).
9. Item 9, UPDATE por coluna e gatilho de colunas imutáveis (r1-9: 40 sondas; Parte 3 vale até para superusuário).
10. Item 10, gatilho de transições T1 a T11 com ator; finais sem saída (ADR-0027; seção matriz 392 sondas, seção estados).
11. Item 11, consentimento: FKs compostas e política de vínculo (r1-11).
12. Item 12, histórico só por gatilho com ator técnico e autor de negócio; auditoria conferida contra a sessão (r1-10, r1-12, RT6).
13. Item 13, link: sem GRANT, funções, um ativo, limites por encaminhamento e paciente, código de 6 dígitos (ADR-0030; r1-13, RT2).
14. Item 14, anexo: chave gerada no servidor, imutável, varredura só PENDENTE para LIMPO/INFECTADO (r1-14, jobs, RT3d).
15. Item 15, agendamento pelo paciente removido até a Fase 6 com requisitos em ADR; flag da rede conferida no banco (ADR-0031; r1-15, RT7).
16. Item 16, T8 com WHERE (jobs: exatamente 1, segunda chamada 0).
17. Item 17, catálogo por função com flag e sem cnpj; telefone e e-mail de médico sem GRANT; `clinica_especialidade` exige equipe (r1-17; sonda 50 da rodada 0 agora passa).
18. Item 18, ações de sistema por 8 funções estreitas que releem a fonte (mapa-modulos.md, seção 5).
19. Item 19, ADR de Proteção de dados (ADR-0026).
20. Itens 20 a 22 registrados como requisito antes das Fases 4 e 5 (ADR-0033); listener idempotente já no desenho. Item 23: ADR-0035 (decisão do Luiz).

Testador (docs/agents/testador-t-fase1-arquitetura.md):
21. Falha 1 (FK simples): FK composta para `paciente_clinica` e encaminhamento.
22. Falha 2 (paciente alheio por UUID): só funções criam vínculo e encaminhamento.
23. Falha 3 (consentimento forjado): FKs compostas.
24. Falha 4 (histórico forjado): sem INSERT.
25. Falha 5 (sem restrição por coluna): GRANT por coluna e gatilho.
26. Falha 6 (T8): função com WHERE.
27. Falha 7 (`clinica_especialidade`): política exige `eh_equipe`.
28. Máquina de estados não imposta: gatilho e matriz.

Avaliador (docs/agents/avaliador-t-fase1-arquitetura.md):
29. Critério 2 PARCIAL: S1, S2, S3 resolvidas; `paciente_clinica` sem caminho para paciente resolvido (vínculo nasce em T4).
30. Critério 3 PARCIAL: contexto dos listeners (mapa, seção 5) e `envio_notificacao` (ADR-0034).
31. Critério 4 PARCIAL: T2, T5, T7, T10/T11 em AGENDADO executáveis e testados; par validado.
32. Critério 5: recibos com FAIL removidos; os três recibos da raiz em pass.
33. Critério 7: ADRs de Proteção de dados (0026), D2 (0024), D7 (0027), D8 (0028), mais 0023, 0025, 0029 a 0035.
34. Critério 8: glossário com status de agendamento, canal, enviado_por_tipo, estado do link e termos novos.
35. Inconsistência da confirmação duplicada: ADR-0032 (só EncaminhamentoAgendado confirma).
36. Catálogo com flag desligada e cnpj; MEDICO não amarrado a profissional: resolvidos (itens 3 e 17).
37. Diagrama de arquitetura: aresta de consumo da agenda por `encaminhamentos`, sessão no banco e funções de jobs.
38. Complexidade: 13 eventos sem consumidor cortados; sete contextos de RLS viram três tipos de sessão; VAGAS e AGENDA_NATIVA adiados (ADR-0031); código do paciente sem evento intermediário.

Sugestões S1 a S3: resolvidas (itens 18, 30, 10).

Bug encontrado pela bateria nesta rodada e corrigido: a checagem de `urgencia` no gatilho tratava comparação com ator nulo como permissão (paciente e destino conseguiam mudar a urgência); corrigido com `coalesce(..., false)` antes do log final.

## Objeções e notas do Executor para a rodada 2 (nenhum requisito do Red Team foi cortado)

- O1. Item 1 aplicado também à equipe (o Red Team pediu "fora da equipe"): a sessão de equipe depende do componente de login (`saas_auth`) ter validado o OIDC; o banco não valida JWT. Resíduo registrado no ADR-0023.
- O2. Item 7: implementada só a troca presencial; a troca "com confirmação no número antigo" fica para a Fase 3, junto com o aviso ao número antigo (o registro de envio não guarda contato).
- O3. Item 17 lido como "sem sessão válida, 0 linhas": com sessão válida e `app.clinica_id` lixo, nome e CRM de profissionais seguem legíveis (públicos no CFM [SUPOSIÇÃO]); sonda marcada INFO. Se o Red Team quiser restringir por relação, é uma política a mais.
- O4. Custo: funções `SECURITY DEFINER` por linha em toda política; medir na Fase 2. Não considero exagero de segurança, mas é o principal custo para o dev solo.
- O5. Correções minhas em sondas, declaradas: em `red-team-sondas-r1.sql` a RT1d mede o vínculo forjado (a semente da rodada 0 dá à clínica A leitura legítima do paciente pelo encaminhamento consentido); em `teste-rls-r1.sql` a sonda 680 passou a usar ENC_E2, porque ENC_E já via pacB legitimamente por E2.

## Rodada de revisão 2 (Executor): o que foi resolvido

Evidência (PostgreSQL 16.15 limpo, porta 5494, usuário não-root `pgtest`, `.pgexec2`, um cluster novo por bateria; runner `docs/arquitetura/evidencias/teste-r2.sh`):
- `modelo-v2-execucao-r2.log`: `modelo-v2.sql` com `ON_ERROR_STOP=1`, exit 0.
- `teste-rls-r2.log` (`teste-rls-r2.sql` = bateria r1 com 2 ajustes de CONTROLE declarados no cabeçalho, R2-A e R2-B; nenhuma sonda de ataque afrouxada): 1423 sondas, 0 falhas, 1281 ataques negados, 117 controles, 24 INFO; 0 tabelas alteradas. Sem ajuste: `teste-rls-r1-sem-ajuste-r2.log`, 2 falhas, exatamente os dois controles cujo pressuposto mudou.
- `teste-r1-independente-r2.log` (bateria do Testador; cópia `teste-r1-independente-r2.sql` com adaptações A1 a A6 no cabeçalho, todas de fixture ou de esperado mais restrito): 3613 casos, 0 falhas; seções [1] a [4] do runner do Testador, pgbench sem vazamento.
- `docs/seguranca/evidencias/red-team-sondas-r1-r2.log`: 26 de 26 negadas, 2 controles.
- `docs/seguranca/evidencias/red-team-sondas-r1-novas-r2.log` (única diferença da cópia executada: socket e porta dos `\!`, diff no log): N4c, N6a, N6b, N7a NEGADO; N4d NEGADO; N5b e N5c seguem passando (resíduo do dono, agora com `ALERTA_DDL_SAAS` no log do servidor, impresso no fim do log).
- `docs/arquitetura/evidencias/sondas-r2.sql` e `sondas-r2.log` (sondas novas desta rodada, papéis reais por `\c`, fluxos reais de link e código): 70 de 70 (item 1: 14; item 2: 16; item 3: 10; item 4: 9; item 5: 13; item 6: 4; item 7: 4).
- ERD archify: anotações de `paciente.telefone`, `sessao.link_paciente_id`, `agendamento.status` e cartão "Sessão (rodada 2)"; `finalize` com os 4 gates em pass (recibo antigo de browser-check removido por pertencer ao HTML anterior); PNG reexportado pelo menu Exportar do viewer. Arquitetura e lifecycle sem mudança de forma (nenhum módulo, evento ou estado novo).

Itens:
1. Testador F1 (link e envio após CANCELADO): `encaminhamento_aberto`; `link_consulta`, `paciente_pede_codigo` e `paciente_confirma_codigo` recusam caso em estado final; `encaminhamento_apos_transicao` revoga link ativo e marca FALHOU envio PENDENTE ao entrar em CANCELADO, EXPIRADO ou CONTRARREFERIDO; `jobs_envio_prepara` relê o status e não entrega segredo nem telefone (R2-1a a R2-1n; J-link 7 de 7). ADR-0030.
2. Testador F2 (agenda reativada): gatilho `agendamento_marca_autor` torna REALIZADO, FALTOU e CANCELADO finais (status e horário) e impede CONFIRMADO para AGENDADO (R2-2a a R2-2p; B-agenda 4 de 4). ADR-0027, máquina de estados seção 3a.
3. Testador F3 (usuário inativo): `sessao_valida` recusa sessão EQUIPE de usuário inativo, valendo para toda política e função (R2-3a a R2-3j; S-inativo 4 de 4). ADR-0023.
4. Red Team T-18: ADR-0036 (telefone é contato). Mesma pessoa só por HMAC do CPF ou nome normalizado + nascimento + telefone sem CPF divergente; sem CPF e sem nascimento nunca deduplica; CPF segue opcional no fluxo do link (R2-4a a R2-4i; N6a, N6b NEGADO). ADR-0029 aponta para o 0036.
5. Red Team I-19: `ator_encaminhamento()`; políticas e funções de paciente (encaminhamento, histórico por herança, agendamento, consentimento, anexo, T3, T10) exigem o caso do link da sessão (R2-5a a R2-5m; N7a NEGADO). ADR-0023 e ADR-0030.
6. Red Team R-07: texto do ADR-0027 corrigido (dono das tabelas e superusuário contornam gatilho e RLS); mitigação no banco por gatilhos de evento `saas_alerta_ddl_*` (log fora da transação, dono não desliga: R2-6a a R2-6d) e mitigação operacional registrada (dono NOLOGIN separado, migração só pelo pipeline, CI recusa DISABLE TRIGGER, NO FORCE, DROP POLICY, alerta de DDL fora do banco).
7. Red Team I-20: regra de nunca interpolar token em SQL (parâmetro ligado) no ADR-0026, item 7; no banco, `track_activities = off` e `log_parameter_max_length(_on_error) = 0` para `saas_app`, `saas_jobs` e `saas_auth` (só superusuário religa) (R2-7a a R2-7d; N4c NEGADO).

Documentos atualizados: `modelo-v2.sql`, `modelo-dados-v2.md`, `mapa-modulos.md`, `maquina-estados-encaminhamento.md`, ADR-0023, 0026, 0027, 0029, 0030, novo ADR-0036, `docs/adr/README.md`, ERD.

## Pendências da Fase 2 (Red Team r1, seção 4), registradas e não feitas nesta rodada
- E-09: credencial de `saas_jobs` fora do processo web (processo e segredo separados), registrar no ADR-0024. Resíduo N8 continua: quem tem a credencial de jobs recebe código em claro.
- E-10: callback OIDC valida assinatura, `iss`, `aud`, `exp`, `nonce` e MFA; `sessao_equipe_abre` recebe e grava o fator e recusa ADMIN e MEDICO sem MFA (resíduo N3c, N3e).
- I-21: oráculos de funções `SECURITY DEFINER` sem sessão (`rede_ligada` responde por qualquer clínica, N11a).
- Ajuste da O3: profissional sem `canal_verificado_em` e sem `usuario_id` fora de `profissional_ver` (manter visível à equipe da clínica que o vinculou e ao próprio encaminhador); teste na Fase 2 (N11d).
- R-07 no CI: o gate que recusa migração perigosa é do pipeline da Fase 2; o alerta no banco já existe.
- T-19 (Fase 3): REALIZADO e FALTOU só com `inicio <= now()` (N12); reconciliação de duplicatas de paciente (consequência do ADR-0036).
