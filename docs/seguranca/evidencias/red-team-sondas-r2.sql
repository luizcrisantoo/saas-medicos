-- red-team-sondas-r2.sql : ataques do Red Team ao desenho da rodada 2 (ADR-0036 identidade
-- do paciente sem dedup por telefone; ADR-0023/0030 sessao do paciente por caso; ADR-0026
-- item 7 e papeis sem track_activities; ADR-0027 alerta de DDL por gatilho de evento).
-- Alvo: docs/arquitetura/modelo-v2.sql (r2).
-- Execucao (PostgreSQL 16.15 descartavel, usuario de SO nao-root pgtest, porta 5492,
-- socket em /home/claude/saas-agenda/.pgrt2, autenticacao trust so neste cluster):
--   psql -h $PWD/.pgrt2 -p 5492 -U pgtest -d postgres -c 'create database r2'
--   psql -h $PWD/.pgrt2 -p 5492 -U pgtest -d r2 -v ON_ERROR_STOP=1 -f docs/arquitetura/modelo-v2.sql
--   psql -h $PWD/.pgrt2 -p 5492 -U pgtest -d r2 -f docs/seguranca/evidencias/red-team-sondas-r2.sql
-- O trecho do log do servidor com os alertas de DDL (R2N9) e as sondas de arranque (R2N8)
-- sao anexados ao .log pelo comando registrado no cabecalho do proprio .log.
-- Cada sonda conecta com o papel real (\c). Link, codigo e sessao de paciente pelo caminho
-- real (jobs_* com saas_jobs, paciente_* com saas_app).
-- Legenda: NEGADO = defesa funcionou; PASSOU = ataque funcionou; CONTROLE = caso legitimo.
\set ON_ERROR_STOP off
\pset pager off
\set QUIET on

\echo '================ SEMENTE (superusuario do cluster) ================'
SET search_path = saas, public;
\set cA 'aaaaaaaa-0000-0000-0000-000000000001'
\set cB 'bbbbbbbb-0000-0000-0000-000000000001'
\set esp 'dddddddd-0000-0000-0000-000000000001'
\set pcB 'bbbbbbbb-0000-0000-0004-000000000001'
INSERT INTO clinica(id,nome) VALUES (:'cA','A'),(:'cB','B');
INSERT INTO flag_clinica(clinica_id,chave,ligada) VALUES (:'cA','REDE_ENCAMINHAMENTO',true),(:'cB','REDE_ENCAMINHAMENTO',true);
INSERT INTO especialidade(id,nome) VALUES (:'esp','Ortopedia');
INSERT INTO clinica_especialidade VALUES (:'cA',:'esp'),(:'cB',:'esp');
INSERT INTO usuario(id,sub_oidc,nome,email) VALUES
 ('aaaaaaaa-0000-0000-0001-000000000002','recA','RecA','rec@a'),
 ('bbbbbbbb-0000-0000-0001-000000000002','recB','RecB','rec@b');
INSERT INTO usuario_clinica(usuario_id,clinica_id,papel) VALUES
 ('aaaaaaaa-0000-0000-0001-000000000002',:'cA','RECEPCAO'),
 ('bbbbbbbb-0000-0000-0001-000000000002',:'cB','RECEPCAO');
INSERT INTO profissional(id,crm,crm_uf,nome,telefone,canal_verificado_em) VALUES
 ('eeeeeeee-0000-0000-0002-000000000001','111','PE','Dr Origem 1','+5581999990001',now()),
 ('eeeeeeee-0000-0000-0002-000000000002','222','PE','Dra Origem 2','+5581999990002',now()),
 ('eeeeeeee-0000-0000-0002-000000000003','333','PE','Dr Ortopedista B','+5581999990003',now());
INSERT INTO profissional_clinica(id,profissional_id,clinica_id,recebe_encaminhamento) VALUES
 (:'pcB','eeeeeeee-0000-0000-0002-000000000003',:'cB',true);
