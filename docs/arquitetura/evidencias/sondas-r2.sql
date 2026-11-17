-- =====================================================================
-- sondas-r2.sql : sondas NOVAS da rodada de revisao 2 (Executor), itens 1 a 7 da devolucao.
-- Alvo: docs/arquitetura/modelo-v2.sql (r2). Executado por teste-r2.sh num cluster limpo
-- (.pgexec2, porta 5494, usuario de SO pgtest). Cada passo conecta com o papel REAL (\c),
-- para session_user e current_user serem os de producao. Fluxos pelo caminho real:
-- sessao de equipe por sessao_equipe_abre (saas_auth), link e codigo por jobs_* (saas_jobs),
-- sessao de paciente por paciente_confirma_codigo (saas_app).
-- Legenda: esperado NEGADO = ataque tem que falhar (erro, 0 linhas, NULL ou false);
--          POSITIVO = controle que tem que funcionar.
-- =====================================================================
\set ON_ERROR_STOP on
\set QUIET on
\pset pager off
SET search_path = saas, public;

CREATE SCHEMA r2;
CREATE TABLE r2.res(n serial, item text, id text, descricao text, papel text, esperado text, obtido text, ok boolean);
GRANT USAGE ON SCHEMA r2 TO PUBLIC;
GRANT INSERT, SELECT ON r2.res TO PUBLIC;
GRANT USAGE ON SEQUENCE r2.res_n_seq TO PUBLIC;
-- executa como o papel corrente; devolve 'OK n=<linhas>' ou 'ERRO: ...'. Efeito so persiste se OK.
CREATE FUNCTION r2.tenta(q text) RETURNS text LANGUAGE plpgsql AS $$
DECLARE n bigint;
BEGIN
  EXECUTE q; GET DIAGNOSTICS n = ROW_COUNT; RETURN 'OK n=' || n;
EXCEPTION WHEN OTHERS THEN RETURN 'ERRO: ' || left(replace(SQLERRM, E'\n', ' '), 100);
END $$;
-- valor escalar de uma consulta como o papel corrente (ou o erro)
CREATE FUNCTION r2.val(q text) RETURNS text LANGUAGE plpgsql AS $$
DECLARE v text;
BEGIN
  EXECUTE q INTO v; RETURN coalesce(v, 'NULL');
EXCEPTION WHEN OTHERS THEN RETURN 'ERRO: ' || left(replace(SQLERRM, E'\n', ' '), 100);
END $$;
-- registra: esperado NEGADO aceita ERRO, 'OK n=0', '0', 'NULL', 'false'; POSITIVO o contrario; 'IGUAL:x' compara.
CREATE FUNCTION r2.reg(item text, id text, descr text, esperado text, obtido text) RETURNS void LANGUAGE sql AS $$
  INSERT INTO r2.res(item,id,descricao,papel,esperado,obtido,ok)
  VALUES (item, id, descr, current_user, esperado, obtido,
    CASE WHEN esperado = 'NEGADO' THEN obtido LIKE 'ERRO%' OR obtido IN ('OK n=0','0','NULL','false','f')
         WHEN esperado = 'ERRO' THEN obtido LIKE 'ERRO%'
         WHEN esperado = 'POSITIVO' THEN NOT (obtido LIKE 'ERRO%' OR obtido IN ('OK n=0','0','NULL','false','f'))
         WHEN esperado = 'OK' THEN obtido LIKE 'OK%'
         WHEN esperado LIKE 'IGUAL:%' THEN obtido = substr(esperado, 7)
         ELSE false END) $$;

-- ---------------------------------------------------------------------
-- Semente (superusuario)
-- ---------------------------------------------------------------------
\set cA 'aaaaaaaa-0000-0000-0000-000000000001'
\set eC 'dddddddd-0000-0000-0000-000000000001'
\set pE 'eeeeeeee-0000-0000-0002-000000000001'
\set pA 'aaaaaaaa-0000-0000-0002-000000000001'
\set pcA 'aaaaaaaa-0000-0000-0004-000000000001'
INSERT INTO clinica(id,nome) VALUES (:'cA','Clinica A');
INSERT INTO flag_clinica(clinica_id,chave,ligada) VALUES (:'cA','REDE_ENCAMINHAMENTO',true);
INSERT INTO especialidade(id,nome) VALUES (:'eC','Cardiologia');
INSERT INTO clinica_especialidade VALUES (:'cA',:'eC');
INSERT INTO usuario(id,sub_oidc,nome,email) VALUES
 ('aaaaaaaa-0000-0000-0001-000000000001','admA','AdmA','a@a'),
 ('aaaaaaaa-0000-0000-0001-000000000002','recA','RecA','r@a'),
 ('aaaaaaaa-0000-0000-0001-000000000003','medA','MedA','m@a'),
 ('aaaaaaaa-0000-0000-0001-000000000009','vaiSair','Vai Sair','s@a');
