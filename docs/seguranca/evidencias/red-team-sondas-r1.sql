-- red-team-sondas-r1.sql : as sondas RT1 a RT10 de red-team-sondas.sql reexecutadas contra o
-- modelo-v2.sql da rodada de revisao 1. Mesmos ataques, mesmos dados de partida, adaptados
-- so no que o modelo mudou (identidade por sessao; papel saas_jobs; GUCs antigas ignoradas).
-- Cada ataque roda duas vezes quando faz sentido: (a) como na rodada 0, so com GUC forjada,
-- e (b) com uma sessao VALIDA do atacante, para provar que a negacao nao depende de falta de
-- contexto. Resultado esperado de toda sonda: NEGADO (erro ou 0 linhas).
-- Execucao: superusuario do cluster descartavel; cada sonda usa SET LOCAL ROLE e e desfeita.
\set ON_ERROR_STOP off
SET search_path = saas, public;
-- semente minima (superusuario), igual a da rodada 0 mais sessoes
INSERT INTO clinica(id,nome) VALUES ('aaaaaaaa-0000-0000-0000-000000000001','A'),('bbbbbbbb-0000-0000-0000-000000000001','B');
INSERT INTO flag_clinica(clinica_id,chave,ligada) VALUES ('aaaaaaaa-0000-0000-0000-000000000001','REDE_ENCAMINHAMENTO',true),('bbbbbbbb-0000-0000-0000-000000000001','REDE_ENCAMINHAMENTO',false);
INSERT INTO usuario(id,sub_oidc,nome,email) VALUES ('aaaaaaaa-0000-0000-0001-000000000002','recA','RecA','r@a'),('aaaaaaaa-0000-0000-0001-000000000003','medA','MedA','m@a');
INSERT INTO usuario_clinica(usuario_id,clinica_id,papel) VALUES ('aaaaaaaa-0000-0000-0001-000000000002','aaaaaaaa-0000-0000-0000-000000000001','RECEPCAO'),('aaaaaaaa-0000-0000-0001-000000000003','aaaaaaaa-0000-0000-0000-000000000001','MEDICO');
INSERT INTO profissional(id,crm,crm_uf,nome,telefone,usuario_id,canal_verificado_em) VALUES ('aaaaaaaa-0000-0000-0002-000000000001','111','PE','MedA','8100','aaaaaaaa-0000-0000-0001-000000000003',now()),('eeeeeeee-0000-0000-0002-000000000001','999','PE','Encaminhador','8199',NULL,now()),('bbbbbbbb-0000-0000-0002-000000000001','222','PE','MedB','8122',NULL,NULL),('eeeeeeee-0000-0000-0002-000000000002','998','PE','Atacante','8198',NULL,now());
INSERT INTO profissional_clinica(id,profissional_id,clinica_id) VALUES ('bbbbbbbb-0000-0000-0004-000000000001','bbbbbbbb-0000-0000-0002-000000000001','bbbbbbbb-0000-0000-0000-000000000001'),('aaaaaaaa-0000-0000-0004-000000000001','aaaaaaaa-0000-0000-0002-000000000001','aaaaaaaa-0000-0000-0000-000000000001');
INSERT INTO especialidade(id,nome) VALUES ('dddddddd-0000-0000-0000-000000000001','Ortopedia');
INSERT INTO clinica_especialidade VALUES ('aaaaaaaa-0000-0000-0000-000000000001','dddddddd-0000-0000-0000-000000000001'),('bbbbbbbb-0000-0000-0000-000000000001','dddddddd-0000-0000-0000-000000000001');
INSERT INTO paciente(id,nome,telefone,cadastrado_por_clinica_id) VALUES ('bbbbbbbb-0000-0000-0003-000000000001','Paciente de B','+5581900000001','bbbbbbbb-0000-0000-0000-000000000001'),('cccccccc-0000-0000-0003-000000000001','Paciente C (atacante)','+5581900000009',NULL);
INSERT INTO paciente_clinica(paciente_id,clinica_id) VALUES ('bbbbbbbb-0000-0000-0003-000000000001','bbbbbbbb-0000-0000-0000-000000000001');
INSERT INTO encaminhamento(id,profissional_origem_id,paciente_id,especialidade_destino_id,clinica_destino_id,motivo_cifrado,urgencia,expira_em)
 VALUES ('eeeeeeee-0000-0000-0005-000000000001','eeeeeeee-0000-0000-0002-000000000001','bbbbbbbb-0000-0000-0003-000000000001','dddddddd-0000-0000-0000-000000000001','aaaaaaaa-0000-0000-0000-000000000001','\x01','ROTINA',now()+interval '30 days'),
        ('eeeeeeee-0000-0000-0005-000000000009','eeeeeeee-0000-0000-0002-000000000002','cccccccc-0000-0000-0003-000000000001','dddddddd-0000-0000-0000-000000000001',NULL,'\x09','ROTINA',now()+interval '30 days');