-- sessoes de teste com token conhecido (so na semente): ad = origem 1, bd = origem 2, aa = recepcao A, bb = recepcao B
INSERT INTO sessao(token_hash,tipo,profissional_id,expira_em) VALUES
 (sha256(decode(repeat('ad',32),'hex')),'ENCAMINHADOR','eeeeeeee-0000-0000-0002-000000000001',now()+interval '6 hours'),
 (sha256(decode(repeat('bd',32),'hex')),'ENCAMINHADOR','eeeeeeee-0000-0000-0002-000000000002',now()+interval '6 hours');
INSERT INTO sessao(token_hash,tipo,usuario_id,expira_em) VALUES
 (sha256(decode(repeat('aa',32),'hex')),'EQUIPE','aaaaaaaa-0000-0000-0001-000000000002',now()+interval '6 hours'),
 (sha256(decode(repeat('bb',32),'hex')),'EQUIPE','bbbbbbbb-0000-0000-0001-000000000002',now()+interval '6 hours');

\echo ''
\echo '================ R2N1. T-18 por outro caminho: CPF do responsavel (ADR-0036, item 2a) ================'
\echo '  Cenario: formulario aceita "CPF do paciente ou responsavel" [SUPOSICAO: pratica comum para menor sem CPF].'
\echo '  Origem 1 encaminha a mae com o CPF dela; depois o filho, com outro nome, outra data e o MESMO CPF.'
\c r2 saas_app
SET search_path = saas;
SELECT set_config('app.sessao', repeat('ad',32), false) IS NOT NULL AS sessao_origem1;
SELECT encaminhamento_cria('Lucia Ramos','+5581900001111',DATE '1984-02-02','\xc1','\xc1c1','dddddddd-0000-0000-0000-000000000001','\x01','ROTINA') AS enc_lucia \gset
SELECT encaminhamento_cria('Davi Ramos','+5581900001111',DATE '2017-06-06','\xc1','\xc1c1','dddddddd-0000-0000-0000-000000000001','\x02','URGENTE') AS enc_davi \gset
\echo 'R2N1a filho e mae com o mesmo CPF e nome e nascimento diferentes (esperado: 2 pacientes)'
SELECT CASE WHEN count(DISTINCT e.paciente_id) = 1 THEN 'PASSOU: caso do filho gravado na mae' ELSE 'NEGADO' END AS r2n1a,
       count(DISTINCT e.paciente_id) AS pacientes,
       max(p.nome) FILTER (WHERE e.id = :'enc_davi') AS nome_do_paciente_no_caso_do_davi,
       max(p.data_nascimento) FILTER (WHERE e.id = :'enc_davi') AS nascimento_no_caso_do_davi
  FROM encaminhamento e JOIN paciente p ON p.id = e.paciente_id WHERE e.id IN (:'enc_lucia', :'enc_davi');
\echo 'R2N1b controle (ADR-0036 2b): mesmo nome normalizado, data e telefone, sem CPF, mesmo encaminhador (esperado: 1)'
SELECT encaminhamento_cria('  LUCIA   ramos ','+5581900001111',DATE '1984-02-02',NULL,NULL,'dddddddd-0000-0000-0000-000000000001','\x03','ROTINA') AS enc_lucia2 \gset
SELECT CASE WHEN count(DISTINCT paciente_id) = 1 THEN 'CONTROLE ok' ELSE 'CONTROLE falhou' END AS r2n1b, count(DISTINCT paciente_id) AS pacientes
  FROM encaminhamento WHERE id IN (:'enc_lucia', :'enc_lucia2');