INSERT INTO usuario_clinica(usuario_id,clinica_id,papel) VALUES
 ('aaaaaaaa-0000-0000-0001-000000000001',:'cA','ADMIN'),
 ('aaaaaaaa-0000-0000-0001-000000000002',:'cA','RECEPCAO'),
 ('aaaaaaaa-0000-0000-0001-000000000003',:'cA','MEDICO'),
 ('aaaaaaaa-0000-0000-0001-000000000009',:'cA','ADMIN');
INSERT INTO profissional(id,crm,crm_uf,nome,telefone,usuario_id,canal_verificado_em) VALUES
 (:'pE','999','PE','Dra Encaminha','+5581999990001',NULL,now()),
 (:'pA','111','PE','Dr Destino','+5581999990002','aaaaaaaa-0000-0000-0001-000000000003',now());
INSERT INTO profissional_especialidade VALUES (:'pA',:'eC');
INSERT INTO profissional_clinica(id,profissional_id,clinica_id,recebe_encaminhamento) VALUES (:'pcA',:'pA',:'cA',true);
-- sessao do encaminhador com token conhecido (o fluxo real do desafio ja e coberto pelas baterias r1)
INSERT INTO sessao(token_hash,tipo,profissional_id,expira_em) VALUES
 (sha256(decode(repeat('ad',32),'hex')),'ENCAMINHADOR',:'pE',now()+interval '1 hour');
\set tokE 'adadadadadadadadadadadadadadadadadadadadadadadadadadadadadadadad'

-- sessoes de equipe pelo componente de login (papel saas_auth)
\c - saas_auth
SELECT sessao_equipe_abre('recA') AS tokrec, sessao_equipe_abre('admA') AS tokadm, sessao_equipe_abre('vaiSair') AS toksai \gset

-- =====================================================================
-- Item 4 (Red Team T-18): telefone e contato, nao identidade. ADR-0036.
-- =====================================================================
\c - saas_app
SELECT set_config('app.sessao', :'tokE', false) IS NOT NULL AS ok \gset
SELECT encaminhamento_cria('Maria da Silva','+5581900000077',DATE '1955-03-01',NULL,NULL,:'eC','\x0a','ROTINA') AS enc_maria \gset
SELECT encaminhamento_cria('Joao da Silva','+5581900000077',DATE '2015-07-09',NULL,NULL,:'eC','\x0b','URGENTE') AS enc_joao \gset
-- mesma pessoa (nome com caixa e espaco diferentes, mesma data, mesmo telefone): segundo caso da Maria
SELECT encaminhamento_cria('  MARIA   da silva ','+5581900000077',DATE '1955-03-01',NULL,NULL,:'eC','\x0c','ROTINA') AS enc_maria2 \gset
-- mesmo nome e telefone, sem data de nascimento: nunca deduplica
SELECT encaminhamento_cria('Ana Lima','+5581900000099',NULL,NULL,NULL,:'eC','\x0d','ROTINA') AS enc_ana1 \gset
SELECT encaminhamento_cria('Ana Lima','+5581900000099',NULL,NULL,NULL,:'eC','\x0e','ROTINA') AS enc_ana2 \gset
-- mesmo nome, data e telefone, mas CPF diferente: pessoas diferentes (homonimos na mesma casa)
SELECT encaminhamento_cria('Jose Alves','+5581900000055',DATE '1960-01-01','\xc1','\xd1',:'eC','\x0f','ROTINA') AS enc_jose1 \gset
SELECT encaminhamento_cria('Jose Alves','+5581900000055',DATE '1960-01-01','\xc2','\xd2',:'eC','\x10','ROTINA') AS enc_jose2 \gset
-- mesmo CPF com telefone novo: mesma pessoa
SELECT encaminhamento_cria('Jose Alves','+5581900000056',DATE '1960-01-01','\xc1','\xd1',:'eC','\x11','ROTINA') AS enc_jose3 \gset
SELECT r2.reg('4','R2-4a','encaminhador: mae e filho com o mesmo telefone, sem CPF, viram 2 pacientes (N6a)','IGUAL:2',
  r2.val(format('select count(distinct paciente_id) from encaminhamento where id in (%L,%L)', :'enc_maria', :'enc_joao')));