-- E1 em ATENDIDO com consulta realizada por MedA (rodada 0 semeava ATENDIDO direto; aqui sem gatilho, so na semente)
SET session_replication_role = replica;
UPDATE encaminhamento SET status='ATENDIDO' WHERE id='eeeeeeee-0000-0000-0005-000000000001';
SET session_replication_role = origin;
INSERT INTO consentimento(paciente_id,finalidade,encaminhamento_id,clinica_id,texto_aceito,versao_texto,canal) VALUES ('bbbbbbbb-0000-0000-0003-000000000001','COMPARTILHAR_CASO','eeeeeeee-0000-0000-0005-000000000001','aaaaaaaa-0000-0000-0000-000000000001','t','1','WHATSAPP');
INSERT INTO link_paciente(id,encaminhamento_id,paciente_id,token_hash,expira_em,codigo_hash,codigo_expira_em,tentativas_codigo) VALUES ('eeeeeeee-0000-0000-0007-000000000001','eeeeeeee-0000-0000-0005-000000000001','bbbbbbbb-0000-0000-0003-000000000001',sha256('\x0101'::bytea),now()+interval '1 day',sha256(convert_to('eeeeeeee-0000-0000-0007-000000000001:111111','UTF8')),now()+interval '10 minutes',9);
INSERT INTO link_paciente(id,encaminhamento_id,paciente_id,token_hash,expira_em) VALUES ('eeeeeeee-0000-0000-0007-000000000009','eeeeeeee-0000-0000-0005-000000000009','cccccccc-0000-0000-0003-000000000001',sha256('\x0909'::bytea),now()+interval '1 day');
INSERT INTO anexo_encaminhamento(id,encaminhamento_id,chave_storage,tipo_mime,tamanho_bytes,sha256,enviado_por_tipo,enviado_por_id) VALUES ('eeeeeeee-0000-0000-0008-000000000001','eeeeeeee-0000-0000-0005-000000000001','obj-1','application/pdf',10,'\x00','PROFISSIONAL','eeeeeeee-0000-0000-0002-000000000001');
-- sessoes validas dos ATACANTES (token = md5('rt-'||chave))
INSERT INTO sessao(token_hash,tipo,usuario_id,expira_em) VALUES
 (sha256(decode(md5('rt-recA'),'hex')),'EQUIPE','aaaaaaaa-0000-0000-0001-000000000002',now()+interval '1 hour'),
 (sha256(decode(md5('rt-medA'),'hex')),'EQUIPE','aaaaaaaa-0000-0000-0001-000000000003',now()+interval '1 hour');
INSERT INTO sessao(token_hash,tipo,profissional_id,expira_em) VALUES
 (sha256(decode(md5('rt-encAtacante'),'hex')),'ENCAMINHADOR','eeeeeeee-0000-0000-0002-000000000002',now()+interval '1 hour');
INSERT INTO sessao(token_hash,tipo,paciente_id,link_paciente_id,expira_em) VALUES
 (sha256(decode(md5('rt-pacC'),'hex')),'PACIENTE','cccccccc-0000-0000-0003-000000000001','eeeeeeee-0000-0000-0007-000000000009',now()+interval '20 minutes');

