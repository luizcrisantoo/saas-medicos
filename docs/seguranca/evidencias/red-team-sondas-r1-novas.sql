-- red-team-sondas-r1-novas.sql : ataques do Red Team ao desenho NOVO da rodada 1
-- (sessao verificavel, papeis saas_app/saas_jobs/saas_auth/saas_owner/saas_funcoes,
-- funcoes SECURITY DEFINER, gatilhos). Alvo: docs/arquitetura/modelo-v2.sql (r1).
-- Execucao (PostgreSQL 16.15 descartavel, usuario de SO nao-root pgtest, porta 5495,
-- socket em /home/claude/saas-agenda/.pgrt, autenticacao trust so neste cluster):
--   psql -h $PWD/.pgrt -p 5495 -U pgtest -d postgres -c 'create database rt'
--   psql -h $PWD/.pgrt -p 5495 -U pgtest -d rt -v ON_ERROR_STOP=1 -f docs/arquitetura/modelo-v2.sql
--   psql -h $PWD/.pgrt -p 5495 -U pgtest -d rt -f docs/seguranca/evidencias/red-team-sondas-r1-novas.sql
-- Cada sonda conecta com o papel real (\c), para session_user e current_user serem os de producao.
-- Legenda no log: NEGADO = defesa funcionou; PASSOU = ataque funcionou; RESIDUAL = funciona por desenho.
\set ON_ERROR_STOP off
\pset pager off
\set QUIET on

\echo '================ SEMENTE (superusuario do cluster) ================'
SET search_path = saas, public;
INSERT INTO clinica(id,nome) VALUES ('aaaaaaaa-0000-0000-0000-000000000001','A'),('bbbbbbbb-0000-0000-0000-000000000001','B');
INSERT INTO flag_clinica(clinica_id,chave,ligada) VALUES ('aaaaaaaa-0000-0000-0000-000000000001','REDE_ENCAMINHAMENTO',true),('bbbbbbbb-0000-0000-0000-000000000001','REDE_ENCAMINHAMENTO',false);
INSERT INTO usuario(id,sub_oidc,nome,email) VALUES
 ('aaaaaaaa-0000-0000-0001-000000000001','admA','AdmA','adm@a'),
 ('aaaaaaaa-0000-0000-0001-000000000002','recA','RecA','rec@a');
INSERT INTO usuario_clinica(usuario_id,clinica_id,papel) VALUES
 ('aaaaaaaa-0000-0000-0001-000000000001','aaaaaaaa-0000-0000-0000-000000000001','ADMIN'),
 ('aaaaaaaa-0000-0000-0001-000000000002','aaaaaaaa-0000-0000-0000-000000000001','RECEPCAO');
INSERT INTO especialidade(id,nome) VALUES ('dddddddd-0000-0000-0000-000000000001','Ortopedia');
INSERT INTO clinica_especialidade VALUES ('aaaaaaaa-0000-0000-0000-000000000001','dddddddd-0000-0000-0000-000000000001');
INSERT INTO profissional(id,crm,crm_uf,nome,telefone,canal_verificado_em) VALUES
 ('eeeeeeee-0000-0000-0002-000000000001','999','PE','Dra Vitima (encaminha)','+5581999990001',now());
INSERT INTO profissional_clinica(id,profissional_id,clinica_id) VALUES
 ('aaaaaaaa-0000-0000-0004-000000000001','eeeeeeee-0000-0000-0002-000000000001','aaaaaaaa-0000-0000-0000-000000000001');
-- sessoes de teste (token conhecido, so na semente)
INSERT INTO sessao(token_hash,tipo,usuario_id,expira_em) VALUES
 (sha256(decode(repeat('aa',32),'hex')),'EQUIPE','aaaaaaaa-0000-0000-0001-000000000002',now()+interval '1 hour');
INSERT INTO sessao(token_hash,tipo,profissional_id,expira_em) VALUES
 (sha256(decode(repeat('ad',32),'hex')),'ENCAMINHADOR','eeeeeeee-0000-0000-0002-000000000001',now()+interval '1 hour');