SELECT r2.reg('4','R2-4b','mesmo nome e telefone SEM data de nascimento: nao deduplica (2 pacientes)','IGUAL:2',
  r2.val(format('select count(distinct paciente_id) from encaminhamento where id in (%L,%L)', :'enc_ana1', :'enc_ana2')));
SELECT r2.reg('4','R2-4c','mesmo nome, data e telefone com CPF diferente: 2 pacientes','IGUAL:2',
  r2.val(format('select count(distinct paciente_id) from encaminhamento where id in (%L,%L)', :'enc_jose1', :'enc_jose2')));
SELECT r2.reg('4','R2-4d','controle: nome normalizado + data + telefone iguais, sem CPF: mesma pessoa (fluxo do link sem CPF)','IGUAL:1',
  r2.val(format('select count(distinct paciente_id) from encaminhamento where id in (%L,%L)', :'enc_maria', :'enc_maria2')));
SELECT r2.reg('4','R2-4e','controle: mesmo CPF com telefone novo: mesma pessoa','IGUAL:1',
  r2.val(format('select count(distinct paciente_id) from encaminhamento where id in (%L,%L)', :'enc_jose1', :'enc_jose3')));
SELECT r2.reg('4','R2-4f','controle: encaminhamento sem CPF do paciente e aceito (idoso sem CPF no fluxo do link)','POSITIVO', :'enc_maria');
RESET app.sessao;
-- recepcao A (N6b)
SELECT set_config('app.sessao', :'tokrec', false), set_config('app.clinica_id', :'cA', false), set_config('app.papel','RECEPCAO', false) \gset
SELECT paciente_cadastra_na_clinica('Maria Souza','+5581900000088',DATE '1950-01-01',NULL,NULL) AS rp1 \gset
SELECT paciente_cadastra_na_clinica('Pedro Souza','+5581900000088',DATE '2018-01-01',NULL,NULL) AS rp2 \gset
SELECT paciente_cadastra_na_clinica('maria  souza','+5581900000088',DATE '1950-01-01',NULL,NULL) AS rp3 \gset
SELECT r2.reg('4','R2-4g','recepcao: avo e neto com o mesmo telefone recebem ids diferentes (N6b)','NEGADO',
  CASE WHEN :'rp1' = :'rp2' THEN 'fundiu' ELSE 'false' END);
SELECT r2.reg('4','R2-4h','recepcao: nome gravado para o neto e o dele','IGUAL:Pedro Souza', r2.val(format('select nome from paciente where id=%L', :'rp2')));
SELECT r2.reg('4','R2-4i','controle recepcao: mesma pessoa (nome normalizado + data + telefone) reaproveita o cadastro','IGUAL:true',
  (:'rp1' = :'rp3')::text);
RESET app.sessao; RESET app.clinica_id; RESET app.papel;

-- =====================================================================
-- Item 5 (Red Team I-19): sessao do paciente vale para o CASO do link.
-- Maria tem dois casos (enc_maria e enc_maria2, mesma pessoa por R2-4d).
-- =====================================================================
\c - saas_jobs
SELECT jobs_envio_link_paciente(:'enc_maria') AS env_l1 \gset
SELECT segredo AS tok_l1 FROM jobs_envio_prepara(:'env_l1') \gset
SELECT jobs_envio_resultado(:'env_l1','ACEITO','p1') AS t2a \gset
SELECT jobs_envio_link_paciente(:'enc_maria2') AS env_l2 \gset
SELECT segredo AS tok_l2 FROM jobs_envio_prepara(:'env_l2') \gset
SELECT jobs_envio_resultado(:'env_l2','ACEITO','p2') AS t2b \gset
\c - saas_app
SELECT paciente_pede_codigo(:'tok_l1') AS pediu \gset
\c - saas_jobs
SELECT envio_id AS env_c1 FROM jobs_envios_pendentes(100) WHERE finalidade='CODIGO_PACIENTE' LIMIT 1 \gset
SELECT segredo AS cod1 FROM jobs_envio_prepara(:'env_c1') \gset
\c - saas_app
SELECT paciente_confirma_codigo(:'tok_l1', :'cod1') AS sess_m1 \gset
SELECT set_config('app.sessao', :'sess_m1', false) IS NOT NULL AS ok \gset
SELECT r2.reg('5','R2-5a','controle: sessao do link do caso 1 ve o caso 1','IGUAL:1', r2.val(format('select count(*) from encaminhamento where id=%L', :'enc_maria')));
SELECT r2.reg('5','R2-5b','sessao do caso 1 le o caso 2 da MESMA pessoa (encaminhamento)','NEGADO', r2.val(format('select count(*) from encaminhamento where id=%L', :'enc_maria2')));
SELECT r2.reg('5','R2-5c','sessao do caso 1 le historico do caso 2','NEGADO', r2.val(format('select count(*) from historico_status_encaminhamento where encaminhamento_id=%L', :'enc_maria2')));
SELECT r2.reg('5','R2-5d','sessao do caso 1 cancela o caso 2 (T10 fora do caso)','NEGADO', r2.tenta(format('update encaminhamento set status=''CANCELADO'' where id=%L', :'enc_maria2')));
SELECT r2.reg('5','R2-5e','sessao do caso 1 escolhe destino e consente no caso 2 (T3 fora do caso)','NEGADO', r2.tenta(format('select paciente_solicita(%L,%L,NULL,''t'',''v1'')', :'enc_maria2', :'cA')));
SELECT r2.reg('5','R2-5f','sessao do caso 1 grava consentimento no caso 2 direto','NEGADO',
  r2.tenta(format('insert into consentimento(paciente_id,finalidade,encaminhamento_id,clinica_id,texto_aceito,versao_texto,canal) select paciente_id,''COMPARTILHAR_CASO'',id,%L,''t'',''v1'',''SITE'' from encaminhamento where id=%L', :'cA', :'enc_maria2')));