RESET app.sessao;
\echo 'R2N1c outro encaminhador digita os mesmos nome, data, telefone e CPF da Lucia (esperado: registro novo, escopo do ADR-0029)'
SELECT set_config('app.sessao', repeat('bd',32), false) IS NOT NULL AS sessao_origem2;
SELECT encaminhamento_cria('Lucia Ramos','+5581900001111',DATE '1984-02-02','\xc1','\xc1c1','dddddddd-0000-0000-0000-000000000001','\x04','ROTINA') AS enc_lucia_o2 \gset
RESET app.sessao;
\c r2 pgtest
SET search_path = saas, public;
SELECT CASE WHEN count(DISTINCT paciente_id) = 2 THEN 'NEGADO' ELSE 'PASSOU: outro medico alcancou o cadastro' END AS r2n1c,
       count(DISTINCT paciente_id) AS pacientes
  FROM encaminhamento WHERE id IN (:'enc_lucia', :'enc_lucia_o2');

\echo ''
\echo '================ R2N2. Telefone informado descartado quando o CPF casa (link vai ao numero antigo) ================'
\c r2 saas_app
SET search_path = saas;
SELECT set_config('app.sessao', repeat('ad',32), false) IS NOT NULL AS sessao_origem1;
SELECT encaminhamento_cria('Rita Lima','+5581900002222',DATE '1970-01-01','\xc2','\xc2c2','dddddddd-0000-0000-0000-000000000001','\x05','ROTINA') AS enc_rita1 \gset
\echo '  Meses depois a Rita troca de numero; o medico digita o numero NOVO e o mesmo CPF'
SELECT encaminhamento_cria('Rita Lima','+5581977773333',DATE '1970-01-01','\xc2','\xc2c2','dddddddd-0000-0000-0000-000000000001','\x06','URGENTE') AS enc_rita2 \gset
RESET app.sessao;
\c r2 saas_jobs
SET search_path = saas;
SELECT jobs_envio_link_paciente(:'enc_rita2') AS env_rita2 \gset
SELECT contato AS contato_rita2 FROM jobs_envio_prepara(:'env_rita2') \gset
\echo 'R2N2a numero para onde vai o link do caso novo (esperado: o numero digitado agora, +5581977773333)'
SELECT CASE WHEN :'contato_rita2' = '+5581977773333' THEN 'NEGADO' ELSE 'PASSOU: link e codigo vao ao numero antigo, sem aviso ao medico' END AS r2n2a,
       :'contato_rita2' AS contato_usado;

\echo ''
\echo '================ R2N3. Recepcao: casamento por CPF devolve outra pessoa em silencio ================'
\c r2 saas_app
SET search_path = saas;
BEGIN;
SELECT set_config('app.sessao', repeat('aa',32), true) IS NOT NULL, set_config('app.clinica_id', :'cA', true) IS NOT NULL, set_config('app.papel','RECEPCAO',true);
SELECT paciente_cadastra_na_clinica('Jose Alves','+5581900004444',DATE '1960-05-05','\xc3','\xc3c3') AS p_jose \gset
\echo 'R2N3a cadastro de outra pessoa (nome, data, telefone diferentes) com CPF igual por digitacao ou CPF de responsavel'
SELECT paciente_cadastra_na_clinica('Ana Alves (neta)','+5581900005555',DATE '2012-09-09','\xc3','\xc3c3') AS p_ana \gset
SELECT CASE WHEN :'p_jose' = :'p_ana' THEN 'PASSOU: devolveu o id do Jose sem sinal de conflito' ELSE 'NEGADO' END AS r2n3a,
       (SELECT nome FROM paciente WHERE id = :'p_ana') AS nome_do_registro_devolvido_para_ana;
COMMIT;

