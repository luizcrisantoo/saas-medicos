# ADR-0024: Papéis de banco separados para web, jobs e login; jobs só por funções estreitas

Status: Aceito na revisão da Fase 1 (rodada 1), sujeito ao Red Team
Data: 2026-11-10
Tarefa: t-fase1-arquitetura
Substitui: a decisão D2 da rodada 0 (dois papéis, `saas_owner` e `saas_app`), apontada pelo Avaliador como decisão sem ADR.

## Contexto
Na rodada 0 jobs, listeners e web usavam o mesmo papel `saas_app`, e "ser SISTEMA" era um texto em `app.papel`. Qualquer conexão declarava SISTEMA e reescrevia anexo (RT3). O Red Team exigiu papel de banco próprio para jobs e listeners e nenhuma política "SISTEMA vê tudo" (itens 2 e 18; S-04, T-06, E-08). O Avaliador apontou excesso de papéis de contexto na RLS.

## Decisão
| Papel | Login | Para quê | Privilégios |
|---|---|---|---|
| `saas_owner` | não | Dono das tabelas; migrações | Sujeito a FORCE RLS |
| `saas_funcoes` | não | Dono das funções `SECURITY DEFINER` | BYPASSRLS; SELECT, INSERT, UPDATE nas tabelas; nunca UPDATE em auditoria e histórico. Ninguém faz SET ROLE para ele |
| `saas_app` | sim | Aplicação web | Sem BYPASSRLS; GRANT por coluna onde há escrita; EXECUTE só nas funções web |
| `saas_jobs` | sim | Jobs e listeners | Nenhum privilégio em tabela; EXECUTE só nas 8 funções `jobs_*` |
| `saas_auth` | sim | Callback do login OIDC | Só EXECUTE em `sessao_equipe_abre` |

- Ações de sistema, uma função por ação, cada uma relendo o estado na fonte: `jobs_envios_pendentes`, `jobs_envio_link_paciente`, `jobs_envio_prepara`, `jobs_envio_resultado` (T2), `jobs_expirar_encaminhamentos` (T8), `jobs_consulta_realizada` (T5), `jobs_agendamento_desfeito` (T7), `jobs_anexo_varredura`. Cada função fica marcada para revisão do Red Team.
- `ALTER DEFAULT PRIVILEGES ... REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC`: função nova nasce inexecutável; o log de execução mostra 0 funções executáveis por PUBLIC.
- Os contextos de RLS da rodada 0 (ADMIN, RECEPCAO, MEDICO, ENCAMINHADOR, PACIENTE, PUBLICO_LINK, SISTEMA) viram três tipos de sessão (EQUIPE, PACIENTE, ENCAMINHADOR); PUBLICO_LINK e SISTEMA deixam de ser contexto de RLS e passam a ser funções.

## Alternativas descartadas
- Política por `current_user = 'saas_jobs'` com SELECT nas tabelas: devolve ao worker leitura ampla, o que o item 18 proíbe.
- Um único papel com `app.papel = SISTEMA`: provado inseguro (RT3).
- Dono das funções igual ao dono das tabelas: o dono está sob FORCE RLS e as funções precisariam de políticas próprias, de novo por papel.

## Consequências
- Credenciais distintas no gerenciador de segredos para `saas_app`, `saas_jobs` e `saas_auth` (ADR-0011, ADR-0012).
- O código de cada função `SECURITY DEFINER` é a barreira: `search_path` fixo, sem SQL dinâmico vindo de parâmetro, revisão do Red Team por função.
- Teste obrigatório na Fase 2: `saas_jobs` não lê nenhuma tabela e `saas_app` não executa nenhuma função `jobs_*` (sondas da seção jobs e r1-2 de `teste-rls-r1.log`).

## Fontes
- docs/agents/red-team-t-fase1-arquitetura.md, itens 2 e 18; docs/agents/avaliador-t-fase1-arquitetura.md (D2, complexidade)
- docs/arquitetura/modelo-v2.sql, seções 0, 13 e 16
- docs/arquitetura/evidencias/modelo-v2-execucao-r1.log (papéis e contagem de funções por papel)