SELECT r2.reg('5','R2-5g','sessao do caso 1 anexa arquivo no caso 2','NEGADO',
  r2.tenta(format('insert into anexo_encaminhamento(encaminhamento_id,tipo_mime,tamanho_bytes,sha256,enviado_por_tipo,enviado_por_id) values (%L,''application/pdf'',1,''\x01'',''PACIENTE'',ator_paciente())', :'enc_maria2')));
SELECT r2.reg('5','R2-5h','total de encaminhamentos visiveis a sessao do caso 1','IGUAL:1', r2.val('select count(*) from encaminhamento'));
SELECT r2.reg('5','R2-5i','controle: T3 no proprio caso funciona','POSITIVO', r2.tenta(format('select paciente_solicita(%L,%L,NULL,''t'',''v1'')', :'enc_maria', :'cA')));
SELECT r2.reg('5','R2-5j','depois do T3 do caso 1, consentimento visivel so do caso 1','IGUAL:1', r2.val('select count(*) from consentimento'));
RESET app.sessao;
-- caso 2 vai a SOLICITADO por uma sessao propria (para a agenda do item 2)
SELECT paciente_pede_codigo(:'tok_l2') AS pediu2 \gset
\c - saas_jobs
SELECT envio_id AS env_c2 FROM jobs_envios_pendentes(100) WHERE finalidade='CODIGO_PACIENTE' LIMIT 1 \gset
SELECT segredo AS cod2 FROM jobs_envio_prepara(:'env_c2') \gset
\c - saas_app
SELECT paciente_confirma_codigo(:'tok_l2', :'cod2') AS sess_m2 \gset
SELECT set_config('app.sessao', :'sess_m2', false) IS NOT NULL AS ok \gset
SELECT r2.reg('5','R2-5k','sessao do caso 2 ve o caso 1 (simetria)','NEGADO', r2.val(format('select count(*) from encaminhamento where id=%L', :'enc_maria')));
SELECT r2.reg('5','R2-5l','sessao do caso 2 ve agendamento/consentimento do caso 1','NEGADO',
  r2.val(format('select (select count(*) from consentimento where encaminhamento_id=%L) + (select count(*) from agendamento where encaminhamento_id=%L)', :'enc_maria', :'enc_maria')));
SELECT r2.reg('5','R2-5m','controle: T3 do caso 2 na propria sessao','POSITIVO', r2.tenta(format('select paciente_solicita(%L,%L,NULL,''t'',''v1'')', :'enc_maria2', :'cA')));
RESET app.sessao;