\echo ''
\echo '================ R2N4. Sessao por caso com telefone da familia: o caso do filho por outros caminhos ================'
\c r2 saas_app
SET search_path = saas;
SELECT set_config('app.sessao', repeat('ad',32), false) IS NOT NULL AS sessao_origem1;
SELECT encaminhamento_cria('Maria Costa','+5581900006666',DATE '1950-03-03',NULL,NULL,'dddddddd-0000-0000-0000-000000000001','\x07','ROTINA') AS enc_maria \gset
SELECT encaminhamento_cria('Joao Costa','+5581900006666',DATE '2014-04-04',NULL,NULL,'dddddddd-0000-0000-0000-000000000001','\x08','URGENTE') AS enc_joao \gset
RESET app.sessao;
\c r2 pgtest
SELECT paciente_id AS pid_joao FROM saas.encaminhamento WHERE id = :'enc_joao' \gset
-- link + codigo + sessao: Maria
\c r2 saas_jobs
SET search_path = saas;
SELECT jobs_envio_link_paciente(:'enc_maria') AS env_m \gset
SELECT contato AS contato_m, segredo AS tok_m FROM jobs_envio_prepara(:'env_m') \gset
SELECT jobs_envio_resultado(:'env_m','ACEITO','pm') AS t2_maria;
\c r2 saas_app
SET search_path = saas;
SELECT paciente_pede_codigo(:'tok_m') AS pediu_m;
\c r2 saas_jobs
SET search_path = saas;
SELECT envio_id AS ec_m FROM jobs_envios_pendentes(100) WHERE finalidade='CODIGO_PACIENTE' LIMIT 1 \gset
SELECT segredo AS cod_m FROM jobs_envio_prepara(:'ec_m') \gset
-- link + codigo + sessao: Joao (mesmo telefone)
SELECT jobs_envio_link_paciente(:'enc_joao') AS env_j \gset
SELECT contato AS contato_j, segredo AS tok_j FROM jobs_envio_prepara(:'env_j') \gset
SELECT jobs_envio_resultado(:'env_j','ACEITO','pj') AS t2_joao;
\c r2 saas_app
SET search_path = saas;
SELECT paciente_confirma_codigo(:'tok_m', :'cod_m') AS sess_m \gset
SELECT paciente_pede_codigo(:'tok_j') AS pediu_j;
\c r2 saas_jobs
SET search_path = saas;
SELECT envio_id AS ec_j FROM jobs_envios_pendentes(100) WHERE finalidade='CODIGO_PACIENTE' LIMIT 1 \gset
SELECT segredo AS cod_j FROM jobs_envio_prepara(:'ec_j') \gset
\c r2 saas_app
SET search_path = saas;
SELECT paciente_confirma_codigo(:'tok_j', :'cod_j') AS sess_j \gset
SELECT (:'contato_m' = :'contato_j') AS mesmo_telefone_recebe_os_dois_links;
\echo '  Joao escolhe a clinica B (T3) e anexa um exame; recepcao B confirma horario (T4)'
SELECT set_config('app.sessao', :'sess_j', false) IS NOT NULL;
SELECT paciente_solicita(:'enc_joao', :'cB', NULL, 'Autorizo compartilhar', 'v1')::text = '' AS t3_joao_sem_erro;
INSERT INTO anexo_encaminhamento(encaminhamento_id, tipo_mime, tamanho_bytes, sha256, nome_original_cifrado, enviado_por_tipo, enviado_por_id)
SELECT :'enc_joao', 'application/pdf', 1000, '\xaa', '\xbb', 'PACIENTE', paciente_id FROM encaminhamento WHERE id = :'enc_joao';
RESET app.sessao;
BEGIN;
SELECT set_config('app.sessao', repeat('bb',32), true) IS NOT NULL, set_config('app.clinica_id', :'cB', true) IS NOT NULL, set_config('app.papel','RECEPCAO',true);
SELECT destino_confirma_horario(:'enc_joao', :'pcB', date_trunc('hour', now()) + interval '3 days', date_trunc('hour', now()) + interval '3 days 30 minutes', 'chave-joao-1') AS ag_joao \gset
COMMIT;
\echo 'R2N4 sessao da MARIA (mesmo aparelho) contra cada caminho ate o caso do JOAO (esperado: 0 em todos)'
SELECT set_config('app.sessao', :'sess_m', false) IS NOT NULL;
SELECT
  (SELECT count(*) FROM encaminhamento WHERE id = :'enc_joao')                              AS r2n4a_encaminhamento,
  (SELECT count(*) FROM paciente p JOIN encaminhamento e ON e.paciente_id = p.id WHERE e.id = :'enc_joao') AS r2n4b_paciente_via_caso,
  (SELECT count(*) FROM paciente)                                                           AS r2n4c_pacientes_visiveis_total,
  (SELECT count(*) FROM historico_status_encaminhamento WHERE encaminhamento_id = :'enc_joao') AS r2n4d_historico,
  (SELECT count(*) FROM anexo_encaminhamento WHERE encaminhamento_id = :'enc_joao')         AS r2n4e_anexo,
  (SELECT count(*) FROM agendamento WHERE encaminhamento_id = :'enc_joao')                  AS r2n4f_agendamento,
  (SELECT count(*) FROM consentimento WHERE encaminhamento_id = :'enc_joao')                AS r2n4g_consentimento,
  (SELECT count(*) FROM contrarreferencia WHERE encaminhamento_id = :'enc_joao')            AS r2n4h_contrarreferencia;