\echo ''
\echo '================ N1. Catalogo: SECURITY DEFINER, search_path, PUBLIC ================'
\echo 'N1a SECURITY DEFINER sem search_path fixo (esperado 0)'
SELECT count(*) AS secdef_sem_search_path FROM pg_proc p
 WHERE p.pronamespace='saas'::regnamespace AND p.prosecdef
   AND NOT EXISTS (SELECT 1 FROM unnest(coalesce(p.proconfig,'{}')) c WHERE c LIKE 'search_path=%');
\echo 'N1b search_path das funcoes: public ou pg_temp antes de saas (esperado 0)'
SELECT count(*) AS search_path_inseguro FROM pg_proc p, unnest(p.proconfig) c
 WHERE p.pronamespace='saas'::regnamespace AND c LIKE 'search_path=%' AND c NOT LIKE 'search_path=saas, pg_temp';
\echo 'N1c funcoes de QUALQUER schema executaveis por saas_app/saas_jobs/saas_auth alcancaveis (schema com USAGE), fora de pg_catalog/information_schema'
SELECT r.rolname, n.nspname, count(*) AS funcoes
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  CROSS JOIN (VALUES ('saas_app'),('saas_jobs'),('saas_auth')) r(rolname)
 WHERE n.nspname NOT IN ('pg_catalog','information_schema')
   AND has_function_privilege(r.rolname, p.oid, 'EXECUTE')
   AND has_schema_privilege(r.rolname, n.oid, 'USAGE')
 GROUP BY 1,2 ORDER BY 1,2;
\echo 'N1d privilegios de schema e banco dos papeis de login'
SELECT r, has_schema_privilege(r,'public','USAGE') AS public_usage, has_schema_privilege(r,'public','CREATE') AS public_create,
       has_schema_privilege(r,'saas','CREATE') AS saas_create, has_database_privilege(r,'rt','TEMP') AS temp,
       has_database_privilege(r,'rt','CREATE') AS db_create
  FROM unnest(ARRAY['saas_app','saas_jobs','saas_auth']) r;
\echo 'N1e funcoes SECURITY DEFINER executaveis por saas_app que NAO exigem sessao (oraculo sem login?)'
SELECT p.proname FROM pg_proc p WHERE p.pronamespace='saas'::regnamespace AND p.prosecdef
   AND has_function_privilege('saas_app', p.oid, 'EXECUTE') ORDER BY 1;
\echo 'N1f membros de papeis saas_* (esperado: nenhum papel de login herda ou assume outro)'
SELECT m.rolname AS membro, g.rolname AS grupo FROM pg_auth_members am
  JOIN pg_roles m ON m.oid=am.member JOIN pg_roles g ON g.oid=am.roleid
 WHERE m.rolname LIKE 'saas_%' OR g.rolname LIKE 'saas_%';
\echo 'N1g parametros que o papel web poderia usar para desligar gatilho (esperado: nenhum GRANT SET)'
SELECT parname, paracl FROM pg_parameter_acl;

\echo ''
\echo '================ N2. Escalada saas_app -> outro papel ================'
\c rt saas_app
SET search_path = saas;
\echo 'N2a SET ROLE saas_funcoes (esperado NEGADO)'
SET ROLE saas_funcoes;
\echo 'N2b SET ROLE saas_owner (esperado NEGADO)'
SET ROLE saas_owner;
\echo 'N2c SET session_replication_role = replica (esperado NEGADO)'
SET session_replication_role = replica;
\echo 'N2d ler a tabela sessao (esperado NEGADO)'
SELECT count(*) FROM sessao;
\echo 'N2e chamar sessao_valida() direto (esperado NEGADO: sem EXECUTE)'
SELECT (sessao_valida()).token_hash;
\echo 'N2f chamar funcao de gatilho direto (esperado NEGADO)'
SELECT encaminhamento_apos_transicao();
\echo 'N2g chamar funcao jobs_* pelo papel web (esperado NEGADO)'
SELECT jobs_expirar_encaminhamentos();
\echo 'N2h sombra em pg_temp: tabela temporaria "sessao" com sessao forjada, depois ator_tipo() (esperado NULL)'
CREATE TEMP TABLE sessao (id uuid, token_hash bytea, tipo text, usuario_id uuid, paciente_id uuid, profissional_id uuid, link_paciente_id uuid, desafio_id uuid, criada_em timestamptz, expira_em timestamptz, encerrada_em timestamptz);
\echo '    (se o CREATE acima falhou, o papel web nao tem TEMP; senao segue)'
INSERT INTO pg_temp.sessao(id,token_hash,tipo,usuario_id,criada_em,expira_em)
 VALUES (gen_random_uuid(), sha256(decode(repeat('ff',32),'hex')),'EQUIPE','aaaaaaaa-0000-0000-0001-000000000001',now(),now()+interval '1 hour');
