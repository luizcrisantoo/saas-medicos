# ADR-0023: Sessão verificável no banco para todo ator

Status: Aceito na revisão da Fase 1 (rodada 1), sujeito ao Red Team
Data: 2026-11-10
Tarefa: t-fase1-arquitetura

## Contexto
Na rodada 0 a RLS conferia no banco só a equipe (`eh_equipe`). Paciente, encaminhador, MEDICO na origem e SISTEMA eram texto de GUC (`app.papel`, `app.paciente_id`, `app.profissional_id`) gravado pelo mesmo papel de banco que atende a internet. O Red Team provou leitura de caso alheio só mudando GUC (RT4, RT5) e pediu contexto verificável para todo ator (docs/agents/red-team-t-fase1-arquitetura.md, item 1; STRIDE E-01, S-03).

## Decisão
- A única identidade que o banco aceita é uma linha da tabela `sessao` (tipo EQUIPE, PACIENTE ou ENCAMINHADOR), apresentada pelo token de sessão em claro em `app.sessao`. O banco calcula `sha256` do token e confere validade (`expira_em`, `encerrada_em`). Sem sessão válida, toda política devolve 0 linhas.
- `app.usuario`, `app.paciente_id`, `app.profissional_id` e `app.link_token_hash` deixam de existir no desenho; se a aplicação os gravar, nada muda (provado nas sondas `ADM_A_SEM_SESSAO`, `PAC_A_FINGE_PACB`, `ENC_E2_FINGE_PE`, `MED_A_FINGE_PB` de `teste-rls-r1.log`).
- `app.clinica_id` e `app.papel` só dizem em qual clínica e com qual papel um membro da equipe age; `eh_equipe` confere os dois contra `usuario_clinica` e a sessão EQUIPE.
- O profissional do ator é derivado: ENCAMINHADOR pela sessão; MEDICO por `profissional.usuario_id` da sessão com `profissional_clinica` ativo na clínica do contexto (Red Team, item 3).
- Sessões nascem só por funções que exigem prova: `sessao_equipe_abre` (papel `saas_auth`, depois do OIDC), `paciente_confirma_codigo` (token do link mais código) e `encaminhador_confirma_codigo` (desafio mais código). O papel web não tem privilégio na tabela `sessao`.
- Escopo da sessão (rodada 2): sessão EQUIPE de usuário com `ativo = false` deixa de valer na hora para toda política e função, conferido em `sessao_valida` (Testador F3). Sessão PACIENTE vale para o CASO do link que a abriu, não para a pessoa: `ator_encaminhamento()` devolve o encaminhamento do link da sessão e toda política e função de paciente sobre encaminhamento, histórico, agendamento, consentimento, anexo, T3 e T10 exige esse caso (Red Team I-19). Quem recebeu o link de um caso (filho, cuidador, grupo da família) não lê os outros casos da mesma pessoa. O cadastro da própria pessoa (`paciente_proprio`) continua legível.
- Validade máxima: paciente 30 minutos, equipe e encaminhador 12 horas (CHECK na tabela). [SUPOSIÇÃO: valores de rascunho; revisar com o provedor do ADR-0007]

## Alternativas descartadas
- Manter GUC de identidade e confiar no montador de contexto: é exatamente o que o Red Team derrubou.
- Um papel de banco por usuário: inviável com pool de conexões e milhares de pacientes.
- Assinar o contexto com HMAC e conferir no banco: exige segredo dentro do banco ou extensão; a tabela de sessão resolve com SQL puro e permite revogar (logout).

## Consequências
- Cada requisição autenticada grava `app.sessao` (local à transação) com o token do cookie; o token nunca vai para log (ADR-0026).
- Uma injeção de SQL no papel web só age com a sessão da própria requisição; sessões de outros não são legíveis (sem GRANT em `sessao`).
- Resíduo aceito: o componente de login (`saas_auth`) confia no token OIDC validado pela aplicação; o banco não valida JWT. Mitigação: credencial própria e uma única função (ADR-0024).
- Custo: funções `SECURITY DEFINER` chamadas por linha nas políticas. Medir na Fase 2 com dados de volume; se pesar, ler a sessão uma vez por transação.

## Fontes
- docs/agents/red-team-t-fase1-arquitetura.md, itens 1 e 3
- docs/seguranca/stride-encaminhamento.md, seção 3 e E-01, S-03, S-05
- docs/arquitetura/modelo-v2.sql, seções 5 (tabela `sessao`) e 10 (funções de contexto)
- docs/arquitetura/evidencias/teste-rls-r1.log, seção r1-1