\echo 'R2N4i sessao da Maria cancela o caso do Joao por UPDATE direto (esperado: 0 linhas)'
UPDATE encaminhamento SET status = 'CANCELADO' WHERE id = :'enc_joao';
\echo '    linhas afetadas:' :ROW_COUNT
\echo 'R2N4j sessao da Maria revoga o consentimento do Joao (esperado: 0 linhas)'
UPDATE consentimento SET revogado_em = now() WHERE encaminhamento_id = :'enc_joao';
\echo '    linhas afetadas:' :ROW_COUNT
\echo 'R2N4k sessao da Maria grava consentimento no caso do Joao (esperado: erro)'
INSERT INTO consentimento(paciente_id, finalidade, encaminhamento_id, clinica_id, texto_aceito, versao_texto, canal)
VALUES (:'pid_joao', 'COMPARTILHAR_CASO', :'enc_joao', :'cB', 'x', 'v1', 'SITE');
\echo 'R2N4l sessao da Maria grava auditoria em nome do Joao (esperado: erro)'
INSERT INTO evento_auditoria(ator_papel, ator_id, acao, recurso_tipo, recurso_id, canal)
VALUES ('PACIENTE', :'pid_joao', 'LER', 'encaminhamento', :'enc_joao', 'WEB');
\echo 'R2N4m controle: a sessao da Maria ve o proprio caso'
SELECT count(*) AS r2n4m_controle_proprio_caso FROM encaminhamento WHERE id = :'enc_maria';
RESET app.sessao;

\echo ''
\echo '================ R2N5. Duplicata como canal: vinculo de encaminhamento depois da revogacao ================'
\echo '  Joao revoga o COMPARTILHAR_CASO da clinica B (paciente_clinica nascido do encaminhamento continua)'
SELECT set_config('app.sessao', :'sess_j', false) IS NOT NULL;
UPDATE consentimento SET revogado_em = now() WHERE encaminhamento_id = :'enc_joao' AND revogado_em IS NULL;
\echo '    revogacoes:' :ROW_COUNT
RESET app.sessao;
BEGIN;
SELECT set_config('app.sessao', repeat('bb',32), true) IS NOT NULL, set_config('app.clinica_id', :'cB', true) IS NOT NULL, set_config('app.papel','RECEPCAO',true);
\echo 'R2N5a recepcao B le o cadastro do Joao depois da revogacao (esperado: 0, I-03)'
SELECT count(*) AS r2n5a_paciente_lido FROM paciente p JOIN agendamento a ON a.paciente_id = p.id WHERE a.id = :'ag_joao';
SELECT paciente_id AS pac_joao FROM agendamento WHERE id = :'ag_joao' \gset
\echo 'R2N5b recepcao B "cadastra" Joao com nome, data e telefone: recebe o id do registro revogado? (esperado: registro novo)'
SELECT paciente_cadastra_na_clinica('Joao Costa','+5581900006666',DATE '2014-04-04',NULL,NULL) AS pac_b \gset
SELECT CASE WHEN :'pac_b' = :'pac_joao' THEN 'PASSOU: oraculo e reuso do vinculo revogado' ELSE 'NEGADO' END AS r2n5b;
\echo 'R2N5c com o id devolvido, recepcao B marca consulta fora do encaminhamento (esperado: negado)'
INSERT INTO agendamento(clinica_id, profissional_clinica_id, paciente_id, inicio, fim, origem, chave_idempotencia)
VALUES (:'cB', :'pcB', :'pac_b', date_trunc('hour', now()) + interval '5 days', date_trunc('hour', now()) + interval '5 days 30 minutes', 'RECEPCAO', 'chave-joao-2');
\echo '    linhas inseridas:' :ROW_COUNT
\echo 'R2N5d recepcao B registra consentimento de WhatsApp em nome dele (esperado: negado)'
INSERT INTO consentimento(paciente_id, finalidade, clinica_id, texto_aceito, versao_texto, canal)
VALUES (:'pac_b', 'COMUNICACAO_WHATSAPP', :'cB', 'aceito no balcao', 'v1', 'RECEPCAO');
\echo '    linhas inseridas:' :ROW_COUNT
\echo 'R2N5e e continua sem conseguir ler o cadastro que acabou de "criar" (incoerencia)'
SELECT count(*) AS r2n5e_paciente_lido FROM paciente WHERE id = :'pac_b';
COMMIT;