SELECT set_config('app.sessao', repeat('ff',32), false) IS NOT NULL AS guc;
SELECT coalesce(ator_tipo(),'NULL') AS n2h_ator_tipo_com_sessao_sombra;
RESET app.sessao;
DROP TABLE pg_temp.sessao;
\echo 'N2i movida para depois da N6 (precisa de encaminhamento existente)'

\echo ''
\echo '================ N3. saas_auth: escopo e escalada ================'
\c rt saas_auth
SET search_path = saas;
\echo 'N3a saas_auth le tabela (esperado NEGADO)'
SELECT count(*) FROM usuario;
\echo 'N3b saas_auth chama funcao web (esperado NEGADO)'
SELECT link_consulta(repeat('00',32));
\echo 'N3c saas_auth abre sessao de ADMIN so com o sub, sem prova OIDC (RESIDUAL do ADR-0023, objecao O1)'
SELECT sessao_equipe_abre('admA') AS tok_admin \gset
SELECT length(:'tok_admin') AS n3c_token_emitido_sem_prova;
\echo 'N3d sub inexistente (esperado erro generico)'
SELECT sessao_equipe_abre('nao-existe');
\c rt saas_app
SET search_path = saas;
\echo 'N3e token emitido pelo saas_auth usado pelo papel web como ADMIN de A (RESIDUAL: quem tem a credencial saas_auth vira qualquer usuario)'
BEGIN;
SELECT set_config('app.sessao', :'tok_admin', true), set_config('app.clinica_id','aaaaaaaa-0000-0000-0000-000000000001',true), set_config('app.papel','ADMIN',true);
SELECT count(*) AS n3e_usuarios_da_clinica_lidos_como_admin FROM usuario;
ROLLBACK;

\echo ''
\echo '================ N4. Sequestro de sessao ================'
\echo 'N4a entropia: 2000 tokens de novo_token(): tamanho, distintos, nibbles fixos'
\c rt pgtest
SET search_path = saas, public;
SELECT min(length(t)) AS min_len, max(length(t)) AS max_len, count(DISTINCT t) AS distintos,
       count(DISTINCT substr(t,13,1)) AS nibble13_distintos, count(DISTINCT substr(t,45,1)) AS nibble45_distintos
  FROM (SELECT novo_token() t FROM generate_series(1,2000)) x;
\echo 'N4b token por chute: 1000 tokens aleatorios contra sessoes reais (esperado 0)'
SELECT count(*) AS n4b_acertos FROM generate_series(1,1000) g
 WHERE EXISTS (SELECT 1 FROM sessao s WHERE s.token_hash = sha256(decode(novo_token(),'hex')));
\echo 'N4c token de sessao visivel a outra conexao do MESMO papel em pg_stat_activity'
\echo '    (vitima: conexao saas_app que grava o token com literal no SQL; atacante: injecao de SQL em outra conexao saas_app)'
\c rt saas_app
SET search_path = saas;
\! psql -h /home/claude/saas-agenda/.pgrt -p 5495 -U saas_app -d rt -qAtc "SELECT set_config('app.sessao','adadadadadadadadadadadadadadadadadadadadadadadadadadadadadadadad',false), pg_sleep(3)" >/dev/null 2>&1 &
SELECT pg_sleep(1);
SELECT CASE WHEN count(*) > 0 THEN 'PASSOU: token lido de outra conexao' ELSE 'NEGADO' END AS n4c_literal,
       max(left(query, 90)) AS amostra
  FROM pg_stat_activity WHERE usename='saas_app' AND pid <> pg_backend_pid() AND query ILIKE '%app.sessao%';