-- =====================================================================
-- Item 2 (Testador F2): agendamento final nao volta; invariante com o encaminhamento.
-- =====================================================================
SELECT set_config('app.sessao', :'tokrec', false), set_config('app.clinica_id', :'cA', false), set_config('app.papel','RECEPCAO', false) \gset
SELECT destino_confirma_horario(:'enc_maria', :'pcA', now()+interval '3 days', now()+interval '3 days 30 min', 'k-m1') AS ag1 \gset
SELECT destino_confirma_horario(:'enc_maria2', :'pcA', now()+interval '4 days', now()+interval '4 days 30 min', 'k-m2') AS ag2 \gset
SELECT r2.reg('2','R2-2a','controle: recepcao cancela agendamento ativo do caso 1','POSITIVO', r2.tenta(format('update agendamento set status=''CANCELADO'' where id=%L', :'ag1')));
\c - saas_jobs
SELECT jobs_agendamento_desfeito(:'ag1') AS t7 \gset
\c - saas_app
SELECT set_config('app.sessao', :'tokrec', false), set_config('app.clinica_id', :'cA', false), set_config('app.papel','RECEPCAO', false) \gset
SELECT r2.reg('2','R2-2b','pre: T7 devolveu o caso 1 a SOLICITADO','IGUAL:SOLICITADO', r2.val(format('select status from encaminhamento where id=%L', :'enc_maria')));
SELECT r2.reg('2','R2-2c','recepcao reativa agendamento CANCELADO -> AGENDADO (F2)','ERRO', r2.tenta(format('update agendamento set status=''AGENDADO'' where id=%L', :'ag1')));
SELECT r2.reg('2','R2-2d','recepcao reativa CANCELADO -> CONFIRMADO','ERRO', r2.tenta(format('update agendamento set status=''CONFIRMADO'' where id=%L', :'ag1')));
SELECT r2.reg('2','R2-2e','recepcao muda horario de agendamento CANCELADO','ERRO', r2.tenta(format('update agendamento set inicio=inicio+interval ''1 hour'', fim=fim+interval ''1 hour'' where id=%L', :'ag1')));
SELECT r2.reg('2','R2-2f','invariante: caso SOLICITADO sem agendamento ativo','IGUAL:0', r2.val(format('select count(*) from agendamento where encaminhamento_id=%L and status in (''AGENDADO'',''CONFIRMADO'')', :'enc_maria')));
SELECT r2.reg('2','R2-2g','controle: AGENDADO -> CONFIRMADO no caso 2','POSITIVO', r2.tenta(format('update agendamento set status=''CONFIRMADO'' where id=%L', :'ag2')));
SELECT r2.reg('2','R2-2h','CONFIRMADO -> AGENDADO (volta)','ERRO', r2.tenta(format('update agendamento set status=''AGENDADO'' where id=%L', :'ag2')));
SELECT r2.reg('2','R2-2i','controle: CONFIRMADO -> REALIZADO','POSITIVO', r2.tenta(format('update agendamento set status=''REALIZADO'' where id=%L', :'ag2')));
\c - saas_jobs
SELECT jobs_consulta_realizada(:'ag2') AS t5 \gset
\c - saas_app
SELECT set_config('app.sessao', :'tokrec', false), set_config('app.clinica_id', :'cA', false), set_config('app.papel','RECEPCAO', false) \gset
SELECT r2.reg('2','R2-2j','pre: T5 levou o caso 2 a ATENDIDO','IGUAL:ATENDIDO', r2.val(format('select status from encaminhamento where id=%L', :'enc_maria2')));
SELECT r2.reg('2','R2-2k','recepcao reabre REALIZADO -> AGENDADO depois de T5 (F2)','ERRO', r2.tenta(format('update agendamento set status=''AGENDADO'' where id=%L', :'ag2')));
SELECT r2.reg('2','R2-2l','recepcao troca REALIZADO -> FALTOU (dispararia T7 indevido)','ERRO', r2.tenta(format('update agendamento set status=''FALTOU'' where id=%L', :'ag2')));
SELECT r2.reg('2','R2-2m','recepcao troca REALIZADO -> CANCELADO','ERRO', r2.tenta(format('update agendamento set status=''CANCELADO'' where id=%L', :'ag2')));
SELECT r2.reg('2','R2-2n','invariante: caso ATENDIDO sem agendamento ativo','IGUAL:0', r2.val(format('select count(*) from agendamento where encaminhamento_id=%L and status in (''AGENDADO'',''CONFIRMADO'')', :'enc_maria2')));
-- agendamento comum da recepcao (sem encaminhamento): FALTOU tambem e final
SELECT r2.tenta(format('insert into agendamento(clinica_id,profissional_clinica_id,paciente_id,inicio,fim,origem,chave_idempotencia) values (%L,%L,%L,now()+interval ''9 days'',now()+interval ''9 days 30 min'',''RECEPCAO'',''k-rec'')', :'cA', :'pcA', :'rp1')) AS ins \gset
SELECT r2.reg('2','R2-2o','controle: agendamento comum AGENDADO -> FALTOU','POSITIVO', r2.tenta('update agendamento set status=''FALTOU'' where chave_idempotencia=''k-rec'''));
SELECT r2.reg('2','R2-2p','agendamento comum FALTOU -> AGENDADO','ERRO', r2.tenta('update agendamento set status=''AGENDADO'' where chave_idempotencia=''k-rec'''));
RESET app.sessao; RESET app.clinica_id; RESET app.papel;

