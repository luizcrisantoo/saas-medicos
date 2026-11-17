# ADR-0026: Proteção de dados (cifra na aplicação, chaves, logs e links)

Status: Aceito na revisão da Fase 1 (rodada 1); item 7 acrescentado na rodada 2 (Red Team I-20)
Data: 2026-11-10
Tarefa: t-fase1-arquitetura

## Contexto
A linha "Proteção de dados" da tabela de decisões do briefing não tinha ADR próprio (Avaliador, critério 7). O Red Team acrescentou requisitos de link e de log (item 19; STRIDE I-07, I-17).

## Decisão
1. Cifra na aplicação: `paciente.cpf_cifrado`, `encaminhamento.motivo_cifrado`, `contrarreferencia.conduta_cifrada` e `anexo_encaminhamento.nome_original_cifrado` são cifrados por envelope (chave de dados por registro, chave mestra no KMS da nuvem). O banco nunca vê texto claro. Busca por CPF só por HMAC com chave do KMS (`cpf_hash`, sem UNIQUE, ADR-0017).
2. Em repouso e em trânsito: banco e bucket com criptografia do provedor; TLS em toda conexão, inclusive aplicação e banco.
3. Logs e APM: sem corpo de requisição, sem cabeçalho `Cookie` e `Authorization`, sem parâmetros de SQL (`log_parameter_max_length = 0` [SUPOSIÇÃO de parâmetro do Postgres gerenciado]); telefone, e-mail e CPF mascarados; entidades sensíveis sem `toString` com campos; erro de banco mapeado para código genérico antes de sair da API.
4. Links do paciente: o GET da página do link não consome nem mostra dado; só chama `link_consulta` (válido ou não). O token é trocado por sessão num POST com o código (`paciente_confirma_codigo`), seguido de redirecionamento para URL sem token. Página com `Referrer-Policy: no-referrer`, sem recurso de terceiro, `Cache-Control: no-store`.
5. Token de link, token de sessão, desafio e código: só o hash no banco; nunca em evento, log, APM ou mensagem além do próprio envio ao destinatário.
6. Teste da Definição de pronto: fluxo completo com marcadores fictícios em motivo, CPF e token; grep dos marcadores em todos os logs e no APM deve voltar vazio.
7. Token nunca no texto do SQL (rodada 2, Red Team I-20). Regra da aplicação: todo segredo (`app.sessao`, token de link, desafio, código) entra no banco só como parâmetro ligado (`PreparedStatement`, `$1`), inclusive no `set_config('app.sessao', ?, true)` do início da transação. Interpolar token em string SQL é defeito de segurança; o revisor de código e um teste de arquitetura (busca por `set_config('app.sessao','` com literal) recusam. Risco que a regra cobre: `pg_stat_activity` mostra o texto do comando de toda conexão do MESMO papel a qualquer outra conexão desse papel; uma injeção de SQL numa conexão `saas_app` leria o token das outras (N4c). Defesa no banco, para quando a regra falhar (`modelo-v2.sql`, seção 16):
   - `ALTER ROLE saas_app|saas_jobs|saas_auth SET track_activities = off`: esses papéis não publicam o texto do comando em `pg_stat_activity`; só o superusuário religa (sonda R2-7b). Custo: monitorar consulta desses papéis passa a ser por `pg_stat_statements` (normaliza literal em `$n`) e pelo rastreio da aplicação.
   - `log_parameter_max_length = 0` e `log_parameter_max_length_on_error = 0` por papel: valor de parâmetro ligado nunca vai ao log do servidor.
   - Provas: `red-team-sondas-r1-novas-r2.log`, N4c e N4d NEGADO; `sondas-r2.log`, R2-7a a R2-7d.

## Alternativas descartadas
- Cifra só em repouso do banco (TDE do provedor): quem lê o banco lê o motivo.
- `pgcrypto` com chave no banco: chave e dado no mesmo lugar.

## Consequências
- Busca textual em motivo e conduta não existe; relatórios usam só campos estruturados.
- Rotação de chave mestra no KMS fica para o ADR-0012 (nuvem).

## Fontes
- docs/briefing.md: Decisões de arquitetura (Proteção de dados); Segurança da aplicação; Definição de pronto
- docs/agents/red-team-t-fase1-arquitetura.md, item 19; docs/seguranca/stride-encaminhamento.md, I-07, I-17
- docs/agents/avaliador-t-fase1-arquitetura.md, critério 7
- docs/agents/red-team-t-fase1-arquitetura-r1.md, I-20 (N4c, N4d)
- PostgreSQL 16, Run-time Statistics (`track_activities`, só superusuário altera) e pg_stat_activity (texto do comando visível ao mesmo papel): https://www.postgresql.org/docs/16/runtime-config-statistics.html, https://www.postgresql.org/docs/16/monitoring-stats.html