SELECT pg_sleep(3);
\echo 'N4d mesma vitima, mas token como parametro ligado ($1, como o JDBC faz com PreparedStatement)'
\! printf '%s\n' "SELECT set_config('app.sessao',\$1,false), pg_sleep(3) \bind adadadadadadadadadadadadadadadadadadadadadadadadadadadadadadadad \g" | psql -h /home/claude/saas-agenda/.pgrt -p 5495 -U saas_app -d rt -qAt >/dev/null 2>&1 &
SELECT pg_sleep(1);
SELECT CASE WHEN bool_or(query ILIKE '%adadadad%') THEN 'PASSOU' ELSE 'NEGADO: so o texto do comando' END AS n4d_bind,
       max(left(query, 90)) AS amostra
  FROM pg_stat_activity WHERE usename='saas_app' AND pid <> pg_backend_pid() AND query ILIKE '%app.sessao%';
SELECT pg_sleep(3);

\echo ''
\echo '================ N5. Dono das tabelas (credencial de migracao) desliga gatilho e RLS ================'
\c rt pgtest
SET search_path = saas, public;
-- semente: um encaminhamento com historico (T1)
SET session_replication_role = origin;
SELECT set_config('app.sessao', repeat('ad',32), false) IS NOT NULL;
SET ROLE saas_app;
SELECT encaminhamento_cria('Paciente N5','+5581911110005',NULL,NULL,NULL,'dddddddd-0000-0000-0000-000000000001','\x05','ROTINA') AS enc_n5 \gset
RESET ROLE;
RESET app.sessao;
SELECT count(*) AS historico_antes FROM historico_status_encaminhamento WHERE encaminhamento_id = :'enc_n5';
BEGIN;
SET LOCAL ROLE saas_owner;
\echo 'N5a dono tenta session_replication_role (esperado NEGADO)'
SAVEPOINT s; SET LOCAL session_replication_role = replica; ROLLBACK TO s;
\echo 'N5b dono desliga gatilhos e FORCE RLS do historico e apaga a trilha (ataque)'
ALTER TABLE historico_status_encaminhamento DISABLE TRIGGER USER;
ALTER TABLE historico_status_encaminhamento NO FORCE ROW LEVEL SECURITY;
DELETE FROM historico_status_encaminhamento WHERE encaminhamento_id = :'enc_n5';
SELECT count(*) AS n5b_historico_depois_do_delete FROM historico_status_encaminhamento WHERE encaminhamento_id = :'enc_n5';
\echo 'N5c dono desliga o gatilho de colunas imutaveis e troca o motivo (ataque)'
ALTER TABLE encaminhamento DISABLE TRIGGER encaminhamento_valida;
ALTER TABLE encaminhamento NO FORCE ROW LEVEL SECURITY;
UPDATE encaminhamento SET motivo_cifrado='\xff' WHERE id = :'enc_n5';
SELECT encode(motivo_cifrado,'hex') AS n5c_motivo_trocado FROM encaminhamento WHERE id = :'enc_n5';
ROLLBACK;
\echo 'N5d sem rastro no banco: auditoria nao registra DDL (contagem de eventos de auditoria com acao ALTER*)'
SELECT count(*) AS n5d_auditoria_de_ddl FROM evento_auditoria WHERE acao ILIKE 'ALTER%';

\echo ''
\echo '================ N6. Deduplicacao por telefone funde pessoas diferentes (dado de saude na pessoa errada) ================'
\c rt saas_app
SET search_path = saas;
\echo 'N6a encaminhador: Maria e o filho Joao, mesmo telefone da familia, sem CPF'
SELECT set_config('app.sessao', repeat('ad',32), false) IS NOT NULL;
SELECT encaminhamento_cria('Maria da Silva','+5581900000077',DATE '1955-03-01',NULL,NULL,'dddddddd-0000-0000-0000-000000000001','\x0a','ROTINA') AS enc_maria \gset
SELECT encaminhamento_cria('Joao da Silva (filho)','+5581900000077',DATE '2015-07-09',NULL,NULL,'dddddddd-0000-0000-0000-000000000001','\x0b','URGENTE') AS enc_joao \gset
SELECT CASE WHEN count(DISTINCT paciente_id)=1 THEN 'PASSOU: os dois casos no MESMO paciente' ELSE 'NEGADO' END AS n6a,
       count(DISTINCT paciente_id) AS pacientes
  FROM encaminhamento WHERE id IN (:'enc_maria', :'enc_joao');