-- =====================================================================
-- Item 1 (Testador F1): link e envio nao sobrevivem a estado final.
-- =====================================================================
SELECT set_config('app.sessao', :'tokE', false) IS NOT NULL AS ok \gset
SELECT encaminhamento_cria('Carla Nunes','+5581900000101',DATE '1970-05-05',NULL,NULL,:'eC','\x21','ROTINA') AS enc_c1 \gset
SELECT encaminhamento_cria('Davi Nunes','+5581900000102',DATE '1971-05-05',NULL,NULL,:'eC','\x22','ROTINA') AS enc_c2 \gset
SELECT encaminhamento_cria('Edu Nunes','+5581900000103',DATE '1972-05-05',NULL,NULL,:'eC','\x23','ROTINA') AS enc_c3 \gset
RESET app.sessao;
\c - saas_jobs
-- c1: envio de link PENDENTE criado com o caso CRIADO
SELECT jobs_envio_link_paciente(:'enc_c1') AS env_c1l \gset
-- c2: link entregue (T2) e codigo pedido, ainda nao preparado
SELECT jobs_envio_link_paciente(:'enc_c2') AS env_c2l \gset
SELECT segredo AS tok_c2 FROM jobs_envio_prepara(:'env_c2l') \gset
SELECT jobs_envio_resultado(:'env_c2l','ACEITO','p3') AS t2c \gset
-- c3: link entregue (T2), para T8
SELECT jobs_envio_link_paciente(:'enc_c3') AS env_c3l \gset
SELECT segredo AS tok_c3 FROM jobs_envio_prepara(:'env_c3l') \gset
SELECT jobs_envio_resultado(:'env_c3l','ACEITO','p4') AS t2d \gset
\c - saas_app
SELECT r2.reg('1','R2-1a','controle: link do caso 2 valido antes do cancelamento','IGUAL:1', r2.val(format('select count(*) from link_consulta(%L)', :'tok_c2')));
SELECT paciente_pede_codigo(:'tok_c2') AS pediu_c2 \gset
\c - saas_jobs
SELECT envio_id AS env_c2c FROM jobs_envios_pendentes(100) WHERE finalidade='CODIGO_PACIENTE' LIMIT 1 \gset
\c - saas_app
-- origem cancela os casos 1 e 2 (T9)
SELECT set_config('app.sessao', :'tokE', false) IS NOT NULL AS ok \gset
SELECT r2.reg('1','R2-1b','controle: origem cancela o caso 1 (T9, CRIADO)','POSITIVO', r2.tenta(format('update encaminhamento set status=''CANCELADO'' where id=%L', :'enc_c1')));
SELECT r2.reg('1','R2-1c','controle: origem cancela o caso 2 (T9, ENVIADO_AO_PACIENTE)','POSITIVO', r2.tenta(format('update encaminhamento set status=''CANCELADO'' where id=%L', :'enc_c2')));
RESET app.sessao;
\c - saas_jobs
SELECT r2.reg('1','R2-1d','envio de link PENDENTE de caso CANCELADO: jobs_envio_prepara entrega token/telefone','NEGADO',
  r2.val(format('select count(*) from jobs_envio_prepara(%L) where segredo is not null or contato is not null', :'env_c1l')));
SELECT r2.reg('1','R2-1e','envio de CODIGO pedido antes do cancelamento: jobs_envio_prepara entrega codigo/telefone','NEGADO',
  r2.val(format('select count(*) from jobs_envio_prepara(%L) where segredo is not null or contato is not null', :'env_c2c')));
SELECT r2.reg('1','R2-1f','jobs_envios_pendentes ainda lista envio de caso CANCELADO','NEGADO',
  r2.val(format('select count(*) from jobs_envios_pendentes(100) where envio_id in (%L,%L)', :'env_c1l', :'env_c2c')));