\echo ''
\echo '================ R2N6. Paciente nascido de encaminhamento: quem corrige telefone ou nome errado ================'
\c r2 saas_app
SET search_path = saas;
BEGIN;
SELECT set_config('app.sessao', repeat('bb',32), true) IS NOT NULL, set_config('app.clinica_id', :'cB', true) IS NOT NULL, set_config('app.papel','RECEPCAO',true);
\echo 'R2N6a recepcao B troca telefone do Joao (nasceu de encaminhamento; esperado: negado, O2 pendente da Fase 3)'
SELECT paciente_troca_telefone_presencial(:'pac_joao', '+5581900009999');
ROLLBACK;

\echo ''
\echo '================ R2N7. I-20: o papel web religa o rastreio de comando ================'
\c r2 saas_app
SET search_path = saas;
\echo 'R2N7a SET track_activities = on (esperado: negado)'
SET track_activities = on;
\echo 'R2N7b SET log_statement = all (esperado: negado)'
SET log_statement = 'all';
\echo 'R2N7c SET log_min_duration_statement = 0 (esperado: negado)'
SET log_min_duration_statement = 0;
\echo 'R2N7d SET log_parameter_max_length = -1 (esperado: negado)'
SET log_parameter_max_length = -1;
\echo 'R2N7e ALTER ROLE saas_app SET track_activities = on (esperado: negado)'
ALTER ROLE saas_app SET track_activities = on;
\echo 'R2N7f valores efetivos na conexao do papel web'
SELECT current_setting('track_activities') AS track_activities, current_setting('log_parameter_max_length') AS lpml,
       current_setting('log_parameter_max_length_on_error') AS lpml_err;
\echo '  R2N7g (opcao de arranque PGOPTIONS) no fim do log, executada pelo runner'