RESET app.sessao;

\echo 'N2i origem (sessao valida) forja saas.transicao=T2 e faz UPDATE direto CRIADO -> ENVIADO_AO_PACIENTE (esperado NEGADO)'
BEGIN;
SELECT set_config('app.sessao', repeat('ad',32), true) IS NOT NULL;
SELECT set_config('saas.transicao','T2',true);
UPDATE encaminhamento SET status='ENVIADO_AO_PACIENTE' WHERE id = :'enc_maria';
ROLLBACK;
SELECT status AS n2i_status_continua FROM encaminhamento WHERE id = :'enc_maria' AND set_config('app.sessao', repeat('ad',32), false) IS NOT NULL;
RESET app.sessao;
\echo 'N6b recepcao A cadastra Maria e depois Joao com o mesmo telefone, sem CPF'
BEGIN;
SELECT set_config('app.sessao', repeat('aa',32), true), set_config('app.clinica_id','aaaaaaaa-0000-0000-0000-000000000001',true), set_config('app.papel','RECEPCAO',true);
SELECT paciente_cadastra_na_clinica('Maria Souza','+5581900000088',DATE '1950-01-01',NULL,NULL) AS p1 \gset
SELECT paciente_cadastra_na_clinica('Pedro Souza (neto)','+5581900000088',DATE '2018-01-01',NULL,NULL) AS p2 \gset
SELECT CASE WHEN :'p1' = :'p2' THEN 'PASSOU: Pedro recebeu o id da Maria (nome ignorado)' ELSE 'NEGADO' END AS n6b,
       (SELECT nome FROM paciente WHERE id = :'p2') AS nome_gravado_para_pedro;
COMMIT;

\echo ''
\echo '================ N7. Fluxo real do link + sessao de paciente com escopo de PESSOA, nao de caso ================'
\c rt saas_jobs
SET search_path = saas;
SELECT jobs_envio_link_paciente(:'enc_maria') AS envio_link \gset
SELECT segredo AS tok_link FROM jobs_envio_prepara(:'envio_link') \gset
SELECT jobs_envio_resultado(:'envio_link','ACEITO','prov-1') AS t2_ok;
\c rt saas_app
SET search_path = saas;
SELECT paciente_pede_codigo(:'tok_link') AS pediu;
\c rt saas_jobs
SET search_path = saas;
SELECT envio_id AS envio_cod FROM jobs_envios_pendentes(50) WHERE finalidade='CODIGO_PACIENTE' LIMIT 1 \gset
SELECT segredo AS cod FROM jobs_envio_prepara(:'envio_cod') \gset
\c rt saas_app
SET search_path = saas;
SELECT paciente_confirma_codigo(:'tok_link', :'cod') AS sess_maria \gset
SELECT set_config('app.sessao', :'sess_maria', false) IS NOT NULL;
\echo 'N7a sessao aberta pelo link do caso da MARIA le o caso do JOAO (esperado pelo desenho: so o caso do link)'
SELECT CASE WHEN count(*) FILTER (WHERE id = :'enc_joao') > 0 THEN 'PASSOU: le caso de outra pessoa' ELSE 'NEGADO' END AS n7a,
       count(*) AS encaminhamentos_visiveis, max(urgencia) FILTER (WHERE id = :'enc_joao') AS urgencia_do_joao
  FROM encaminhamento;
RESET app.sessao;