SELECT r2.reg('1','R2-1g','novo link para caso CANCELADO','ERRO', r2.tenta(format('select jobs_envio_link_paciente(%L)', :'enc_c1')));
\c - saas_app
SELECT r2.reg('1','R2-1h','link nao usado de caso CANCELADO ainda valido em link_consulta (F1)','NEGADO', r2.val(format('select count(*) from link_consulta(%L)', :'tok_c2')));
SELECT r2.reg('1','R2-1i','pedir codigo pelo link de caso CANCELADO','NEGADO', r2.val(format('select paciente_pede_codigo(%L)', :'tok_c2')));
SELECT r2.reg('1','R2-1j','abrir sessao pelo link de caso CANCELADO (qualquer codigo)','NEGADO', r2.val(format('select paciente_confirma_codigo(%L,''000000'')', :'tok_c2')));
-- T8: caso 3 expira (fixture: expira_em no passado pelo superusuario)
\c - pgtest
SET session_replication_role = replica;
UPDATE saas.encaminhamento SET expira_em = now() - interval '1 minute' WHERE id = :'enc_c3';
SET session_replication_role = origin;
\c - saas_jobs
SELECT jobs_expirar_encaminhamentos() AS expirados \gset
\c - saas_app
SELECT r2.reg('1','R2-1k','pre: T8 expirou o caso 3','IGUAL:true', (:'expirados'::int >= 1)::text);
SELECT r2.reg('1','R2-1l','link de caso EXPIRADO ainda valido em link_consulta','NEGADO', r2.val(format('select count(*) from link_consulta(%L)', :'tok_c3')));
\c - pgtest
SELECT r2.reg('1','R2-1m','links ativos (nao usados nem revogados) de casos em estado final','IGUAL:0',
  r2.val('select count(*) from saas.link_paciente l join saas.encaminhamento e on e.id=l.encaminhamento_id where e.status in (''CANCELADO'',''EXPIRADO'',''CONTRARREFERIDO'') and l.usado_em is null and l.revogado_em is null'));
SELECT r2.reg('1','R2-1n','envios PENDENTES de link/codigo de casos em estado final','IGUAL:0',
  r2.val('select count(*) from saas.envio_notificacao v join saas.encaminhamento e on e.id=v.encaminhamento_id where e.status in (''CANCELADO'',''EXPIRADO'',''CONTRARREFERIDO'') and v.status=''PENDENTE'''));

-- =====================================================================
-- Item 3 (Testador F3): usuario desativado com sessao viva.
-- =====================================================================
\c - saas_app
SELECT set_config('app.sessao', :'toksai', false), set_config('app.clinica_id', :'cA', false), set_config('app.papel','ADMIN', false) \gset
SELECT r2.reg('3','R2-3a','controle: usuario ativo le profissional','POSITIVO', r2.val('select count(*) from profissional'));
SELECT r2.reg('3','R2-3b','controle: usuario ativo usa catalogo_rede','POSITIVO', r2.val(format('select count(*) from catalogo_rede(%L)', :'eC')));
\c - pgtest
UPDATE saas.usuario SET ativo = false WHERE sub_oidc = 'vaiSair';
\c - saas_app
SELECT set_config('app.sessao', :'toksai', false), set_config('app.clinica_id', :'cA', false), set_config('app.papel','ADMIN', false) \gset
SELECT r2.reg('3','R2-3c','desativado le profissional (F3)','NEGADO', r2.val('select count(*) from profissional'));
SELECT r2.reg('3','R2-3d','desativado le profissional_especialidade','NEGADO', r2.val('select count(*) from profissional_especialidade'));
SELECT r2.reg('3','R2-3e','desativado usa catalogo_rede (F3)','NEGADO', r2.val(format('select count(*) from catalogo_rede(%L)', :'eC')));
SELECT r2.reg('3','R2-3f','desativado: ator_tipo()','NEGADO', r2.val('select ator_tipo()'));
SELECT r2.reg('3','R2-3g','desativado le clinica, usuario, paciente, encaminhamento, agendamento, auditoria','NEGADO',
  r2.val('select (select count(*) from clinica)+(select count(*) from usuario)+(select count(*) from paciente)+(select count(*) from encaminhamento)+(select count(*) from agendamento)+(select count(*) from evento_auditoria)'));
SELECT r2.reg('3','R2-3h','desativado cancela agendamento','NEGADO', r2.tenta('update agendamento set status=''CANCELADO'''));
SELECT r2.reg('3','R2-3i','desativado cadastra paciente','ERRO', r2.tenta('select paciente_cadastra_na_clinica(''X'',''+5581900000999'',NULL,NULL,NULL)'));
RESET app.sessao; RESET app.clinica_id; RESET app.papel;
\c - saas_auth
SELECT r2.reg('3','R2-3j','desativado abre sessao nova pelo login','ERRO', r2.tenta('select sessao_equipe_abre(''vaiSair'')'));

