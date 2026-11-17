\set ON_ERROR_STOP off
SET search_path = saas, public;
-- semente minima (superusuario)
INSERT INTO clinica(id,nome) VALUES ('aaaaaaaa-0000-0000-0000-000000000001','A'),('bbbbbbbb-0000-0000-0000-000000000001','B');
INSERT INTO usuario(id,sub_oidc,nome,email) VALUES ('aaaaaaaa-0000-0000-0001-000000000002','recA','RecA','r@a'),('aaaaaaaa-0000-0000-0001-000000000003','medA','MedA','m@a');
INSERT INTO usuario_clinica(usuario_id,clinica_id,papel) VALUES ('aaaaaaaa-0000-0000-0001-000000000002','aaaaaaaa-0000-0000-0000-000000000001','RECEPCAO'),('aaaaaaaa-0000-0000-0001-000000000003','aaaaaaaa-0000-0000-0000-000000000001','MEDICO');
INSERT INTO profissional(id,crm,crm_uf,nome,usuario_id) VALUES ('aaaaaaaa-0000-0000-0002-000000000001','111','PE','MedA','aaaaaaaa-0000-0000-0001-000000000003'),('eeeeeeee-0000-0000-0002-000000000001','999','PE','Encaminhador',NULL),('bbbbbbbb-0000-0000-0002-000000000001','222','PE','MedB',NULL);
INSERT INTO profissional_clinica(id,profissional_id,clinica_id) VALUES ('bbbbbbbb-0000-0000-0004-000000000001','bbbbbbbb-0000-0000-0002-000000000001','bbbbbbbb-0000-0000-0000-000000000001');
INSERT INTO especialidade(id,nome) VALUES ('dddddddd-0000-0000-0000-000000000001','Ortopedia');
INSERT INTO paciente(id,nome,telefone) VALUES ('bbbbbbbb-0000-0000-0003-000000000001','Paciente de B','+5581900000001');
INSERT INTO paciente_clinica(paciente_id,clinica_id) VALUES ('bbbbbbbb-0000-0000-0003-000000000001','bbbbbbbb-0000-0000-0000-000000000001');
INSERT INTO encaminhamento(id,profissional_origem_id,paciente_id,especialidade_destino_id,clinica_destino_id,motivo_cifrado,urgencia,status,expira_em)
 VALUES ('eeeeeeee-0000-0000-0005-000000000001','eeeeeeee-0000-0000-0002-000000000001','bbbbbbbb-0000-0000-0003-000000000001','dddddddd-0000-0000-0000-000000000001','aaaaaaaa-0000-0000-0000-000000000001','\x01','ROTINA','ATENDIDO',now()+interval '30 days');
INSERT INTO consentimento(paciente_id,finalidade,encaminhamento_id,clinica_id,texto_aceito,versao_texto,canal) VALUES ('bbbbbbbb-0000-0000-0003-000000000001','COMPARTILHAR_CASO','eeeeeeee-0000-0000-0005-000000000001','aaaaaaaa-0000-0000-0000-000000000001','t','1','WHATSAPP');
INSERT INTO link_paciente(id,encaminhamento_id,paciente_id,token_hash,expira_em,codigo_hash,tentativas_codigo) VALUES ('eeeeeeee-0000-0000-0007-000000000001','eeeeeeee-0000-0000-0005-000000000001','bbbbbbbb-0000-0000-0003-000000000001','\x0101',now()+interval '1 day','\xaaaa',9);
INSERT INTO anexo_encaminhamento(id,encaminhamento_id,chave_storage,tipo_mime,tamanho_bytes,sha256,enviado_por_tipo,enviado_por_id) VALUES ('eeeeeeee-0000-0000-0008-000000000001','eeeeeeee-0000-0000-0005-000000000001','obj-1','application/pdf',10,'\x00','PROFISSIONAL','eeeeeeee-0000-0000-0002-000000000001');
\echo '======== SONDAS COMO saas_app ========'
SET ROLE saas_app;
SET search_path = saas;

\echo '--- RT1: recepcao A vincula paciente de B por UUID e troca o TELEFONE global dele'
BEGIN;
SELECT set_config('app.clinica_id','aaaaaaaa-0000-0000-0000-000000000001',true), set_config('app.usuario','aaaaaaaa-0000-0000-0001-000000000002',true), set_config('app.papel','RECEPCAO',true);
INSERT INTO paciente_clinica(paciente_id,clinica_id) VALUES ('bbbbbbbb-0000-0000-0003-000000000001','aaaaaaaa-0000-0000-0000-000000000001');
UPDATE paciente SET telefone='+5581999999999' WHERE id='bbbbbbbb-0000-0000-0003-000000000001';
SELECT id, telefone FROM paciente;
ROLLBACK;