\echo ''
\echo '================ N8. Credencial saas_jobs = chave mestra de toda identidade fora da equipe ================'
\c rt saas_app
SET search_path = saas;
\echo 'N8a atacante (sem sessao) pede codigo para o CRM publico da vitima pelo endpoint publico'
SELECT encaminhador_pede_codigo('999','PE') AS desafio \gset
\c rt saas_jobs
SET search_path = saas;
\echo 'N8b com a credencial do worker, prepara o envio e recebe o codigo em claro'
SELECT envio_id AS envio_enc FROM jobs_envios_pendentes(50) WHERE finalidade='CODIGO_ENCAMINHADOR' LIMIT 1 \gset
SELECT segredo AS cod_enc FROM jobs_envio_prepara(:'envio_enc') \gset
\c rt saas_app
SET search_path = saas;
SELECT encaminhador_confirma_codigo(:'desafio', :'cod_enc') AS sess_vitima \gset
SELECT set_config('app.sessao', :'sess_vitima', false) IS NOT NULL;
SELECT CASE WHEN count(*) > 0 THEN 'RESIDUAL: casos da medica lidos com credencial de jobs' ELSE 'NEGADO' END AS n8c, count(*) AS casos
  FROM encaminhamento;
RESET app.sessao;

\echo ''
\echo '================ N9. Cadastro de encaminhador: oraculo de CRM e envio em massa a telefone de terceiro ================'
\c rt saas_app
SET search_path = saas;
SELECT now() AS t9 \gset
\echo 'N9a CRM existente (999/PE) e CRM novo: o efeito colateral (mensagem ao telefone informado) diferencia'
SELECT encaminhador_cadastra('999','PE','Qualquer','+5581988880000',NULL) IS NOT NULL AS tok1;
SELECT encaminhador_cadastra('123456','PE','Squatter','+5581988880000',NULL) IS NOT NULL AS tok2;
\c rt pgtest
SET search_path = saas, public;
SELECT p.crm, count(e.id) AS mensagens_geradas_pelo_cadastro
  FROM profissional p LEFT JOIN envio_notificacao e ON e.destinatario_id = p.id AND e.finalidade='CODIGO_ENCAMINHADOR' AND e.criado_em >= :'t9'
 WHERE p.telefone = '+5581988880000' OR p.crm='999' GROUP BY p.crm ORDER BY 1;
\echo 'N9b 30 CRMs inventados com o telefone de uma vitima: quantas mensagens saem (esperado: teto por telefone)'
\c rt saas_app
SET search_path = saas;
SELECT count(encaminhador_cadastra('9'||g::text,'SP','x','+5511977770000',NULL)) FROM generate_series(1,30) g;
\c rt pgtest
SET search_path = saas, public;
SELECT CASE WHEN count(*) >= 30 THEN 'PASSOU: sem teto por telefone de destino' ELSE 'NEGADO' END AS n9b, count(*) AS mensagens_enfileiradas
  FROM envio_notificacao e JOIN profissional p ON p.id = e.destinatario_id WHERE p.telefone='+5511977770000';
\echo 'N9c o medico verdadeiro do CRM 123456/PE tenta se cadastrar depois do squatter (esperado: algum caminho)'
\c rt saas_app
SET search_path = saas;
SELECT encaminhador_cadastra('123456','PE','Medico verdadeiro','+5581900001234',NULL) IS NOT NULL AS tok;
\c rt pgtest
SET search_path = saas, public;
SELECT CASE WHEN count(*) = 0 THEN 'PASSOU: dono real bloqueado, nenhum codigo ao telefone dele' ELSE 'NEGADO' END AS n9c
  FROM envio_notificacao e JOIN profissional p ON p.id=e.destinatario_id WHERE p.crm='123456' AND p.telefone='+5581900001234';