-- =====================================================================
-- Item 6 (Red Team R-07): dono das tabelas contorna gatilho e RLS; alerta de DDL.
-- =====================================================================
\c - pgtest
SELECT r2.reg('6','R2-6a','controle: gatilhos de evento de alerta existem, ativos, donos superusuario','IGUAL:2',
  r2.val('select count(*) from pg_event_trigger t join pg_roles r on r.oid=t.evtowner where t.evtname like ''saas_alerta_ddl%'' and t.evtenabled=''O'' and r.rolsuper'));
BEGIN;
SET LOCAL ROLE saas_owner;
SELECT r2.tenta('alter event trigger saas_alerta_ddl_fim disable') AS o6b,
       r2.tenta('drop event trigger saas_alerta_ddl_drop') AS o6c,
       r2.tenta('alter table saas.historico_status_encaminhamento disable trigger user') AS o6d \gset
ROLLBACK;
SELECT r2.reg('6','R2-6b','(como saas_owner) dono das tabelas desliga o alerta (ALTER EVENT TRIGGER ... DISABLE)','ERRO', :'o6b');
SELECT r2.reg('6','R2-6c','(como saas_owner) dono das tabelas apaga o alerta (DROP EVENT TRIGGER)','ERRO', :'o6c');
SELECT r2.reg('6','R2-6d','(como saas_owner) RESIDUAL documentado (ADR-0027): dono desliga gatilho do historico; o comando passa e fica no log (ver fim do log)','OK', :'o6d');

-- =====================================================================
-- Item 7 (Red Team I-20): token fora de pg_stat_activity.
-- =====================================================================
SELECT r2.reg('7','R2-7a','controle: track_activities=off e log_parameter_max_length=0 nos 3 papeis de login','IGUAL:3',
  r2.val('select count(*) from pg_db_role_setting s join pg_roles r on r.oid=s.setrole where r.rolname in (''saas_app'',''saas_jobs'',''saas_auth'') and ''track_activities=off''=any(s.setconfig) and ''log_parameter_max_length=0''=any(s.setconfig)'));
\c - saas_app
SELECT r2.reg('7','R2-7b','papel web religa track_activities','ERRO', r2.tenta('set track_activities = on'));
\setenv PGHOST :dir
\setenv PGPORT :porta
-- vitima: conexao saas_app que (contra a regra) interpola o token no texto do SQL
\! psql -X -U saas_app -d r2 -qAtc "SELECT set_config('app.sessao','adadadadadadadadadadadadadadadadadadadadadadadadadadadadadadadad',false), pg_sleep(3)" >/dev/null 2>&1 &
SELECT pg_sleep(1) \gset
SELECT r2.reg('7','R2-7c','outra conexao saas_app le o token literal em pg_stat_activity (N4c)','NEGADO',
  r2.val('select count(*) from pg_stat_activity where usename=''saas_app'' and pid<>pg_backend_pid() and query ilike ''%adadadad%'''));
SELECT r2.reg('7','R2-7d','outra conexao saas_app ve o texto de qualquer comando da vitima','NEGADO',
  r2.val('select count(*) from pg_stat_activity where usename=''saas_app'' and pid<>pg_backend_pid() and coalesce(query,'''')<>'''''));
SELECT pg_sleep(3) \gset

-- =====================================================================
\c - pgtest
\o
\echo '===== RESULTADO sondas-r2 ====='
SELECT n, item, id, descricao, papel, esperado, left(obtido, 70) AS obtido, CASE WHEN ok THEN 'PASSOU' ELSE 'FALHOU' END AS r FROM r2.res ORDER BY n;
\echo '===== RESUMO POR ITEM ====='
SELECT item, count(*) AS total, count(*) FILTER (WHERE ok) AS passou, count(*) FILTER (WHERE NOT ok) AS falhou,
       count(*) FILTER (WHERE esperado IN ('NEGADO','ERRO')) AS ataques, count(*) FILTER (WHERE esperado IN ('NEGADO','ERRO') AND ok) AS ataques_negados
  FROM r2.res GROUP BY item ORDER BY item;
SELECT count(*) AS total, count(*) FILTER (WHERE ok) AS passou, count(*) FILTER (WHERE NOT ok) AS falhou FROM r2.res;