-- harness: aplica papel e GUCs, roda o ataque, mede, desfaz e registra
CREATE SCHEMA rt_aux;
CREATE TABLE rt_aux.res(n serial, id text, descricao text, papel text, resultado text, negado boolean);
GRANT USAGE ON SCHEMA rt_aux TO saas_app, saas_jobs;
GRANT INSERT, SELECT ON rt_aux.res TO saas_app, saas_jobs;
GRANT USAGE ON SEQUENCE rt_aux.res_n_seq TO saas_app, saas_jobs;
CREATE FUNCTION rt_aux.sonda(p_id text, p_desc text, p_gucs text[], p_ataque text[], p_verif text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE r text; n bigint; s text; i int;
BEGIN
  BEGIN
    FOR i IN 1 .. coalesce(array_length(p_gucs,1),0) / 2 LOOP
      PERFORM set_config(p_gucs[2*i-1], p_gucs[2*i], true);
    END LOOP;
    FOREACH s IN ARRAY p_ataque LOOP EXECUTE s; GET DIAGNOSTICS n = ROW_COUNT; r := n::text; END LOOP;
    IF p_verif IS NOT NULL THEN EXECUTE p_verif INTO r; END IF;
    RAISE EXCEPTION 'desfazer' USING ERRCODE = 'RB001';
  EXCEPTION
    WHEN SQLSTATE 'RB001' THEN NULL;
    WHEN OTHERS THEN r := 'ERRO[' || SQLSTATE || ']: ' || left(SQLERRM, 100);
  END;
  INSERT INTO rt_aux.res(id, descricao, papel, resultado, negado)
  VALUES (p_id, p_desc, current_user, coalesce(r,'NULL'), r LIKE 'ERRO%' OR r = '0');
END $$;
GRANT EXECUTE ON FUNCTION rt_aux.sonda(text,text,text[],text[],text) TO saas_app, saas_jobs;

\echo '======== SONDAS (saas_app e saas_jobs via SET LOCAL ROLE) ========'

-- RT1: recepcao A vincula paciente de B por UUID e troca o TELEFONE global dele
BEGIN; SET LOCAL ROLE saas_app;
SELECT rt_aux.sonda('RT1a','recepcao A (sessao valida) vincula paciente de B por UUID',
  ARRAY['app.clinica_id','aaaaaaaa-0000-0000-0000-000000000001','app.papel','RECEPCAO','app.sessao',md5('rt-recA')],
  ARRAY['INSERT INTO saas.paciente_clinica(paciente_id,clinica_id) VALUES (''bbbbbbbb-0000-0000-0003-000000000001'',''aaaaaaaa-0000-0000-0000-000000000001'')']);
SELECT rt_aux.sonda('RT1b','recepcao A (sessao valida) troca telefone de paciente de B por UPDATE',
  ARRAY['app.clinica_id','aaaaaaaa-0000-0000-0000-000000000001','app.papel','RECEPCAO','app.sessao',md5('rt-recA')],
  ARRAY['UPDATE saas.paciente SET telefone=''+5581999999999'' WHERE id=''bbbbbbbb-0000-0000-0003-000000000001''']);
SELECT rt_aux.sonda('RT1c','recepcao A (sessao valida) troca telefone de paciente de B pela funcao presencial',
  ARRAY['app.clinica_id','aaaaaaaa-0000-0000-0000-000000000001','app.papel','RECEPCAO','app.sessao',md5('rt-recA')],
  ARRAY['SELECT saas.paciente_troca_telefone_presencial(''bbbbbbbb-0000-0000-0003-000000000001'',''+5581999999999'')']);
-- Nota: nesta semente E1 leva o paciente de B para a clinica A COM consentimento, entao A ler
-- esse paciente pelo encaminhamento e legitimo. A sonda mede o vinculo forjado, nao a leitura.
SELECT rt_aux.sonda('RT1d','recepcao A (sessao valida): vinculo forjado com paciente de B nao existe apos a tentativa',
  ARRAY['app.clinica_id','aaaaaaaa-0000-0000-0000-000000000001','app.papel','RECEPCAO','app.sessao',md5('rt-recA')],
  ARRAY['SELECT 1'], 'SELECT count(*) FROM saas.paciente_clinica WHERE paciente_id=''bbbbbbbb-0000-0000-0003-000000000001''');
COMMIT;

-- RT2: PUBLICO_LINK zera tentativas, troca codigo_hash e estende expiracao do proprio link
BEGIN; SET LOCAL ROLE saas_app;
SELECT rt_aux.sonda('RT2a','PUBLICO_LINK (GUC, como na rodada 0) UPDATE no proprio link',
  ARRAY['app.papel','PUBLICO_LINK','app.link_token_hash','0101'],
  ARRAY['UPDATE saas.link_paciente SET tentativas_codigo=0, codigo_hash=''\xbeef'', expira_em=now()+interval ''365 days'', codigo_expira_em=now()+interval ''365 days''']);
SELECT rt_aux.sonda('RT2b','com o token do link: 1 erro (soma 10) e o codigo certo deixa de abrir sessao',
  ARRAY[]::text[],
  ARRAY['SELECT saas.paciente_confirma_codigo(''0101'',''000000'')'],
  'SELECT count(*) FROM (SELECT saas.paciente_confirma_codigo(''0101'',''111111'') t) x WHERE t IS NOT NULL');
COMMIT;

-- RT3: qualquer conexao declara SISTEMA e troca chave_storage de anexo PENDENTE
BEGIN; SET LOCAL ROLE saas_app;
SELECT rt_aux.sonda('RT3a','saas_app declara SISTEMA e reescreve anexo',
  ARRAY['app.papel','SISTEMA'],
  ARRAY['UPDATE saas.anexo_encaminhamento SET chave_storage=''objeto-de-outro-encaminhamento'', tipo_mime=''image/png'', status_varredura=''LIMPO''']);
SELECT rt_aux.sonda('RT3b','saas_app chama a funcao de varredura do worker',
  ARRAY['app.papel','SISTEMA'], ARRAY['SELECT saas.jobs_anexo_varredura(''eeeeeeee-0000-0000-0008-000000000001'',''LIMPO'')']);
COMMIT;
BEGIN; SET LOCAL ROLE saas_jobs;
SELECT rt_aux.sonda('RT3c','papel do worker (saas_jobs) reescreve anexo direto',
  ARRAY[]::text[], ARRAY['UPDATE saas.anexo_encaminhamento SET chave_storage=''objeto-de-outro-encaminhamento''']);
SELECT rt_aux.sonda('RT3d','papel do worker: LIMPO e depois volta/troca para INFECTADO',
  ARRAY[]::text[], ARRAY['SELECT saas.jobs_anexo_varredura(''eeeeeeee-0000-0000-0008-000000000001'',''LIMPO'')','SELECT saas.jobs_anexo_varredura(''eeeeeeee-0000-0000-0008-000000000001'',''INFECTADO'')']);
COMMIT;

-- RT4: PACIENTE com paciente_id alheio le paciente, encaminhamento e anexo
BEGIN; SET LOCAL ROLE saas_app;
SELECT rt_aux.sonda('RT4a','PACIENTE so por GUC com paciente_id de B',
  ARRAY['app.papel','PACIENTE','app.paciente_id','bbbbbbbb-0000-0000-0003-000000000001'],
  ARRAY['SELECT 1'], 'SELECT (SELECT count(*) FROM saas.paciente) + (SELECT count(*) FROM saas.encaminhamento) + (SELECT count(*) FROM saas.anexo_encaminhamento)');
SELECT rt_aux.sonda('RT4b','PACIENTE C com sessao valida e GUC paciente_id de B: dados de B',
  ARRAY['app.papel','PACIENTE','app.paciente_id','bbbbbbbb-0000-0000-0003-000000000001','app.sessao',md5('rt-pacC')],
  ARRAY['SELECT 1'], 'SELECT (SELECT count(*) FROM saas.paciente WHERE id=''bbbbbbbb-0000-0000-0003-000000000001'') + (SELECT count(*) FROM saas.encaminhamento WHERE paciente_id=''bbbbbbbb-0000-0000-0003-000000000001'') + (SELECT count(*) FROM saas.anexo_encaminhamento)');
COMMIT;

-- RT5: ENCAMINHADOR com profissional_id de outro medico (CRM publico) le os encaminhamentos dele
BEGIN; SET LOCAL ROLE saas_app;
SELECT rt_aux.sonda('RT5a','ENCAMINHADOR so por GUC com profissional_id do encaminhador real',
  ARRAY['app.papel','ENCAMINHADOR','app.profissional_id','eeeeeeee-0000-0000-0002-000000000001'],
  ARRAY['SELECT 1'], 'SELECT (SELECT count(*) FROM saas.encaminhamento) + (SELECT count(*) FROM saas.anexo_encaminhamento)');
SELECT rt_aux.sonda('RT5b','atacante com sessao valida de encaminhador e GUC do real',
  ARRAY['app.papel','ENCAMINHADOR','app.profissional_id','eeeeeeee-0000-0000-0002-000000000001','app.sessao',md5('rt-encAtacante')],
  ARRAY['SELECT 1'], 'SELECT (SELECT count(*) FROM saas.encaminhamento WHERE profissional_origem_id=''eeeeeeee-0000-0000-0002-000000000001'') + (SELECT count(*) FROM saas.anexo_encaminhamento)');
SELECT rt_aux.sonda('RT5c','atacante digita o CRM publico do real e tenta abrir sessao',
  ARRAY[]::text[], ARRAY['SELECT set_config(''app.sessao'', coalesce(saas.encaminhador_confirma_codigo(saas.encaminhador_pede_codigo(''999'',''PE''),''000000''),''''), true)'],
  'SELECT count(*) FROM saas.encaminhamento');
SELECT rt_aux.sonda('RT5d','atacante recadastra o CRM do real pelo formulario',
  ARRAY[]::text[], ARRAY['SELECT set_config(''app.sessao'', coalesce(saas.encaminhador_confirma_codigo(saas.encaminhador_cadastra(''999'',''PE'',''Falso'',''81911112222'',''f@x''),''000000''),''''), true)'],
  'SELECT count(*) FROM saas.encaminhamento');
COMMIT;

-- RT6: auditoria forjada: ENCAMINHADOR grava evento com ator_id e papel de terceiro
BEGIN; SET LOCAL ROLE saas_app;
SELECT rt_aux.sonda('RT6a','ENCAMINHADOR so por GUC grava evento como ADMIN',
  ARRAY['app.papel','ENCAMINHADOR','app.profissional_id','eeeeeeee-0000-0000-0002-000000000001'],
  ARRAY['INSERT INTO saas.evento_auditoria(ator_papel,ator_id,acao,recurso_tipo) VALUES (''ADMIN'',''aaaaaaaa-0000-0000-0001-000000000002'',''LER_ENCAMINHAMENTO'',''encaminhamento'')']);
SELECT rt_aux.sonda('RT6b','ENCAMINHADOR com sessao valida grava evento como ADMIN',
  ARRAY['app.sessao',md5('rt-encAtacante')],
  ARRAY['INSERT INTO saas.evento_auditoria(ator_papel,ator_id,acao,recurso_tipo) VALUES (''ADMIN'',''aaaaaaaa-0000-0000-0001-000000000002'',''LER_ENCAMINHAMENTO'',''encaminhamento'')']);
COMMIT;

-- RT7: PACIENTE marca agendamento na clinica B, profissional qualquer, sem encaminhamento nem vaga
BEGIN; SET LOCAL ROLE saas_app;
SELECT rt_aux.sonda('RT7a','PACIENTE so por GUC insere agendamento',
  ARRAY['app.papel','PACIENTE','app.paciente_id','bbbbbbbb-0000-0000-0003-000000000001'],
  ARRAY['INSERT INTO saas.agendamento(clinica_id,profissional_clinica_id,paciente_id,inicio,fim,origem,chave_idempotencia) VALUES (''bbbbbbbb-0000-0000-0000-000000000001'',''bbbbbbbb-0000-0000-0004-000000000001'',''bbbbbbbb-0000-0000-0003-000000000001'',now()+interval ''1 day'',now()+interval ''1 day 30 min'',''SITE'',''k1'')']);
SELECT rt_aux.sonda('RT7b','PACIENTE C com sessao valida insere agendamento para si',
  ARRAY['app.sessao',md5('rt-pacC')],
  ARRAY['INSERT INTO saas.agendamento(clinica_id,profissional_clinica_id,paciente_id,inicio,fim,origem,chave_idempotencia) VALUES (''bbbbbbbb-0000-0000-0000-000000000001'',''bbbbbbbb-0000-0000-0004-000000000001'',''cccccccc-0000-0000-0003-000000000001'',now()+interval ''1 day'',now()+interval ''1 day 30 min'',''SITE'',''k1'')']);
COMMIT;

-- RT8: MEDICO de A assina contrarreferencia como outro profissional
BEGIN; SET LOCAL ROLE saas_app;
SELECT rt_aux.sonda('RT8a','MEDICO A (sessao valida) com GUC profissional_id de MedB assina como MedB',
  ARRAY['app.clinica_id','aaaaaaaa-0000-0000-0000-000000000001','app.papel','MEDICO','app.profissional_id','bbbbbbbb-0000-0000-0002-000000000001','app.sessao',md5('rt-medA')],
  ARRAY['INSERT INTO saas.contrarreferencia(encaminhamento_id,clinica_id,autor_profissional_id,conduta_cifrada) VALUES (''eeeeeeee-0000-0000-0005-000000000001'',''aaaaaaaa-0000-0000-0000-000000000001'',''bbbbbbbb-0000-0000-0002-000000000001'',''\x02'')']);
SELECT rt_aux.sonda('RT8b','MEDICO so por GUC (rodada 0) assina como MedB',
  ARRAY['app.clinica_id','aaaaaaaa-0000-0000-0000-000000000001','app.usuario','aaaaaaaa-0000-0000-0001-000000000003','app.papel','MEDICO','app.profissional_id','bbbbbbbb-0000-0000-0002-000000000001'],
  ARRAY['INSERT INTO saas.contrarreferencia(encaminhamento_id,clinica_id,autor_profissional_id,conduta_cifrada) VALUES (''eeeeeeee-0000-0000-0005-000000000001'',''aaaaaaaa-0000-0000-0000-000000000001'',''bbbbbbbb-0000-0000-0002-000000000001'',''\x02'')']);
COMMIT;

-- RT9: oraculo por erro: ENCAMINHADOR cadastra CRM existente
BEGIN; SET LOCAL ROLE saas_app;
SELECT rt_aux.sonda('RT9a','ENCAMINHADOR (sessao valida) INSERT de CRM existente (esperado: erro de privilegio, nao de unicidade)',
  ARRAY['app.sessao',md5('rt-encAtacante')],
  ARRAY['INSERT INTO saas.profissional(crm,crm_uf,nome) VALUES (''222'',''PE'',''x'')']);
SELECT rt_aux.sonda('RT9b','formulario com CRM existente x inexistente devolve o mesmo formato (64 hex), sem erro',
  ARRAY[]::text[], ARRAY['SELECT 1'],
  'SELECT CASE WHEN length(saas.encaminhador_cadastra(''222'',''PE'',''x'',''81900000000'',''x@x'')) = length(saas.encaminhador_cadastra(''7777'',''PE'',''y'',''81900000001'',''y@x'')) THEN 0 ELSE 1 END');
COMMIT;

-- RT10: PACIENTE altera o proprio telefone
BEGIN; SET LOCAL ROLE saas_app;
SELECT rt_aux.sonda('RT10a','PACIENTE so por GUC altera telefone',
  ARRAY['app.papel','PACIENTE','app.paciente_id','bbbbbbbb-0000-0000-0003-000000000001'],
  ARRAY['UPDATE saas.paciente SET telefone=''+5581988888888''']);
SELECT rt_aux.sonda('RT10b','PACIENTE C com sessao valida altera o proprio telefone',
  ARRAY['app.sessao',md5('rt-pacC')],
  ARRAY['UPDATE saas.paciente SET telefone=''+5581988888888'' WHERE id=''cccccccc-0000-0000-0003-000000000001''']);
COMMIT;

-- Controles positivos (o harness nao e vacuo): o acesso legitimo continua funcionando
BEGIN; SET LOCAL ROLE saas_app;
SELECT rt_aux.sonda('CTRL1','controle: recepcao A (sessao valida) ve E1, destino com consentimento',
  ARRAY['app.clinica_id','aaaaaaaa-0000-0000-0000-000000000001','app.papel','RECEPCAO','app.sessao',md5('rt-recA')],
  ARRAY['SELECT 1'], 'SELECT count(*) FROM saas.encaminhamento');
SELECT rt_aux.sonda('CTRL2','controle: paciente C (sessao valida) ve o proprio encaminhamento',
  ARRAY['app.sessao',md5('rt-pacC')], ARRAY['SELECT 1'], 'SELECT count(*) FROM saas.encaminhamento');
COMMIT;

\echo '======== RESULTADO ========'
\pset format wrapped
\pset columns 200
SELECT n, id, descricao, papel, CASE WHEN negado THEN 'NEGADO' ELSE 'ABERTA' END AS veredito, resultado FROM rt_aux.res ORDER BY n;
SELECT count(*) FILTER (WHERE id NOT LIKE 'CTRL%') AS sondas_de_ataque,
       count(*) FILTER (WHERE id NOT LIKE 'CTRL%' AND negado) AS negadas,
       count(*) FILTER (WHERE id NOT LIKE 'CTRL%' AND NOT negado) AS abertas,
       count(*) FILTER (WHERE id LIKE 'CTRL%' AND NOT negado) AS controles_positivos_ok
  FROM rt_aux.res;
\echo '--- integridade: dados de partida intactos'
SELECT (SELECT telefone FROM saas.paciente WHERE id='bbbbbbbb-0000-0000-0003-000000000001') AS telefone_pacB,
       (SELECT tentativas_codigo FROM saas.link_paciente WHERE id='eeeeeeee-0000-0000-0007-000000000001') AS tentativas_link,
       (SELECT chave_storage||'/'||status_varredura FROM saas.anexo_encaminhamento) AS anexo,
       (SELECT count(*) FROM saas.contrarreferencia) AS contrarreferencias,
       (SELECT count(*) FROM saas.agendamento) AS agendamentos;