\echo ''
\echo '================ N10. Bloqueio permanente do paciente por quem tem o link ================'
\c rt saas_jobs
SET search_path = saas;
SELECT jobs_envio_link_paciente(:'enc_joao') AS envio_l2 \gset
SELECT segredo AS tok_l2 FROM jobs_envio_prepara(:'envio_l2') \gset
SELECT jobs_envio_resultado(:'envio_l2','ACEITO','prov-2');
\c rt saas_app
SET search_path = saas;
\echo 'N10a quem recebeu o link encaminhado (grupo da familia) erra 10 vezes'
SELECT count(paciente_confirma_codigo(:'tok_l2', lpad(g::text,6,'0'))) AS sessoes_abertas FROM generate_series(1,10) g;
\echo 'N10b link reemitido e codigo certo: o paciente legitimo entra? (esperado pelo ADR-0030: nao; caminho de recuperacao: nenhum)'
\c rt saas_jobs
SET search_path = saas;
SELECT jobs_envio_link_paciente(:'enc_joao') AS envio_l3 \gset
SELECT segredo AS tok_l3 FROM jobs_envio_prepara(:'envio_l3') \gset
\c rt saas_app
SET search_path = saas;
SELECT paciente_pede_codigo(:'tok_l3') AS pediu;
\c rt saas_jobs
SET search_path = saas;
SELECT envio_id AS envio_c3 FROM jobs_envios_pendentes(50) WHERE finalidade='CODIGO_PACIENTE' LIMIT 1 \gset
SELECT segredo AS cod3 FROM jobs_envio_prepara(:'envio_c3') \gset
\c rt saas_app
SET search_path = saas;
SELECT CASE WHEN paciente_confirma_codigo(:'tok_l3', :'cod3') IS NULL THEN 'PASSOU: paciente legitimo bloqueado para sempre neste caso' ELSE 'NEGADO' END AS n10b;

\echo ''
\echo '================ N11. Oraculos de funcoes SECURITY DEFINER sem sessao ================'
\c rt saas_app
SET search_path = saas;
RESET app.sessao;
\echo 'N11a rede_ligada(uuid) sem sessao nenhuma: responde por qualquer clinica'
SELECT rede_ligada('aaaaaaaa-0000-0000-0000-000000000001') AS a, rede_ligada('bbbbbbbb-0000-0000-0000-000000000001') AS b;
\echo 'N11b consentimento_ativo e pode_contrarreferenciar sem sessao (esperado false)'
SELECT consentimento_ativo(:'enc_maria','aaaaaaaa-0000-0000-0000-000000000001') AS c, pode_contrarreferenciar(:'enc_maria') AS p;
\echo 'N11c transicao_cancelamento com linha forjada pelo chamador (so devolve rotulo; esperado NULL sem sessao)'
SELECT transicao_cancelamento(ROW(gen_random_uuid(),'eeeeeeee-0000-0000-0002-000000000001',gen_random_uuid(),gen_random_uuid(),NULL,NULL,'\x00','ROTINA','CRIADO',now(),now(),now())::encaminhamento) AS rotulo;
\echo 'N11d sessao de PACIENTE lista o diretorio de medicos da rede (objecao O3)'
SELECT set_config('app.sessao', :'sess_maria', false) IS NOT NULL;
SELECT count(*) AS n11d_profissionais_visiveis_ao_paciente, count(*) FILTER (WHERE canal_verificado_em IS NULL) AS nao_verificados
  FROM profissional;
RESET app.sessao;

\echo ''
\echo '================ N12. Agenda: status livre para a equipe (entrada de T5) ================'
BEGIN;
SELECT set_config('app.sessao', repeat('aa',32), true), set_config('app.clinica_id','aaaaaaaa-0000-0000-0000-000000000001',true), set_config('app.papel','RECEPCAO',true);
INSERT INTO agendamento(clinica_id,profissional_clinica_id,paciente_id,inicio,fim,origem,chave_idempotencia)
 VALUES ('aaaaaaaa-0000-0000-0000-000000000001','aaaaaaaa-0000-0000-0004-000000000001',:'p1',now()+interval '10 days',now()+interval '10 days 30 minutes','RECEPCAO','n12');
UPDATE agendamento SET status='REALIZADO' WHERE chave_idempotencia='n12';
UPDATE agendamento SET status='AGENDADO' WHERE chave_idempotencia='n12';
SELECT CASE WHEN status='AGENDADO' THEN 'PASSOU: consulta futura marcada REALIZADO e depois desfeita' ELSE 'NEGADO' END AS n12 FROM agendamento WHERE chave_idempotencia='n12';
ROLLBACK;

\echo ''
\echo '================ FIM ================'