\echo ''
\echo '================ R2N9. R-07: alerta de DDL cobre politica e gatilho? ================'
\echo '  Cada passo como saas_owner, com marca no log do servidor; o runner anexa o log entre as marcas.'
\c r2 pgtest
SET search_path = saas, public;
DO $$ BEGIN RAISE LOG 'MARCA_R2N9a inicio: CREATE POLICY aberta'; END $$;
SET ROLE saas_owner;
CREATE POLICY r2n9_aberta ON saas.encaminhamento FOR SELECT USING (true);
RESET ROLE;
DO $$ BEGIN RAISE LOG 'MARCA_R2N9a fim'; END $$;
\c r2 saas_app
SET search_path = saas;
\echo 'R2N9a efeito: papel web SEM sessao le encaminhamentos depois da politica aberta do dono'
SELECT count(*) AS r2n9a_encaminhamentos_sem_sessao FROM encaminhamento;
\c r2 pgtest
SET search_path = saas, public;
DO $$ BEGIN RAISE LOG 'MARCA_R2N9b inicio: ALTER POLICY encaminhamento_paciente USING (true)'; END $$;
SET ROLE saas_owner;
BEGIN; ALTER POLICY encaminhamento_paciente ON saas.encaminhamento USING (true); ROLLBACK;
RESET ROLE;
DO $$ BEGIN RAISE LOG 'MARCA_R2N9b fim'; END $$;
DO $$ BEGIN RAISE LOG 'MARCA_R2N9c inicio: DROP POLICY'; END $$;
SET ROLE saas_owner;
DROP POLICY r2n9_aberta ON saas.encaminhamento;
RESET ROLE;
DO $$ BEGIN RAISE LOG 'MARCA_R2N9c fim'; END $$;
DO $$ BEGIN RAISE LOG 'MARCA_R2N9d inicio: DROP TRIGGER historico_so_inclusao'; END $$;
SET ROLE saas_owner;
BEGIN; DROP TRIGGER historico_so_inclusao ON saas.historico_status_encaminhamento; ROLLBACK;
RESET ROLE;
DO $$ BEGIN RAISE LOG 'MARCA_R2N9d fim'; END $$;
DO $$ BEGIN RAISE LOG 'MARCA_R2N9e inicio: CREATE TRIGGER que zera motivo'; END $$;
SET ROLE saas_owner;
BEGIN;
CREATE FUNCTION saas.r2n9_f() RETURNS trigger LANGUAGE plpgsql AS $f$ BEGIN RETURN NEW; END $f$;
CREATE TRIGGER r2n9_t BEFORE UPDATE ON saas.encaminhamento FOR EACH ROW EXECUTE FUNCTION saas.r2n9_f();
ROLLBACK;
RESET ROLE;
DO $$ BEGIN RAISE LOG 'MARCA_R2N9e fim'; END $$;
DO $$ BEGIN RAISE LOG 'MARCA_R2N9f inicio: controle ALTER TABLE DISABLE TRIGGER'; END $$;
SET ROLE saas_owner;
BEGIN; ALTER TABLE saas.historico_status_encaminhamento DISABLE TRIGGER historico_so_inclusao; ROLLBACK;
RESET ROLE;
DO $$ BEGIN RAISE LOG 'MARCA_R2N9f fim'; END $$;
\echo 'R2N9g o que pg_event_trigger_ddl_commands informa como schema de politica e gatilho (causa)'
CREATE TABLE public.r2n9_cap(tag text, tipo text, esquema text, ident text);
CREATE FUNCTION public.r2n9_cap_f() RETURNS event_trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog AS $f$
DECLARE r record; BEGIN
  FOR r IN SELECT * FROM pg_event_trigger_ddl_commands() LOOP
    INSERT INTO public.r2n9_cap VALUES (r.command_tag, r.object_type, coalesce(r.schema_name,'(nulo)'), r.object_identity);
  END LOOP; END $f$;
CREATE EVENT TRIGGER r2n9_cap_t ON ddl_command_end EXECUTE FUNCTION public.r2n9_cap_f();
BEGIN;
SET ROLE saas_owner;
CREATE POLICY r2n9_x ON saas.paciente FOR SELECT USING (true);
CREATE TRIGGER r2n9_y BEFORE UPDATE ON saas.paciente FOR EACH ROW EXECUTE FUNCTION saas.bloqueia_alteracao();
ALTER TABLE saas.paciente DISABLE TRIGGER r2n9_y;
RESET ROLE;
SELECT tag, tipo, esquema, ident FROM public.r2n9_cap ORDER BY tag;
ROLLBACK;
DROP EVENT TRIGGER r2n9_cap_t; DROP FUNCTION public.r2n9_cap_f(); DROP TABLE IF EXISTS public.r2n9_cap;
\echo ''
\echo '================ FIM DO SQL (anexos do runner abaixo) ================'