\echo '--- RT2: PUBLICO_LINK zera tentativas, troca codigo_hash e estende expiracao do proprio link'
BEGIN;
SELECT set_config('app.papel','PUBLICO_LINK',true), set_config('app.link_token_hash','0101',true);
UPDATE link_paciente SET tentativas_codigo=0, codigo_hash='\xbeef', expira_em=now()+interval '365 days', codigo_expira_em=now()+interval '365 days';
SELECT tentativas_codigo, codigo_hash, expira_em > now()+interval '300 days' AS estendido FROM link_paciente;
ROLLBACK;

\echo '--- RT3: qualquer conexao saas_app declara SISTEMA e troca chave_storage de anexo PENDENTE'
BEGIN;
SELECT set_config('app.papel','SISTEMA',true);
UPDATE anexo_encaminhamento SET chave_storage='objeto-de-outro-encaminhamento', tipo_mime='image/png', status_varredura='LIMPO';
SELECT chave_storage, status_varredura FROM anexo_encaminhamento;
ROLLBACK;

\echo '--- RT4: contexto forjado so por GUC: PACIENTE com paciente_id alheio le paciente, encaminhamento e link'
BEGIN;
SELECT set_config('app.papel','PACIENTE',true), set_config('app.paciente_id','bbbbbbbb-0000-0000-0003-000000000001',true);
SELECT (SELECT count(*) FROM paciente) pac, (SELECT count(*) FROM encaminhamento) enc, (SELECT count(*) FROM anexo_encaminhamento) anexos;
ROLLBACK;

\echo '--- RT5: ENCAMINHADOR com profissional_id de outro medico (CRM publico) le os encaminhamentos dele'
BEGIN;
SELECT set_config('app.papel','ENCAMINHADOR',true), set_config('app.profissional_id','eeeeeeee-0000-0000-0002-000000000001',true);
SELECT count(*) AS encaminhamentos_lidos, (SELECT count(*) FROM anexo_encaminhamento) anexos FROM encaminhamento;
ROLLBACK;

\echo '--- RT6: auditoria forjada: ENCAMINHADOR grava evento com ator_id e papel de terceiro'
BEGIN;
SELECT set_config('app.papel','ENCAMINHADOR',true), set_config('app.profissional_id','eeeeeeee-0000-0000-0002-000000000001',true);
INSERT INTO evento_auditoria(ator_papel,ator_id,acao,recurso_tipo) VALUES ('ADMIN','aaaaaaaa-0000-0000-0001-000000000002','LER_ENCAMINHAMENTO','encaminhamento');
SELECT 'inserido' ;
ROLLBACK;

\echo '--- RT7: PACIENTE marca agendamento na clinica B, profissional qualquer, sem encaminhamento nem vaga'
BEGIN;
SELECT set_config('app.papel','PACIENTE',true), set_config('app.paciente_id','bbbbbbbb-0000-0000-0003-000000000001',true);
INSERT INTO agendamento(clinica_id,profissional_clinica_id,paciente_id,inicio,fim,origem,chave_idempotencia) VALUES ('bbbbbbbb-0000-0000-0000-000000000001','bbbbbbbb-0000-0000-0004-000000000001','bbbbbbbb-0000-0000-0003-000000000001',now()+interval '1 day',now()+interval '1 day 30 min','SITE','k1');
SELECT 'agendado';
ROLLBACK;

\echo '--- RT8: MEDICO de A assina contrarreferencia como outro profissional (app.profissional_id nao conferido)'
BEGIN;
SELECT set_config('app.clinica_id','aaaaaaaa-0000-0000-0000-000000000001',true), set_config('app.usuario','aaaaaaaa-0000-0000-0001-000000000003',true), set_config('app.papel','MEDICO',true), set_config('app.profissional_id','bbbbbbbb-0000-0000-0002-000000000001',true);
INSERT INTO contrarreferencia(encaminhamento_id,clinica_id,autor_profissional_id,conduta_cifrada) VALUES ('eeeeeeee-0000-0000-0005-000000000001','aaaaaaaa-0000-0000-0000-000000000001','bbbbbbbb-0000-0000-0002-000000000001','\x02');
SELECT 'contrarreferencia gravada com autor MedB por usuario MedA';
ROLLBACK;

\echo '--- RT9: oraculo por erro: ENCAMINHADOR cadastra CRM existente (resultado: erro de unicidade sem DETAIL, so revela existencia)'
BEGIN;
SELECT set_config('app.papel','ENCAMINHADOR',true);
INSERT INTO profissional(crm,crm_uf,nome) VALUES ('222','PE','x');
ROLLBACK;

\echo '--- RT10: PACIENTE pede o proprio paciente em contexto e altera telefone (persistencia apos 1 acesso)'
BEGIN;
SELECT set_config('app.papel','PACIENTE',true), set_config('app.paciente_id','bbbbbbbb-0000-0000-0003-000000000001',true);
UPDATE paciente SET telefone='+5581988888888';
SELECT telefone FROM paciente;
ROLLBACK;
