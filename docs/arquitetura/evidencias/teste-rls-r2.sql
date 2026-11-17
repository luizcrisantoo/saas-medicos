-- =====================================================================
-- teste-rls-r2.sql : bateria teste-rls-r1.sql executada contra o modelo r2. Copia fiel,
-- com SO estas diferencas (nenhuma sonda removida; nenhum esperado de ataque afrouxado):
--  R2-A. Controle "ADM_A atualiza agendamento da clinica A" marcava CONFIRMADO em TODOS os
--        agendamentos de A, inclusive os REALIZADO da semente (agE8, agE9). Com r2-2 (finais
--        sem saida) o controle passa a mirar so os ativos (AGENDADO, CONFIRMADO).
--  R2-B. "paciente revoga consentimento de E5" usava a sessao de PAC_A, que nasceu do link
--        de E1. Com I-19 essa sessao NAO alcanca E5: a sonda vira ATAQUE (A continua vendo
--        E5, esperado POSITIVO na verificacao) e o controle de revogacao passa a usar a
--        sessao PAC_A_E5, aberta por um link de E5 (semente nova L5, ja usado).
-- Execucao sem estas mudancas: teste-rls-r1-sem-ajuste-r2.log (as 2 unicas falhas sao estas).
-- =====================================================================
-- =====================================================================
-- (cabecalho original) teste-rls-r1.sql : prova de isolamento do modelo-v2.sql, rodada de revisao 1
-- Base: teste-rls.sql do Testador (rodada 0). Executado por teste-rls-r1.sh.
-- O QUE MUDOU EM RELACAO A RODADA 0 (nenhuma sonda foi removida nem enfraquecida):
--  1. Infra: k, res, ctx e sonda passaram de pg_temp para o schema teste_aux, para a
--     mesma bateria rodar tambem como saas_jobs e saas_auth (papeis novos, ADR-0024).
--  2. Contexto: ctx continua gravando as GUCs antigas (app.usuario, app.profissional_id,
--     app.paciente_id, app.link_token_hash) e agora grava tambem app.sessao. O modelo r1
--     ignora as GUCs antigas; os contextos forjados provam isso.
--  3. Esperado '0' vira 'ERRO' quando o papel web nao tem mais privilegio na tabela
--     (sessao, link_paciente, desafio_encaminhador, envio_notificacao): erro e mais
--     forte que 0 linhas.
--  4. Sete sondas da secao f eram "ataque e depois verificacao = 0"; agora o passo de
--     ataque falha com erro antes da verificacao. Esperado passou de '0' para 'NEGADO'
--     (erro ou 0). Marcadas com [r1: NEGADO].
--  5. Sondas que esperavam SISTEMA positivo pelo papel web (T8 e "SISTEMA ve expirados")
--     agora esperam negado pelo papel web; o positivo de T8 foi para a secao jobs, rodando
--     como saas_jobs (Red Team, itens 2 e 16).
--  6. Sondas INFO da maquina de estados viraram ERRO esperado (Red Team, item 10).
--  7. Controle "ADM_A insere paciente_clinica(A)" agora usa paciente_cadastra_na_clinica
--     (insert direto passou a ser proibido, Red Team item 6, e ganhou sonda propria).
--  8. Secoes novas: r1 (itens 1 a 19 do Red Team), matriz (pares de status x ator),
--     jobs (saas_jobs) e auth (saas_auth).
-- Convencao de esperado: ERRO | 0 | NEGADO (erro ou 0) | POSITIVO (>0) | OK | INFO
-- =====================================================================
\set ON_ERROR_STOP on
\set QUIET on
\pset pager off
\pset format aligned

\set cA   'aaaaaaaa-0000-0000-0000-000000000001'
\set cB   'bbbbbbbb-0000-0000-0000-000000000001'
\set uA   'aaaaaaaa-0000-0000-0001-000000000001'
\set uRecA 'aaaaaaaa-0000-0000-0001-000000000002'
\set uMedA 'aaaaaaaa-0000-0000-0001-000000000003'
\set uInatA 'aaaaaaaa-0000-0000-0001-000000000004'
\set uMedA2 'aaaaaaaa-0000-0000-0001-000000000005'
\set uB   'bbbbbbbb-0000-0000-0001-000000000001'
\set uMedB 'bbbbbbbb-0000-0000-0001-000000000002'
\set pA   'aaaaaaaa-0000-0000-0002-000000000001'
\set pA2  'aaaaaaaa-0000-0000-0002-000000000002'
\set pB   'bbbbbbbb-0000-0000-0002-000000000001'
\set pE   'eeeeeeee-0000-0000-0002-000000000001'
\set pE2  'eeeeeeee-0000-0000-0002-000000000002'
\set pE3  'eeeeeeee-0000-0000-0002-000000000003'
\set pacA 'aaaaaaaa-0000-0000-0003-000000000001'
\set pacB 'bbbbbbbb-0000-0000-0003-000000000001'
\set pacX 'cccccccc-0000-0000-0003-000000000001'
\set pcA  'aaaaaaaa-0000-0000-0004-000000000001'
\set pcB  'bbbbbbbb-0000-0000-0004-000000000001'
\set eC   'cccccccc-0000-0000-0006-000000000001'
\set eD   'cccccccc-0000-0000-0006-000000000002'
\set E1   'eeeeeeee-0000-0000-0005-000000000001'
\set E2   'eeeeeeee-0000-0000-0005-000000000002'
\set E3   'eeeeeeee-0000-0000-0005-000000000003'
\set E5   'eeeeeeee-0000-0000-0005-000000000005'
\set E6   'eeeeeeee-0000-0000-0005-000000000006'
\set E7   'eeeeeeee-0000-0000-0005-000000000007'
\set E8   'eeeeeeee-0000-0000-0005-000000000008'
\set E9   'eeeeeeee-0000-0000-0005-000000000009'
\set E10  'eeeeeeee-0000-0000-0005-000000000010'
\set L0   'eeeeeeee-0000-0000-0007-000000000000'
\set L1   'eeeeeeee-0000-0000-0007-000000000001'
\set L2   'eeeeeeee-0000-0000-0007-000000000002'
\set L5   'eeeeeeee-0000-0000-0007-000000000005'
\set LX   'eeeeeeee-0000-0000-0007-000000000003'
\set D1   'eeeeeeee-0000-0000-0009-000000000001'
\set anxE1 'eeeeeeee-0000-0000-0008-000000000001'
\set agA1 'aaaaaaaa-0000-0000-000a-000000000001'
\set agE8 'aaaaaaaa-0000-0000-000a-000000000008'
\set agE9 'aaaaaaaa-0000-0000-000a-000000000009'
\set tokE1 '0101010101010101'
\set tokE2 '0202020202020202'
\set tokL0 '0f0f0f0f0f0f0f0f'
\set tokLX '0303030303030303'
\set desD1 '0d0d0d0d0d0d0d0d'

-- =====================================================================
-- PARTE 1: semente (superusuario do cluster descartavel)
-- =====================================================================
\connect - pgtest
SET search_path = saas, public;

INSERT INTO especialidade(id,nome) VALUES (:'eC','Cardiologia'),(:'eD','Dermatologia');
INSERT INTO usuario(id,sub_oidc,nome,email) VALUES
 (:'uA','sub-uA','Admin A','a@a.test'),(:'uRecA','sub-uRecA','Recepcao A','r@a.test'),
 (:'uMedA','sub-uMedA','Medico A','m@a.test'),(:'uInatA','sub-uInatA','Admin Inativo A','i@a.test'),
 (:'uMedA2','sub-uMedA2','Medico A2 sem vinculo profissional','m2@a.test'),
 (:'uB','sub-uB','Admin B','a@b.test'),(:'uMedB','sub-uMedB','Medico B','m@b.test');
INSERT INTO clinica(id,nome,modo_recebimento) VALUES (:'cA','Clinica A','PEDIDO'),(:'cB','Clinica B','PEDIDO');
INSERT INTO clinica_especialidade VALUES (:'cA',:'eC'),(:'cB',:'eC');
INSERT INTO usuario_clinica(usuario_id,clinica_id,papel,ativo) VALUES
 (:'uA',:'cA','ADMIN',true),(:'uRecA',:'cA','RECEPCAO',true),(:'uMedA',:'cA','MEDICO',true),
 (:'uInatA',:'cA','ADMIN',false),(:'uMedA2',:'cA','MEDICO',true),(:'uB',:'cB','ADMIN',true),(:'uMedB',:'cB','MEDICO',true);
-- rede ligada em A, desligada em B (Red Team, item 15)
INSERT INTO flag_clinica(clinica_id,chave,ligada) VALUES (:'cA','f1',true),(:'cB','f1',true),
 (:'cA','REDE_ENCAMINHAMENTO',true),(:'cB','REDE_ENCAMINHAMENTO',false);
INSERT INTO profissional(id,crm,crm_uf,nome,telefone,email,usuario_id,canal_verificado_em) VALUES
 (:'pA','1001','SP','Dr A','11900000001','pa@a.test',:'uMedA',now()),
 (:'pA2','1002','SP','Dr A2','11900000002','pa2@a.test',:'uMedA2',now()),
 (:'pB','2001','RJ','Dr B','21900000001','pb@b.test',:'uMedB',now()),
 (:'pE','3001','MG','Dr Encaminhador','31900000001','pe@x.test',NULL,now()),
 (:'pE2','3002','MG','Dr Encaminhador 2','31900000002','pe2@x.test',NULL,now()),
 (:'pE3','3003','MG','Dr Nao Verificado','31900000003','pe3@x.test',NULL,NULL);
INSERT INTO profissional_especialidade VALUES (:'pA',:'eC'),(:'pB',:'eC');
INSERT INTO profissional_clinica(id,profissional_id,clinica_id,recebe_encaminhamento) VALUES
 (:'pcA',:'pA',:'cA',true),(:'pcB',:'pB',:'cB',true);
INSERT INTO horario_atendimento(clinica_id,profissional_clinica_id,dia_semana,hora_inicio,hora_fim) VALUES
 (:'cA',:'pcA',1,'08:00','12:00'),(:'cB',:'pcB',1,'08:00','12:00');
INSERT INTO paciente(id,nome,telefone,data_nascimento,cpf_cifrado,cpf_hash,cadastrado_por_clinica_id) VALUES
 (:'pacA','Paciente A','11911110001','1980-01-01','\xaa01','\xbb01',:'cA'),
 (:'pacB','Paciente B','21911110002','1981-02-02','\xaa02','\xbb02',:'cB'),
 (:'pacX','Paciente X','31911110003','1982-03-03','\xaa03','\xbb03',NULL);
INSERT INTO paciente_clinica(paciente_id,clinica_id) VALUES (:'pacA',:'cA'),(:'pacB',:'cB');
INSERT INTO encaminhamento(id,profissional_origem_id,paciente_id,especialidade_destino_id,clinica_destino_id,motivo_cifrado,urgencia,expira_em) VALUES
 (:'E1',:'pE',:'pacA',:'eC',:'cA','\xdead01','ROTINA',now()+interval '30 days'),
 (:'E2',:'pE',:'pacB',:'eC',:'cB','\xdead02','ROTINA',now()+interval '30 days'),
 (:'E3',:'pE',:'pacX',:'eC',:'cA','\xdead03','ROTINA',now()+interval '30 days'),
 (:'E5',:'pE',:'pacA',:'eC',:'cA','\xdead05','ROTINA',now()+interval '30 days'),
 (:'E6',:'pE',:'pacX',:'eC',NULL,'\xdead06','ROTINA',now()+interval '30 days'),
 (:'E7',:'pE',:'pacX',:'eC',NULL,'\xdead07','ROTINA',now()-interval '1 day'),
 (:'E8',:'pE',:'pacA',:'eC',:'cA','\xdead08','ROTINA',now()+interval '30 days'),
 (:'E9',:'pE',:'pacA',:'eC',:'cA','\xdead09','ROTINA',now()+interval '30 days'),
 (:'E10',:'pE3',:'pacX',:'eC',NULL,'\xdead10','ROTINA',now()+interval '30 days');
-- Estados de partida fora de CRIADO: o gatilho de transicoes nao deixa nem o superusuario
-- pular estados, entao a fixture usa session_replication_role (so nesta semente).
SET session_replication_role = replica;
UPDATE encaminhamento SET status='CANCELADO' WHERE id=:'E6';
UPDATE encaminhamento SET status='ATENDIDO' WHERE id=:'E8';
UPDATE encaminhamento SET status='AGENDADO' WHERE id=:'E9';
SET session_replication_role = origin;
INSERT INTO consentimento(paciente_id,finalidade,encaminhamento_id,clinica_id,texto_aceito,versao_texto,canal) VALUES
 (:'pacA','COMPARTILHAR_CASO',:'E1',:'cA','texto','v1','SITE'),
 (:'pacB','COMPARTILHAR_CASO',:'E2',:'cB','texto','v1','SITE'),
 (:'pacA','COMPARTILHAR_CASO',:'E5',:'cA','texto','v1','SITE'),
 (:'pacA','COMPARTILHAR_CASO',:'E8',:'cA','texto','v1','SITE'),
 (:'pacA','COMPARTILHAR_CASO',:'E9',:'cA','texto','v1','SITE'),
 (:'pacA','AGENDAMENTO',NULL,:'cA','texto','v1','RECEPCAO'),
 (:'pacB','AGENDAMENTO',NULL,:'cB','texto','v1','RECEPCAO');
-- links: L0 revogado com 9 tentativas (soma por encaminhamento), L1 ativo com codigo 123456
INSERT INTO link_paciente(id,encaminhamento_id,paciente_id,token_hash,expira_em,revogado_em,tentativas_codigo) VALUES
 (:'L0',:'E1',:'pacA',sha256(decode(:'tokL0','hex')),now()+interval '3 days',now(),9);
INSERT INTO link_paciente(id,encaminhamento_id,paciente_id,token_hash,expira_em,codigo_hash,codigo_expira_em) VALUES
 (:'L1',:'E1',:'pacA',sha256(decode(:'tokE1','hex')),now()+interval '3 days',sha256(convert_to(:'L1'||':123456','UTF8')),now()+interval '10 minutes'),
 (:'L2',:'E2',:'pacB',sha256(decode(:'tokE2','hex')),now()+interval '3 days',NULL,NULL),
 (:'LX',:'E3',:'pacX',sha256(decode(:'tokLX','hex')),now()+interval '3 days',NULL,NULL);
-- R2-B: link de E5 ja usado, origem da sessao PAC_A_E5
INSERT INTO link_paciente(id,encaminhamento_id,paciente_id,token_hash,expira_em,usado_em) VALUES
 (:'L5',:'E5',:'pacA',sha256(decode('0505050505050505','hex')),now()+interval '3 days',now());
INSERT INTO desafio_encaminhador(id,profissional_id,desafio_hash,codigo_hash,codigo_expira_em,expira_em) VALUES
 (:'D1',:'pE',sha256(decode(:'desD1','hex')),sha256(convert_to(:'D1'||':654321','UTF8')),now()+interval '10 minutes',now()+interval '15 minutes');
-- sessoes: token em claro = md5('sessao-'||chave); banco guarda sha256 do token
INSERT INTO sessao(token_hash,tipo,usuario_id,expira_em)
 SELECT sha256(decode(md5('sessao-'||k),'hex')),'EQUIPE',u::uuid,now()+interval '1 hour'
   FROM (VALUES ('uA',:'uA'),('uRecA',:'uRecA'),('uMedA',:'uMedA'),('uInatA',:'uInatA'),('uMedA2',:'uMedA2'),('uB',:'uB'),('uMedB',:'uMedB')) v(k,u);
INSERT INTO sessao(token_hash,tipo,profissional_id,expira_em)
 SELECT sha256(decode(md5('sessao-'||k),'hex')),'ENCAMINHADOR',p::uuid,now()+interval '1 hour'
   FROM (VALUES ('pE',:'pE'),('pE2',:'pE2')) v(k,p);
INSERT INTO sessao(token_hash,tipo,paciente_id,link_paciente_id,expira_em)
 SELECT sha256(decode(md5('sessao-'||k),'hex')),'PACIENTE',p::uuid,l::uuid,now()+interval '20 minutes'
   FROM (VALUES ('pacA',:'pacA',:'L1'),('pacB',:'pacB',:'L2'),('pacX',:'pacX',:'LX'),('pacA-E5',:'pacA',:'L5')) v(k,p,l);
INSERT INTO sessao(token_hash,tipo,usuario_id,criada_em,expira_em) VALUES
 (sha256(decode(md5('sessao-uA-exp'),'hex')),'EQUIPE',:'uA',now()-interval '2 hours',now()-interval '1 minute');
INSERT INTO sessao(token_hash,tipo,usuario_id,expira_em,encerrada_em) VALUES
 (sha256(decode(md5('sessao-uA-enc'),'hex')),'EQUIPE',:'uA',now()+interval '1 hour',now());
INSERT INTO vaga_encaminhamento(clinica_id,profissional_clinica_id,inicio,fim) VALUES
 (:'cA',:'pcA',now()+interval '10 days',now()+interval '10 days 30 min'),
 (:'cB',:'pcB',now()+interval '10 days',now()+interval '10 days 30 min');
INSERT INTO agendamento(id,clinica_id,profissional_clinica_id,paciente_id,inicio,fim,origem,chave_idempotencia) VALUES
 (:'agA1',:'cA',:'pcA',:'pacA',now()+interval '5 days',now()+interval '5 days 30 min','RECEPCAO','kA1');
INSERT INTO agendamento(clinica_id,profissional_clinica_id,paciente_id,inicio,fim,origem,chave_idempotencia) VALUES
 (:'cB',:'pcB',:'pacB',now()+interval '5 days',now()+interval '5 days 30 min','RECEPCAO','kB1');
INSERT INTO agendamento(id,clinica_id,profissional_clinica_id,paciente_id,inicio,fim,origem,encaminhamento_id,status,status_alterado_por,chave_idempotencia) VALUES
 (:'agE8',:'cA',:'pcA',:'pacA',now()-interval '2 days',now()-interval '2 days'+interval '30 min','ENCAMINHAMENTO',:'E8','REALIZADO',:'uMedA','kE8'),
 (:'agE9',:'cA',:'pcA',:'pacA',now()-interval '1 day',now()-interval '1 day'+interval '30 min','ENCAMINHAMENTO',:'E9','REALIZADO',:'uMedA','kE9');
-- contrarreferencias de E1 e E2 para a visibilidade da secao b (nao estao ATENDIDO: fixture sem gatilho)
SET session_replication_role = replica;
INSERT INTO contrarreferencia(encaminhamento_id,clinica_id,autor_profissional_id,conduta_cifrada) VALUES
 (:'E1',:'cA',:'pA','\xc0de01'),(:'E2',:'cB',:'pB','\xc0de02');
SET session_replication_role = origin;
INSERT INTO anexo_encaminhamento(id,encaminhamento_id,chave_storage,tipo_mime,tamanho_bytes,sha256,enviado_por_tipo,enviado_por_id) VALUES
 (:'anxE1',:'E1','obj-E1','application/pdf',100,'\x01','PROFISSIONAL',:'pE');
INSERT INTO anexo_encaminhamento(encaminhamento_id,chave_storage,tipo_mime,tamanho_bytes,sha256,enviado_por_tipo,enviado_por_id) VALUES
 (:'E2','obj-E2','application/pdf',100,'\x02','PROFISSIONAL',:'pE');
INSERT INTO evento_auditoria(ator_papel,ator_id,clinica_id,acao,recurso_tipo) VALUES
 ('ADMIN',:'uA',:'cA','LER','X'),('ADMIN',:'uB',:'cB','LER','X'),('SISTEMA',NULL,NULL,'LER','X');

-- Auxiliar de teste (fora do schema do modelo)
CREATE SCHEMA teste_aux;
CREATE TABLE teste_aux.alvos(tab text, dono text, id uuid);
CREATE TABLE teste_aux.snap(tab text PRIMARY KEY, h text);
DO $$
DECLARE t text;
BEGIN
  FOR t IN SELECT unnest(ARRAY['usuario_clinica','flag_clinica','profissional_clinica','horario_atendimento',
        'paciente_clinica','vaga_encaminhamento','agendamento','contrarreferencia','consentimento','evento_auditoria','clinica'])
  LOOP
    EXECUTE format($f$INSERT INTO teste_aux.alvos SELECT %L,
      CASE WHEN %s = 'aaaaaaaa-0000-0000-0000-000000000001'::uuid THEN 'A'
           WHEN %s = 'bbbbbbbb-0000-0000-0000-000000000001'::uuid THEN 'B' ELSE 'N' END, id FROM saas.%I$f$,
      t, CASE WHEN t='clinica' THEN 'id' ELSE 'clinica_id' END, CASE WHEN t='clinica' THEN 'id' ELSE 'clinica_id' END, t);
  END LOOP;
END $$;
INSERT INTO teste_aux.alvos SELECT 'usuario', CASE WHEN id IN (:'uB',:'uMedB') THEN 'B' ELSE 'A' END, id FROM usuario;
INSERT INTO teste_aux.alvos SELECT 'paciente', CASE WHEN id=:'pacB' THEN 'B' WHEN id=:'pacA' THEN 'A' ELSE 'N' END, id FROM paciente;
INSERT INTO teste_aux.alvos SELECT 'encaminhamento', CASE WHEN id=:'E2' THEN 'B' WHEN id IN (:'E1',:'E5',:'E8',:'E9') THEN 'A' ELSE 'N' END, id FROM encaminhamento;
INSERT INTO teste_aux.alvos SELECT 'historico_status_encaminhamento', CASE WHEN encaminhamento_id=:'E2' THEN 'B' WHEN encaminhamento_id IN (:'E1',:'E5',:'E8',:'E9') THEN 'A' ELSE 'N' END, id FROM historico_status_encaminhamento;
INSERT INTO teste_aux.alvos SELECT 'link_paciente', CASE WHEN encaminhamento_id=:'E2' THEN 'B' ELSE 'A' END, id FROM link_paciente;
INSERT INTO teste_aux.alvos SELECT 'anexo_encaminhamento', CASE WHEN encaminhamento_id=:'E2' THEN 'B' ELSE 'A' END, id FROM anexo_encaminhamento;
DO $$
DECLARE t text;
BEGIN
  FOR t IN SELECT tablename FROM pg_tables WHERE schemaname='saas' LOOP
    EXECUTE format('INSERT INTO teste_aux.snap SELECT %L, md5(coalesce(string_agg(x::text, ''|'' ORDER BY x::text),'''')) FROM saas.%I x', t, t);
  END LOOP;
END $$;

CREATE TABLE teste_aux.k(nome text PRIMARY KEY, id text);
INSERT INTO teste_aux.k VALUES
 ('cA',:'cA'),('cB',:'cB'),('uA',:'uA'),('uRecA',:'uRecA'),('uMedA',:'uMedA'),('uInatA',:'uInatA'),('uMedA2',:'uMedA2'),('uB',:'uB'),('uMedB',:'uMedB'),
 ('pA',:'pA'),('pA2',:'pA2'),('pB',:'pB'),('pE',:'pE'),('pE2',:'pE2'),('pE3',:'pE3'),('pacA',:'pacA'),('pacB',:'pacB'),('pacX',:'pacX'),
 ('pcA',:'pcA'),('pcB',:'pcB'),('eC',:'eC'),('eD',:'eD'),('E1',:'E1'),('E2',:'E2'),('E3',:'E3'),('E5',:'E5'),('E6',:'E6'),('E7',:'E7'),
 ('E8',:'E8'),('E9',:'E9'),('E10',:'E10'),('L0',:'L0'),('L1',:'L1'),('D1',:'D1'),('anxE1',:'anxE1'),('agA1',:'agA1'),('agE8',:'agE8'),('agE9',:'agE9'),
 ('tokE1',:'tokE1'),('tokE2',:'tokE2'),('tokL0',:'tokL0'),('desD1',:'desD1'),('morta','dddddddd-0000-0000-0000-00000000dead');
CREATE TABLE teste_aux.res(n serial, secao text, nome text, ctx text, esperado text, obtido text, ok boolean);

-- ctx(nome): GUCs antigas (ignoradas pelo modelo r1) + app.sessao (unica identidade).
-- v = clinica, usuario, papel, profissional, paciente, token_hash_hex, chave_da_sessao
CREATE FUNCTION teste_aux.kid(n text) RETURNS text LANGUAGE sql AS $$ SELECT id FROM teste_aux.k WHERE nome = n $$;
CREATE FUNCTION teste_aux.ctx(c text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE v text[]; k text := 'teste_aux.kid';
BEGIN
  v := CASE c
    WHEN 'ADM_A'  THEN ARRAY[teste_aux.kid('cA'), teste_aux.kid('uA'),    'ADMIN',     '', '', '', 'uA']
    WHEN 'REC_A'  THEN ARRAY[teste_aux.kid('cA'), teste_aux.kid('uRecA'), 'RECEPCAO',  '', '', '', 'uRecA']
    WHEN 'MED_A'  THEN ARRAY[teste_aux.kid('cA'), teste_aux.kid('uMedA'), 'MEDICO',    teste_aux.kid('pA'), '', '', 'uMedA']
    WHEN 'MED_A2' THEN ARRAY[teste_aux.kid('cA'), teste_aux.kid('uMedA2'),'MEDICO',    teste_aux.kid('pA2'), '', '', 'uMedA2']
    WHEN 'ADM_B'  THEN ARRAY[teste_aux.kid('cB'), teste_aux.kid('uB'),    'ADMIN',     '', '', '', 'uB']
    WHEN 'MED_B'  THEN ARRAY[teste_aux.kid('cB'), teste_aux.kid('uMedB'), 'MEDICO',    teste_aux.kid('pB'), '', '', 'uMedB']
    WHEN 'ENC_E'  THEN ARRAY['', '', 'ENCAMINHADOR', teste_aux.kid('pE'),  '', '', 'pE']
    WHEN 'ENC_E2' THEN ARRAY['', '', 'ENCAMINHADOR', teste_aux.kid('pE2'), '', '', 'pE2']
    WHEN 'ENC_E2_CLIN_A' THEN ARRAY[teste_aux.kid('cA'), '', 'ENCAMINHADOR', teste_aux.kid('pE2'), '', '', 'pE2']
    WHEN 'PAC_A'  THEN ARRAY['', '', 'PACIENTE', '', teste_aux.kid('pacA'), '', 'pacA']
    WHEN 'PAC_A_E5' THEN ARRAY['', '', 'PACIENTE', '', teste_aux.kid('pacA'), '', 'pacA-E5']
    WHEN 'PAC_B'  THEN ARRAY['', '', 'PACIENTE', '', teste_aux.kid('pacB'), '', 'pacB']
    WHEN 'PAC_X'  THEN ARRAY['', '', 'PACIENTE', '', teste_aux.kid('pacX'), '', 'pacX']
    WHEN 'LINK_E1' THEN ARRAY['', '', 'PUBLICO_LINK', '', '', teste_aux.kid('tokE1'), '']
    WHEN 'SISTEMA' THEN ARRAY['', '', 'SISTEMA', '', '', '', '']
    WHEN 'VAZIO'  THEN ARRAY['', '', '', '', '', '', '']
    WHEN 'SO_CLINICA_A' THEN ARRAY[teste_aux.kid('cA'), '', '', '', '', '', '']
    WHEN 'SO_PAPEL_ADMIN' THEN ARRAY['', '', 'ADMIN', '', '', '', '']
    WHEN 'USU_SEM_CLINICA' THEN ARRAY['', teste_aux.kid('uA'), 'ADMIN', '', '', '', 'uA']
    WHEN 'CLIN_INEXISTENTE' THEN ARRAY[teste_aux.kid('morta'), teste_aux.kid('uA'), 'ADMIN', '', '', '', 'uA']
    WHEN 'ADM_A_NA_CLIN_B' THEN ARRAY[teste_aux.kid('cB'), teste_aux.kid('uA'), 'ADMIN', '', '', '', 'uA']
    WHEN 'REC_A_FINGE_ADMIN' THEN ARRAY[teste_aux.kid('cA'), teste_aux.kid('uRecA'), 'ADMIN', '', '', '', 'uRecA']
    WHEN 'ADM_A_INATIVO' THEN ARRAY[teste_aux.kid('cA'), teste_aux.kid('uInatA'), 'ADMIN', '', '', '', 'uInatA']
    WHEN 'GUC_LIXO' THEN ARRAY['abc', teste_aux.kid('uA'), 'ADMIN', '', '', '', 'uA']
    -- r1: contextos forjados so com GUC (o que as sondas RT3, RT4 e RT5 faziam)
    WHEN 'ADM_A_SEM_SESSAO' THEN ARRAY[teste_aux.kid('cA'), teste_aux.kid('uA'), 'ADMIN', '', '', '', '']
    WHEN 'PAC_A_SEM_SESSAO' THEN ARRAY['', '', 'PACIENTE', '', teste_aux.kid('pacA'), '', '']
    WHEN 'PAC_B_SEM_SESSAO' THEN ARRAY['', '', 'PACIENTE', '', teste_aux.kid('pacB'), '', '']
    WHEN 'ENC_E_SEM_SESSAO' THEN ARRAY['', '', 'ENCAMINHADOR', teste_aux.kid('pE'), '', '', '']
    WHEN 'ADM_A_SESSAO_EXPIRADA' THEN ARRAY[teste_aux.kid('cA'), teste_aux.kid('uA'), 'ADMIN', '', '', '', 'uA-exp']
    WHEN 'ADM_A_SESSAO_ENCERRADA' THEN ARRAY[teste_aux.kid('cA'), teste_aux.kid('uA'), 'ADMIN', '', '', '', 'uA-enc']
    WHEN 'ADM_A_COM_SESSAO_DE_PACIENTE' THEN ARRAY[teste_aux.kid('cA'), teste_aux.kid('uA'), 'ADMIN', '', '', '', 'pacA']
    WHEN 'MED_A_FINGE_PB' THEN ARRAY[teste_aux.kid('cA'), teste_aux.kid('uMedA'), 'MEDICO', teste_aux.kid('pB'), '', '', 'uMedA']
    WHEN 'ENC_E2_FINGE_PE' THEN ARRAY['', '', 'ENCAMINHADOR', teste_aux.kid('pE'), '', '', 'pE2']
    WHEN 'PAC_A_FINGE_PACB' THEN ARRAY['', '', 'PACIENTE', '', teste_aux.kid('pacB'), '', 'pacA']
    WHEN 'SESSAO_NAO_HEX' THEN ARRAY[teste_aux.kid('cA'), '', 'ADMIN', '', '', '', '#zz']
    ELSE NULL END;
  IF v IS NULL THEN RAISE EXCEPTION 'ctx desconhecido %', c; END IF;
  PERFORM set_config('app.clinica_id', v[1], true), set_config('app.usuario', v[2], true),
          set_config('app.papel', v[3], true), set_config('app.profissional_id', v[4], true),
          set_config('app.paciente_id', v[5], true), set_config('app.link_token_hash', v[6], true),
          set_config('app.sessao', CASE WHEN v[7] = '' THEN '' WHEN v[7] LIKE '#%' THEN substr(v[7],2)
                                        ELSE md5('sessao-' || v[7]) END, true);
END $$;

CREATE FUNCTION teste_aux.sonda(secao text, nome text, c text, esperado text, passos text[], verif text DEFAULT NULL, ctx_verif text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE s text; r text := NULL; n bigint; ok boolean; kk record;
BEGIN
  BEGIN
    IF c <> 'NUNCA' THEN PERFORM teste_aux.ctx(c); END IF;
    FOREACH s IN ARRAY passos LOOP
      FOR kk IN SELECT * FROM teste_aux.k LOOP s := replace(s, '{'||kk.nome||'}', kk.id); END LOOP;
      IF s LIKE 'ctx:%' THEN PERFORM teste_aux.ctx(substr(s,5));
      ELSE EXECUTE s; GET DIAGNOSTICS n = ROW_COUNT; r := n::text; END IF;
    END LOOP;
    IF verif IS NOT NULL THEN
      IF ctx_verif IS NOT NULL THEN PERFORM teste_aux.ctx(ctx_verif); END IF;
      FOR kk IN SELECT * FROM teste_aux.k LOOP verif := replace(verif, '{'||kk.nome||'}', kk.id); END LOOP;
      EXECUTE verif INTO r;
    END IF;
    RAISE EXCEPTION 'desfazer' USING ERRCODE = 'RB001';
  EXCEPTION
    WHEN SQLSTATE 'RB001' THEN NULL;
    WHEN OTHERS THEN r := 'ERRO[' || SQLSTATE || ']: ' || left(SQLERRM, 110);
  END;
  ok := CASE esperado
    WHEN 'ERRO'     THEN r LIKE 'ERRO%'
    WHEN '0'        THEN r = '0'
    WHEN 'NEGADO'   THEN r LIKE 'ERRO%' OR r = '0'
    WHEN 'POSITIVO' THEN r ~ '^[0-9]+$' AND r::bigint > 0
    WHEN 'OK'       THEN r NOT LIKE 'ERRO%'
    WHEN 'INFO'     THEN NULL END;
  INSERT INTO teste_aux.res(secao, nome, ctx, esperado, obtido, ok) VALUES (secao, nome, c, esperado, coalesce(r,'NULL'), coalesce(ok,CASE WHEN esperado='INFO' THEN NULL ELSE false END));
END $$;

-- Fixture: poe o encaminhamento ou o agendamento num estado de partida (pula gatilhos;
-- dono superusuario do cluster descartavel). So prepara pre-condicao; nao e o ataque.
CREATE FUNCTION teste_aux.forca_status(e uuid, s text) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = saas, public AS $$
BEGIN SET LOCAL session_replication_role = replica; UPDATE saas.encaminhamento SET status = s WHERE id = e; SET LOCAL session_replication_role = origin; END $$;
CREATE FUNCTION teste_aux.forca_agendamento(a uuid, s text) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = saas, public AS $$
BEGIN SET LOCAL session_replication_role = replica; UPDATE saas.agendamento SET status = s, atualizado_em = now() WHERE id = a; SET LOCAL session_replication_role = origin; END $$;
-- Leitura de verificacao como dono do cluster (para papeis sem SELECT, ex.: saas_jobs).
CREATE FUNCTION teste_aux.conta(q text) RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path = saas, public AS $$
DECLARE r bigint; BEGIN EXECUTE q INTO r; RETURN r; END $$;

GRANT USAGE ON SCHEMA teste_aux TO saas_app, saas_jobs, saas_auth;
GRANT SELECT ON teste_aux.alvos, teste_aux.k TO saas_app, saas_jobs, saas_auth;
GRANT SELECT, INSERT ON teste_aux.res TO saas_app, saas_jobs, saas_auth;
GRANT USAGE ON SEQUENCE teste_aux.res_n_seq TO saas_app, saas_jobs, saas_auth;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA teste_aux TO saas_app, saas_jobs, saas_auth;

\echo
\echo '===== PARTE 2: testes como saas_app ====='
\connect - saas_app
SET search_path = saas, public;

SELECT current_user AS papel_de_conexao, rolsuper, rolbypassrls,
       (SELECT count(*) FROM pg_tables WHERE tableowner = current_user) AS tabelas_de_propriedade_do_app
  FROM pg_roles WHERE rolname = current_user;
CREATE TEMP TABLE tabs_rls AS SELECT relname::text AS t FROM pg_class
  WHERE relnamespace='saas'::regnamespace AND relkind='r' AND relrowsecurity ORDER BY 1;
SELECT count(*) AS tabelas_com_rls, bool_and(relforcerowsecurity) AS todas_com_force
  FROM pg_class WHERE relnamespace='saas'::regnamespace AND relkind='r' AND relrowsecurity;

\o /dev/null
-- ---------------------------------------------------------------------
-- (c) nega por padrao
-- ---------------------------------------------------------------------
DO $$ DECLARE t text; c text; esp text; BEGIN
  FOREACH c IN ARRAY ARRAY['NUNCA','VAZIO','SO_CLINICA_A','SO_PAPEL_ADMIN','USU_SEM_CLINICA','CLIN_INEXISTENTE'] LOOP
    FOR t IN SELECT tabs_rls.t FROM tabs_rls LOOP
      esp := CASE WHEN has_any_column_privilege('saas.'||t, 'SELECT') THEN '0' ELSE 'ERRO' END;
      IF (c IN ('SO_PAPEL_ADMIN','USU_SEM_CLINICA','CLIN_INEXISTENTE') AND t IN ('profissional','profissional_especialidade'))
         OR (c IN ('USU_SEM_CLINICA','CLIN_INEXISTENTE') AND t IN ('usuario','usuario_clinica')) THEN
        PERFORM teste_aux.sonda('c','ver '||t||' (global/proprio por desenho)',c,'INFO',ARRAY[format('select 1 from saas.%I',t)]);
      ELSE
        PERFORM teste_aux.sonda('c','ver '||t,c,esp,ARRAY[format('select 1 from saas.%I',t)]);
      END IF;
    END LOOP;
    PERFORM teste_aux.sonda('c','inserir agendamento',c,'ERRO',ARRAY[
      'insert into saas.agendamento(clinica_id,profissional_clinica_id,paciente_id,inicio,fim,origem,chave_idempotencia) values (''{cA}'',''{pcA}'',''{pacA}'',now()+interval ''40 days'',now()+interval ''40 days 30 min'',''RECEPCAO'',''c-x'')']);
    PERFORM teste_aux.sonda('c','atualizar agendamento',c,'NEGADO',ARRAY['update saas.agendamento set id=id']);
    PERFORM teste_aux.sonda('c','atualizar encaminhamento',c,'NEGADO',ARRAY['update saas.encaminhamento set urgencia=urgencia']);
  END LOOP;
END $$;
DO $$ DECLARE t text; BEGIN
  FOR t IN SELECT tabs_rls.t FROM tabs_rls LOOP
    PERFORM teste_aux.sonda('c','GUC clinica_id=abc em '||t||CASE WHEN t IN ('profissional','profissional_especialidade') THEN ' (global por desenho)' ELSE '' END,'GUC_LIXO',
      CASE WHEN t IN ('profissional','profissional_especialidade') THEN 'INFO' ELSE 'NEGADO' END,ARRAY[format('select 1 from saas.%I',t)]);
  END LOOP;
END $$;
SELECT teste_aux.sonda('c','especialidade sem RLS e visivel sem contexto (catalogo global)','VAZIO','POSITIVO',ARRAY['select 1 from saas.especialidade']);

-- ---------------------------------------------------------------------
-- controles positivos
-- ---------------------------------------------------------------------
DO $$ DECLARE t text; BEGIN
  FOREACH t IN ARRAY ARRAY['usuario','clinica','usuario_clinica','flag_clinica','profissional_clinica','horario_atendimento',
                           'paciente','paciente_clinica','encaminhamento','historico_status_encaminhamento','consentimento',
                           'vaga_encaminhamento','agendamento','contrarreferencia','anexo_encaminhamento','evento_auditoria','clinica_especialidade'] LOOP
    PERFORM teste_aux.sonda('controle','ADM_A ve linhas de A em '||t,'ADM_A','POSITIVO',ARRAY[format('select 1 from saas.%I',t)]);
  END LOOP;
END $$;
SELECT teste_aux.sonda('controle','REC_A ve agendamento da propria clinica','REC_A','POSITIVO',ARRAY['select 1 from saas.agendamento where clinica_id=''{cA}''']);
SELECT teste_aux.sonda('controle','ADM_A insere agendamento na clinica A','ADM_A','POSITIVO',ARRAY[
  'insert into saas.agendamento(clinica_id,profissional_clinica_id,paciente_id,inicio,fim,origem,chave_idempotencia) values (''{cA}'',''{pcA}'',''{pacA}'',now()+interval ''40 days'',now()+interval ''40 days 30 min'',''RECEPCAO'',''ok-1'')']);
SELECT teste_aux.sonda('controle','ADM_A atualiza agendamento da clinica A','ADM_A','POSITIVO',ARRAY['update saas.agendamento set status=''CONFIRMADO'' where clinica_id=''{cA}'' and status in (''AGENDADO'',''CONFIRMADO'')']);   -- R2-A
SELECT teste_aux.sonda('controle','ADM_B ve a propria clinica B','ADM_B','POSITIVO',ARRAY['select 1 from saas.agendamento where clinica_id=''{cB}''']);

-- ---------------------------------------------------------------------
-- (a) clinica A nao le, lista, atualiza, apaga nem insere em B
-- ---------------------------------------------------------------------
DO $$ DECLARE t text; c text; ids text; esp text; BEGIN
  FOREACH c IN ARRAY ARRAY['ADM_A','REC_A','MED_A'] LOOP
    FOR t IN SELECT x FROM unnest(ARRAY['usuario','clinica','usuario_clinica','flag_clinica','profissional_clinica','horario_atendimento',
         'paciente','paciente_clinica','encaminhamento','historico_status_encaminhamento','consentimento','link_paciente',
         'vaga_encaminhamento','agendamento','contrarreferencia','anexo_encaminhamento','evento_auditoria']) x LOOP
      ids := format('select id from teste_aux.alvos where tab=%L and dono=''B''', t);
      esp := CASE WHEN has_any_column_privilege('saas.'||t, 'SELECT') THEN '0' ELSE 'ERRO' END;
      PERFORM teste_aux.sonda('a','ler por id (B) em '||t,c,esp,ARRAY[format('select 1 from saas.%I where id in (%s)',t,ids)]);
      PERFORM teste_aux.sonda('a','listar tudo e cruzar com B em '||t,c,esp,ARRAY['select 1'],
        format('select count(*) from (select id from saas.%I) s join teste_aux.alvos a on a.id=s.id and a.tab=%L and a.dono=''B''',t,t));
      PERFORM teste_aux.sonda('a','atualizar (B) em '||t,c,'NEGADO',ARRAY[
        format('update saas.%I set %s where id in (%s)',t, CASE WHEN t='consentimento' THEN 'revogado_em=revogado_em' ELSE 'id=id' END, ids)]);
      PERFORM teste_aux.sonda('a','apagar (B) em '||t,c,'NEGADO',ARRAY[format('delete from saas.%I where id in (%s)',t,ids)]);
    END LOOP;
    PERFORM teste_aux.sonda('a','ler clinica_especialidade de B',c,'0',ARRAY['select 1 from saas.clinica_especialidade where clinica_id=''{cB}''']);
    PERFORM teste_aux.sonda('a','atualizar clinica_especialidade de B',c,'NEGADO',ARRAY['update saas.clinica_especialidade set clinica_id=clinica_id where clinica_id=''{cB}''']);
    PERFORM teste_aux.sonda('a','apagar clinica_especialidade de B',c,'NEGADO',ARRAY['delete from saas.clinica_especialidade where clinica_id=''{cB}''']);
  END LOOP;
END $$;
DO $$ DECLARE c text; BEGIN
  FOREACH c IN ARRAY ARRAY['ADM_A','REC_A','MED_A'] LOOP
    PERFORM teste_aux.sonda('a','inserir clinica_especialidade(B)',c,'ERRO',ARRAY['insert into saas.clinica_especialidade values (''{cB}'',''{eD}'')']);
    PERFORM teste_aux.sonda('a','inserir usuario_clinica(B) (auto-promocao)',c,'ERRO',ARRAY['insert into saas.usuario_clinica(usuario_id,clinica_id,papel) values (''{uA}'',''{cB}'',''ADMIN'')']);
    PERFORM teste_aux.sonda('a','inserir flag_clinica(B)',c,'ERRO',ARRAY['insert into saas.flag_clinica(clinica_id,chave,ligada) values (''{cB}'',''novo'',true)']);
    PERFORM teste_aux.sonda('a','inserir profissional_clinica(B)',c,'ERRO',ARRAY['insert into saas.profissional_clinica(profissional_id,clinica_id) values (''{pA}'',''{cB}'')']);
    PERFORM teste_aux.sonda('a','inserir horario_atendimento(B)',c,'ERRO',ARRAY['insert into saas.horario_atendimento(clinica_id,profissional_clinica_id,dia_semana,hora_inicio,hora_fim) values (''{cB}'',''{pcB}'',2,''08:00'',''09:00'')']);
    PERFORM teste_aux.sonda('a','inserir paciente_clinica(B)',c,'ERRO',ARRAY['insert into saas.paciente_clinica(paciente_id,clinica_id) values (''{pacA}'',''{cB}'')']);
    PERFORM teste_aux.sonda('a','inserir vaga_encaminhamento(B)',c,'ERRO',ARRAY['insert into saas.vaga_encaminhamento(clinica_id,profissional_clinica_id,inicio,fim) values (''{cB}'',''{pcB}'',now()+interval ''50 days'',now()+interval ''50 days 30 min'')']);
    PERFORM teste_aux.sonda('a','inserir agendamento(B)',c,'ERRO',ARRAY['insert into saas.agendamento(clinica_id,profissional_clinica_id,paciente_id,inicio,fim,origem,chave_idempotencia) values (''{cB}'',''{pcB}'',''{pacB}'',now()+interval ''50 days'',now()+interval ''50 days 30 min'',''RECEPCAO'',''x-b'')']);
    PERFORM teste_aux.sonda('a','inserir consentimento(B, RECEPCAO)',c,'ERRO',ARRAY['insert into saas.consentimento(paciente_id,finalidade,clinica_id,texto_aceito,versao_texto,canal) values (''{pacB}'',''AGENDAMENTO'',''{cB}'',''t'',''v1'',''RECEPCAO'')']);
    PERFORM teste_aux.sonda('a','inserir contrarreferencia(B)',c,'ERRO',ARRAY['insert into saas.contrarreferencia(encaminhamento_id,clinica_id,autor_profissional_id,conduta_cifrada) values (''{E2}'',''{cB}'',''{pA}'',''\xff'')']);
    PERFORM teste_aux.sonda('a','inserir evento_auditoria(clinica B)',c,'ERRO',ARRAY['insert into saas.evento_auditoria(ator_papel,clinica_id,acao,recurso_tipo) values (''ADMIN'',''{cB}'',''X'',''X'')']);
    PERFORM teste_aux.sonda('a','inserir link_paciente para encaminhamento de B',c,'ERRO',ARRAY['insert into saas.link_paciente(encaminhamento_id,paciente_id,token_hash,expira_em) values (''{E2}'',''{pacB}'',''\x99'',now()+interval ''1 day'')']);
    PERFORM teste_aux.sonda('a','inserir anexo em encaminhamento de B',c,'ERRO',ARRAY['insert into saas.anexo_encaminhamento(encaminhamento_id,chave_storage,tipo_mime,tamanho_bytes,sha256,enviado_por_tipo,enviado_por_id) values (''{E2}'',''obj-x'',''application/pdf'',1,''\x01'',''PROFISSIONAL'',''{pA}'')']);
    PERFORM teste_aux.sonda('a','inserir historico em encaminhamento de B',c,'ERRO',ARRAY['insert into saas.historico_status_encaminhamento(encaminhamento_id,status_anterior,status_novo,autor_papel) values (''{E2}'',''CRIADO'',''ATENDIDO'',''ADMIN'')']);
  END LOOP;
END $$;
-- [r1] controle: vinculo de paciente so pela funcao de cadastro (insert direto ganhou sonda propria em r1)
SELECT teste_aux.sonda('controle','ADM_A cadastra paciente na clinica A (paciente_cadastra_na_clinica)','ADM_A','POSITIVO',
  ARRAY['select saas.paciente_cadastra_na_clinica(''Novo'',''11977770000'',NULL,NULL,''\xee01'')'],
  'select count(*) from saas.paciente_clinica where clinica_id=''{cA}''');
SELECT teste_aux.sonda('controle','ADM_A insere evento_auditoria(clinica A)','ADM_A','POSITIVO',ARRAY['insert into saas.evento_auditoria(ator_papel,clinica_id,acao,recurso_tipo) values (''ADMIN'',''{cA}'',''X'',''X'')']);
SELECT teste_aux.sonda('controle','ADM_A insere clinica_especialidade(A)','ADM_A','POSITIVO',ARRAY['insert into saas.clinica_especialidade values (''{cA}'',''{eD}'')']);
SELECT teste_aux.sonda('a','saas_app: SET ROLE saas_owner','NUNCA','ERRO',ARRAY['set local role saas_owner']);
SELECT teste_aux.sonda('a','saas_app: DISABLE ROW LEVEL SECURITY','NUNCA','ERRO',ARRAY['alter table saas.agendamento disable row level security']);
SELECT teste_aux.sonda('a','saas_app: NO FORCE ROW LEVEL SECURITY','NUNCA','ERRO',ARRAY['alter table saas.agendamento no force row level security']);
SELECT teste_aux.sonda('a','saas_app: criar politica permissiva','NUNCA','ERRO',ARRAY['create policy p_vaza on saas.agendamento for select using (true)']);
SELECT teste_aux.sonda('a','saas_app: session_replication_role=replica (pula gatilhos)','NUNCA','ERRO',ARRAY['set local session_replication_role = replica']);
SELECT teste_aux.sonda('a','saas_app: TRUNCATE agendamento','ADM_A','ERRO',ARRAY['truncate saas.agendamento']);

-- ---------------------------------------------------------------------
-- (b) visibilidade do encaminhamento: origem, clinica destino (com consentimento), paciente
-- ---------------------------------------------------------------------
DO $$ DECLARE c text; vis boolean; BEGIN
  FOREACH c IN ARRAY ARRAY['ENC_E','ADM_A','REC_A','MED_A','PAC_A','ADM_B','MED_B','ENC_E2','ENC_E2_CLIN_A','PAC_B','PAC_X','LINK_E1','SISTEMA','ADM_A_NA_CLIN_B','REC_A_FINGE_ADMIN','ADM_A_INATIVO','CLIN_INEXISTENTE','VAZIO',
                           'ADM_A_SEM_SESSAO','PAC_A_SEM_SESSAO','ENC_E_SEM_SESSAO','ADM_A_SESSAO_EXPIRADA','ADM_A_SESSAO_ENCERRADA','ADM_A_COM_SESSAO_DE_PACIENTE','ENC_E2_FINGE_PE','PAC_A_FINGE_PACB'] LOOP
    -- PAC_A_FINGE_PACB e ADM_A_COM_SESSAO_DE_PACIENTE apresentam a sessao de pacA: veem E1 por serem pacA, nada alem
    vis := c IN ('ENC_E','ADM_A','REC_A','MED_A','PAC_A','PAC_A_FINGE_PACB','ADM_A_COM_SESSAO_DE_PACIENTE');
    PERFORM teste_aux.sonda('b','E1 '||CASE WHEN vis THEN 'visivel' ELSE 'invisivel' END,c,CASE WHEN vis THEN 'POSITIVO' ELSE '0' END,
      ARRAY['select 1 from saas.encaminhamento where id=''{E1}''']);
    PERFORM teste_aux.sonda('b','historico de E1 '||CASE WHEN vis THEN 'visivel' ELSE 'invisivel' END,c,CASE WHEN vis THEN 'POSITIVO' ELSE '0' END,
      ARRAY['select 1 from saas.historico_status_encaminhamento where encaminhamento_id=''{E1}''']);
    PERFORM teste_aux.sonda('b','anexo de E1 '||CASE WHEN vis THEN 'visivel' ELSE 'invisivel' END,c,CASE WHEN vis THEN 'POSITIVO' ELSE '0' END,
      ARRAY['select 1 from saas.anexo_encaminhamento where encaminhamento_id=''{E1}''']);
    PERFORM teste_aux.sonda('b','contrarreferencia de E1 '||CASE WHEN vis THEN 'visivel' ELSE 'invisivel' END,c,CASE WHEN vis THEN 'POSITIVO' ELSE '0' END,
      ARRAY['select 1 from saas.contrarreferencia where encaminhamento_id=''{E1}''']);
    PERFORM teste_aux.sonda('b','motivo_cifrado de E1 '||CASE WHEN vis THEN 'legivel' ELSE 'ilegivel' END,c,CASE WHEN vis THEN 'POSITIVO' ELSE '0' END,
      ARRAY['select motivo_cifrado from saas.encaminhamento where id=''{E1}''']);
    PERFORM teste_aux.sonda('b','atualizar E1',c,CASE WHEN vis THEN 'INFO' ELSE 'NEGADO' END, ARRAY['update saas.encaminhamento set urgencia=''URGENTE'' where id=''{E1}''']);
  END LOOP;
  FOREACH c IN ARRAY ARRAY['ENC_E','PAC_X','ADM_A','REC_A','MED_A','ADM_B','PAC_A','PAC_B','ENC_E2','SISTEMA'] LOOP
    vis := c IN ('ENC_E','PAC_X');
    PERFORM teste_aux.sonda('b','E3 (destino A sem consentimento) '||CASE WHEN vis THEN 'visivel' ELSE 'invisivel' END,c,CASE WHEN vis THEN 'POSITIVO' ELSE '0' END,
      ARRAY['select 1 from saas.encaminhamento where id=''{E3}''']);
  END LOOP;
  FOREACH c IN ARRAY ARRAY['ENC_E','ADM_B','MED_B','PAC_B','ADM_A','REC_A','MED_A','PAC_A','PAC_X','ENC_E2'] LOOP
    vis := c IN ('ENC_E','ADM_B','MED_B','PAC_B');
    PERFORM teste_aux.sonda('b','E2 '||CASE WHEN vis THEN 'visivel' ELSE 'invisivel' END,c,CASE WHEN vis THEN 'POSITIVO' ELSE '0' END,
      ARRAY['select 1 from saas.encaminhamento where id=''{E2}''']);
  END LOOP;
  PERFORM teste_aux.sonda('b','paciente pacA visivel a A (vinculo)','ADM_A','POSITIVO',ARRAY['select 1 from saas.paciente where id=''{pacA}''']);
  PERFORM teste_aux.sonda('b','paciente pacB invisivel a A','ADM_A','0',ARRAY['select 1 from saas.paciente where id=''{pacB}''']);
  PERFORM teste_aux.sonda('b','paciente pacA invisivel a B','ADM_B','0',ARRAY['select 1 from saas.paciente where id=''{pacA}''']);
  PERFORM teste_aux.sonda('b','paciente pacX invisivel a A (E3 sem consentimento)','ADM_A','0',ARRAY['select 1 from saas.paciente where id=''{pacX}''']);
  PERFORM teste_aux.sonda('b','paciente pacA invisivel a PAC_B','PAC_B','0',ARRAY['select 1 from saas.paciente where id=''{pacA}''']);
  PERFORM teste_aux.sonda('b','pacA visivel ao encaminhador origem (via E1)','ENC_E','POSITIVO',ARRAY['select 1 from saas.paciente where id=''{pacA}''']);
  PERFORM teste_aux.sonda('b','pacA invisivel a outro encaminhador','ENC_E2','0',ARRAY['select 1 from saas.paciente where id=''{pacA}''']);
  -- link publico: so pela funcao, so o proprio token [r1: tabela sem privilegio -> ERRO]
  PERFORM teste_aux.sonda('b','link publico ve so o proprio link (link_consulta)','LINK_E1','POSITIVO',ARRAY['select 1 from saas.link_consulta(''{tokE1}'')']);
  PERFORM teste_aux.sonda('b','link publico nao le a tabela link_paciente (nem E2)','LINK_E1','ERRO',ARRAY['select 1 from saas.link_paciente where encaminhamento_id=''{E2}''']);
  PERFORM teste_aux.sonda('b','link publico nao ve encaminhamento','LINK_E1','0',ARRAY['select 1 from saas.encaminhamento']);
  -- [r1] papel web declarando SISTEMA nao ve nada (positivo de T8 foi para a secao jobs)
  PERFORM teste_aux.sonda('b','saas_app declarando SISTEMA nao ve expirados (E7)','SISTEMA','0',ARRAY['select 1 from saas.encaminhamento where id=''{E7}''']);
  PERFORM teste_aux.sonda('b','SISTEMA nao ve nao-expirados (E1)','SISTEMA','0',ARRAY['select 1 from saas.encaminhamento where id in (''{E1}'',''{E2}'',''{E3}'',''{E5}'')']);
END $$;
SELECT teste_aux.sonda('b','antes de revogar: A ve E5','ADM_A','POSITIVO',ARRAY['select 1 from saas.encaminhamento where id=''{E5}''']);
-- R2-B
SELECT teste_aux.sonda('b','[r2 I-19] sessao do caso E1 tenta revogar consentimento de E5; A continua vendo E5','PAC_A','POSITIVO',
  ARRAY['update saas.consentimento set revogado_em=now() where encaminhamento_id=''{E5}'' and finalidade=''COMPARTILHAR_CASO''','ctx:ADM_A'],
  'select count(*) from saas.encaminhamento where id=''{E5}''');
SELECT teste_aux.sonda('b','paciente (sessao do caso E5) revoga consentimento de E5; A deixa de ver E5','PAC_A_E5','0',
  ARRAY['update saas.consentimento set revogado_em=now() where encaminhamento_id=''{E5}'' and finalidade=''COMPARTILHAR_CASO''','ctx:ADM_A'],
  'select count(*) from saas.encaminhamento where id=''{E5}''');
SELECT teste_aux.sonda('b','outro encaminhador nao emite link para E1','ENC_E2','ERRO',ARRAY['insert into saas.link_paciente(encaminhamento_id,paciente_id,token_hash,expira_em) values (''{E1}'',''{pacA}'',''\x77'',now()+interval ''1 day'')']);
SELECT teste_aux.sonda('b','outro encaminhador nao anexa em E1','ENC_E2','ERRO',ARRAY['insert into saas.anexo_encaminhamento(encaminhamento_id,chave_storage,tipo_mime,tamanho_bytes,sha256,enviado_por_tipo,enviado_por_id) values (''{E1}'',''obj-y'',''application/pdf'',1,''\x01'',''PROFISSIONAL'',''{pE2}'')']);
SELECT teste_aux.sonda('b','PAC_B nao anexa em E1','PAC_B','ERRO',ARRAY['insert into saas.anexo_encaminhamento(encaminhamento_id,chave_storage,tipo_mime,tamanho_bytes,sha256,enviado_por_tipo,enviado_por_id) values (''{E1}'',''obj-z'',''application/pdf'',1,''\x01'',''PACIENTE'',''{pacB}'')']);
SELECT teste_aux.sonda('b','MED_B nao grava contrarreferencia de E1','MED_B','ERRO',ARRAY['insert into saas.contrarreferencia(encaminhamento_id,clinica_id,autor_profissional_id,conduta_cifrada) values (''{E1}'',''{cB}'',''{pB}'',''\xff'')']);
SELECT teste_aux.sonda('b','MED_A nao grava contrarreferencia de E2 (destino B)','MED_A','ERRO',ARRAY['insert into saas.contrarreferencia(encaminhamento_id,clinica_id,autor_profissional_id,conduta_cifrada) values (''{E2}'',''{cA}'',''{pA}'',''\xff'')']);
-- [r1] controle de contrarreferencia passou para E8 (ATENDIDO, agendamento REALIZADO do proprio medico; T-17)
SELECT teste_aux.sonda('b','controle: MED_A grava contrarreferencia de E8 (destino A, ATENDIDO)','MED_A','POSITIVO',ARRAY['insert into saas.contrarreferencia(encaminhamento_id,clinica_id,autor_profissional_id,conduta_cifrada) values (''{E8}'',''{cA}'',''{pA}'',''\xff'')']);
SELECT teste_aux.sonda('b','terceiro nao atualiza E1 (PAC_B)','PAC_B','NEGADO',ARRAY['update saas.encaminhamento set urgencia=''URGENTE'' where id=''{E1}''']);
SELECT teste_aux.sonda('b','terceiro nao atualiza E1 (ADM_B)','ADM_B','NEGADO',ARRAY['update saas.encaminhamento set urgencia=''URGENTE'' where id=''{E1}''']);
SELECT teste_aux.sonda('b','terceiro nao atualiza E1 (ENC_E2)','ENC_E2','NEGADO',ARRAY['update saas.encaminhamento set urgencia=''URGENTE'' where id=''{E1}''']);
SELECT teste_aux.sonda('b','terceiro nao apaga E1 (todos os papeis)','ADM_A','NEGADO',ARRAY['delete from saas.encaminhamento where id=''{E1}''']);

-- ---------------------------------------------------------------------
-- (e) auditoria e historico so de inclusao
-- ---------------------------------------------------------------------
DO $$ DECLARE c text; t text; BEGIN
  FOREACH c IN ARRAY ARRAY['ADM_A','ADM_B','SISTEMA','ENC_E','PAC_A'] LOOP
    FOREACH t IN ARRAY ARRAY['evento_auditoria','historico_status_encaminhamento'] LOOP
      PERFORM teste_aux.sonda('e','UPDATE em '||t,c,'NEGADO',ARRAY[format('update saas.%I set id=id',t)]);
      PERFORM teste_aux.sonda('e','DELETE em '||t,c,'NEGADO',ARRAY[format('delete from saas.%I',t)]);
      PERFORM teste_aux.sonda('e','TRUNCATE em '||t,c,'ERRO',ARRAY[format('truncate saas.%I',t)]);
    END LOOP;
  END LOOP;
  PERFORM teste_aux.sonda('e','UPDATE auditoria da propria clinica: permission denied','ADM_A','ERRO',ARRAY['update saas.evento_auditoria set acao=''APAGADO'' where clinica_id=''{cA}''']);
  PERFORM teste_aux.sonda('e','DELETE auditoria da propria clinica: permission denied','ADM_A','ERRO',ARRAY['delete from saas.evento_auditoria where clinica_id=''{cA}''']);
  PERFORM teste_aux.sonda('e','controle: INSERT em auditoria funciona','ADM_A','POSITIVO',ARRAY['insert into saas.evento_auditoria(ator_papel,clinica_id,acao,recurso_tipo) values (''ADMIN'',''{cA}'',''X'',''X'')']);
END $$;

-- ---------------------------------------------------------------------
-- (f) bordas
-- ---------------------------------------------------------------------
SELECT teste_aux.sonda('f','clinica_id NULL em agendamento','ADM_A','ERRO',ARRAY['insert into saas.agendamento(clinica_id,profissional_clinica_id,paciente_id,inicio,fim,origem,chave_idempotencia) values (NULL,''{pcA}'',''{pacA}'',now()+interval ''60 days'',now()+interval ''60 days 30 min'',''RECEPCAO'',''n1'')']);
SELECT teste_aux.sonda('f','clinica_id NULL em horario_atendimento','ADM_A','ERRO',ARRAY['insert into saas.horario_atendimento(clinica_id,profissional_clinica_id,dia_semana,hora_inicio,hora_fim) values (NULL,''{pcA}'',2,''08:00'',''09:00'')']);
SELECT teste_aux.sonda('f','clinica_id NULL em paciente_clinica','ADM_A','ERRO',ARRAY['insert into saas.paciente_clinica(paciente_id,clinica_id) values (''{pacX}'',NULL)']);
SELECT teste_aux.sonda('f','clinica_id NULL em vaga_encaminhamento','ADM_A','ERRO',ARRAY['insert into saas.vaga_encaminhamento(clinica_id,profissional_clinica_id,inicio,fim) values (NULL,''{pcA}'',now()+interval ''60 days'',now()+interval ''61 days'')']);
SELECT teste_aux.sonda('f','clinica_id NULL em profissional_clinica','ADM_A','ERRO',ARRAY['insert into saas.profissional_clinica(profissional_id,clinica_id) values (''{pE}'',NULL)']);
SELECT teste_aux.sonda('f','clinica_id NULL em consentimento (COMPARTILHAR_CASO exige)','PAC_A','ERRO',ARRAY['insert into saas.consentimento(paciente_id,finalidade,encaminhamento_id,clinica_id,texto_aceito,versao_texto,canal) values (''{pacA}'',''COMPARTILHAR_CASO'',''{E1}'',NULL,''t'',''v1'',''SITE'')']);
SELECT teste_aux.sonda('f','clinica_id NULL em evento_auditoria (permitido por desenho)','ADM_A','INFO',ARRAY['insert into saas.evento_auditoria(ator_papel,clinica_id,acao,recurso_tipo) values (''ADMIN'',NULL,''X'',''X'')']);
SELECT teste_aux.sonda('f','UUID inexistente como clinica_id: nada visivel','CLIN_INEXISTENTE','0',ARRAY['select 1 from saas.agendamento']);
SELECT teste_aux.sonda('f','UUID inexistente: insert em agendamento (clinica_id inexistente)','CLIN_INEXISTENTE','ERRO',ARRAY['insert into saas.agendamento(clinica_id,profissional_clinica_id,paciente_id,inicio,fim,origem,chave_idempotencia) values (''{morta}'',''{pcA}'',''{pacA}'',now()+interval ''60 days'',now()+interval ''60 days 30 min'',''RECEPCAO'',''m1'')']);
SELECT teste_aux.sonda('f','UUID inexistente no contexto, insert com clinica A','CLIN_INEXISTENTE','ERRO',ARRAY['insert into saas.agendamento(clinica_id,profissional_clinica_id,paciente_id,inicio,fim,origem,chave_idempotencia) values (''{cA}'',''{pcA}'',''{pacA}'',now()+interval ''60 days'',now()+interval ''60 days 30 min'',''RECEPCAO'',''m2'')']);
SELECT teste_aux.sonda('f','ctx forjado: usuario de A com clinica_id de B nao ve B','ADM_A_NA_CLIN_B','0',ARRAY['select 1 from saas.agendamento']);
SELECT teste_aux.sonda('f','ctx forjado: usuario de A com clinica_id de B nao insere em B','ADM_A_NA_CLIN_B','ERRO',ARRAY['insert into saas.agendamento(clinica_id,profissional_clinica_id,paciente_id,inicio,fim,origem,chave_idempotencia) values (''{cB}'',''{pcB}'',''{pacB}'',now()+interval ''60 days'',now()+interval ''60 days 30 min'',''RECEPCAO'',''f1'')']);
SELECT teste_aux.sonda('f','recepcao fingindo papel ADMIN (usuario_clinica manda no papel)','REC_A_FINGE_ADMIN','0',ARRAY['select 1 from saas.agendamento']);
SELECT teste_aux.sonda('f','usuario inativo na clinica nao ve nada','ADM_A_INATIVO','0',ARRAY['select 1 from saas.agendamento']);
DO $$ DECLARE c text; BEGIN
  FOREACH c IN ARRAY ARRAY['ADM_A','REC_A','MED_A'] LOOP
    PERFORM teste_aux.sonda('f','UPDATE agendamento SET clinica_id=B (mover linha)',c,'NEGADO',ARRAY['update saas.agendamento set clinica_id=''{cB}'' where clinica_id=''{cA}''']);
    PERFORM teste_aux.sonda('f','UPDATE profissional_clinica SET clinica_id=B',c,'NEGADO',ARRAY['update saas.profissional_clinica set clinica_id=''{cB}'' where clinica_id=''{cA}''']);
    PERFORM teste_aux.sonda('f','UPDATE horario_atendimento SET clinica_id=B',c,'NEGADO',ARRAY['update saas.horario_atendimento set clinica_id=''{cB}'' where clinica_id=''{cA}''']);
    PERFORM teste_aux.sonda('f','UPDATE paciente_clinica SET clinica_id=B',c,'NEGADO',ARRAY['update saas.paciente_clinica set clinica_id=''{cB}'' where clinica_id=''{cA}''']);
    PERFORM teste_aux.sonda('f','UPDATE vaga_encaminhamento SET clinica_id=B',c,'NEGADO',ARRAY['update saas.vaga_encaminhamento set clinica_id=''{cB}'' where clinica_id=''{cA}''']);
    PERFORM teste_aux.sonda('f','UPDATE usuario_clinica SET clinica_id=B',c,'NEGADO',ARRAY['update saas.usuario_clinica set clinica_id=''{cB}'' where clinica_id=''{cA}''']);
    PERFORM teste_aux.sonda('f','UPDATE flag_clinica SET clinica_id=B',c,'NEGADO',ARRAY['update saas.flag_clinica set clinica_id=''{cB}'' where clinica_id=''{cA}''']);
    PERFORM teste_aux.sonda('f','UPDATE clinica SET id=B',c,'NEGADO',ARRAY['update saas.clinica set id=''{cB}'' where id=''{cA}''']);
    PERFORM teste_aux.sonda('f','UPDATE clinica B (nome)',c,'NEGADO',ARRAY['update saas.clinica set nome=''pwn'' where id=''{cB}''']);
  END LOOP;
  PERFORM teste_aux.sonda('f','UPDATE consentimento SET clinica_id (sem privilegio de coluna)','PAC_A','ERRO',ARRAY['update saas.consentimento set clinica_id=''{cB}'' where paciente_id=''{pacA}''']);
END $$;
SELECT teste_aux.sonda('f','FK composta: agendamento(clinica A) -> profissional_clinica de B','ADM_A','ERRO',ARRAY['insert into saas.agendamento(clinica_id,profissional_clinica_id,paciente_id,inicio,fim,origem,chave_idempotencia) values (''{cA}'',''{pcB}'',''{pacA}'',now()+interval ''60 days'',now()+interval ''60 days 30 min'',''RECEPCAO'',''fk1'')']);
SELECT teste_aux.sonda('f','FK composta: horario(clinica A) -> profissional_clinica de B','ADM_A','ERRO',ARRAY['insert into saas.horario_atendimento(clinica_id,profissional_clinica_id,dia_semana,hora_inicio,hora_fim) values (''{cA}'',''{pcB}'',2,''08:00'',''09:00'')']);
SELECT teste_aux.sonda('f','FK composta: vaga(clinica A) -> profissional_clinica de B','ADM_A','ERRO',ARRAY['insert into saas.vaga_encaminhamento(clinica_id,profissional_clinica_id,inicio,fim) values (''{cA}'',''{pcB}'',now()+interval ''60 days'',now()+interval ''61 days'')']);
SELECT teste_aux.sonda('f','FK composta: UPDATE agendamento aponta profissional_clinica de B','ADM_A','NEGADO',ARRAY['update saas.agendamento set profissional_clinica_id=''{pcB}'' where clinica_id=''{cA}''']);
SELECT teste_aux.sonda('f','FK simples: agendamento(A) -> paciente_id de paciente so de B','ADM_A','ERRO',ARRAY['insert into saas.agendamento(clinica_id,profissional_clinica_id,paciente_id,inicio,fim,origem,chave_idempotencia) values (''{cA}'',''{pcA}'',''{pacB}'',now()+interval ''60 days'',now()+interval ''60 days 30 min'',''RECEPCAO'',''fk2'')']);
SELECT teste_aux.sonda('f','FK simples: oraculo de existencia (UUID inexistente x existente em outro tenant)','ADM_A','INFO',ARRAY['insert into saas.agendamento(clinica_id,profissional_clinica_id,paciente_id,inicio,fim,origem,chave_idempotencia) values (''{cA}'',''{pcA}'',''{morta}'',now()+interval ''60 days'',now()+interval ''60 days 30 min'',''RECEPCAO'',''fk3'')']);
SELECT teste_aux.sonda('f','FK simples: agendamento(A) origem ENCAMINHAMENTO apontando E2 (de B)','ADM_A','ERRO',ARRAY['insert into saas.agendamento(clinica_id,profissional_clinica_id,paciente_id,inicio,fim,origem,encaminhamento_id,chave_idempotencia) values (''{cA}'',''{pcA}'',''{pacA}'',now()+interval ''60 days'',now()+interval ''60 days 30 min'',''ENCAMINHAMENTO'',''{E2}'',''fk4'')']);
SELECT teste_aux.sonda('f','paciente_clinica(A, pacB) por UUID: A passa a ler dados de pacB? [r1: NEGADO]','REC_A','NEGADO',
  ARRAY['insert into saas.paciente_clinica(paciente_id,clinica_id) values (''{pacB}'',''{cA}'')'],
  'select count(*) from saas.paciente where id=''{pacB}''');
SELECT teste_aux.sonda('f','encaminhamento criado com paciente_id de B por UUID: origem passa a ler pacB? [r1: NEGADO]','ENC_E2','NEGADO',
  ARRAY['insert into saas.encaminhamento(profissional_origem_id,paciente_id,especialidade_destino_id,motivo_cifrado,urgencia,expira_em) values (''{pE2}'',''{pacB}'',''{eC}'',''\x00'',''ROTINA'',now()+interval ''1 day'')'],
  'select count(*) from saas.paciente where id=''{pacB}''');
SELECT teste_aux.sonda('f','mesmo vazamento por MEDICO da clinica A [r1: NEGADO]','MED_A','NEGADO',
  ARRAY['insert into saas.encaminhamento(profissional_origem_id,paciente_id,especialidade_destino_id,motivo_cifrado,urgencia,expira_em) values (''{pA}'',''{pacB}'',''{eC}'',''\x00'',''ROTINA'',now()+interval ''1 day'')'],
  'select count(*) from saas.paciente where id=''{pacB}''');
SELECT teste_aux.sonda('f','UPDATE E1.paciente_id := pacB pela origem: E1 passa a apontar pacB? [r1: NEGADO]','ENC_E','NEGADO',
  ARRAY['update saas.encaminhamento set paciente_id=''{pacB}'' where id=''{E1}'''],
  'select count(*) from saas.encaminhamento where id=''{E1}'' and paciente_id=''{pacB}''');
SELECT teste_aux.sonda('f','consentimento forjado por PAC_A para E3 (de pacX): A passa a ver E3? [r1: NEGADO]','PAC_A','NEGADO',
  ARRAY['insert into saas.consentimento(paciente_id,finalidade,encaminhamento_id,clinica_id,texto_aceito,versao_texto,canal) values (''{pacA}'',''COMPARTILHAR_CASO'',''{E3}'',''{cA}'',''t'',''v1'',''SITE'')','ctx:ADM_A'],
  'select count(*) from saas.encaminhamento where id=''{E3}''');
SELECT teste_aux.sonda('f','consentimento forjado por PAC_B para E1 (de pacA) em nome da clinica B: B passa a ver E1? [r1: NEGADO]','PAC_B','NEGADO',
  ARRAY['insert into saas.consentimento(paciente_id,finalidade,encaminhamento_id,clinica_id,texto_aceito,versao_texto,canal) values (''{pacB}'',''COMPARTILHAR_CASO'',''{E1}'',''{cB}'',''t'',''v1'',''SITE'')','ctx:ADM_B'],
  'select count(*) from saas.encaminhamento where id=''{E1}''');
SELECT teste_aux.sonda('f','historico forjado: PAC_A insere linha de historico em E1 (autor/papel livres)','PAC_A','ERRO',
  ARRAY['insert into saas.historico_status_encaminhamento(encaminhamento_id,status_anterior,status_novo,transicao,ator_tecnico,ator_tipo,ator_papel,ator_id) values (''{E1}'',''AGENDADO'',''ATENDIDO'',''T5'',''saas_app'',''EQUIPE'',''MEDICO'',''{pA}'')']);
SELECT teste_aux.sonda('f','historico forjado: ENC_E insere linha de historico em E1','ENC_E','ERRO',
  ARRAY['insert into saas.historico_status_encaminhamento(encaminhamento_id,status_anterior,status_novo,transicao,ator_tecnico,ator_tipo,ator_papel,ator_id) values (''{E1}'',''AGENDADO'',''ATENDIDO'',''T5'',''saas_app'',''EQUIPE'',''MEDICO'',''{pA}'')']);
SELECT teste_aux.sonda('f','PAC_A altera motivo_cifrado de E1 (dado clinico do medico)','PAC_A','NEGADO',ARRAY['update saas.encaminhamento set motivo_cifrado=''\x00'' where id=''{E1}''']);
SELECT teste_aux.sonda('f','destino (ADM_A) altera motivo_cifrado de E1','ADM_A','NEGADO',ARRAY['update saas.encaminhamento set motivo_cifrado=''\x00'' where id=''{E1}''']);
SELECT teste_aux.sonda('f','PAC_A troca profissional_origem_id de E1 por si/outro','PAC_A','NEGADO',ARRAY['update saas.encaminhamento set profissional_origem_id=''{pE2}'' where id=''{E1}''']);
SELECT teste_aux.sonda('f','profissional global: A le nome/CRM de profissional so de B (INFO; telefone e e-mail sem GRANT, ver r1)','ADM_A','INFO',ARRAY['select 1 from saas.profissional where id=''{pB}''']);

-- ---------------------------------------------------------------------
-- (d) set_config(is_local=true) nao vaza entre transacoes
-- ---------------------------------------------------------------------
DO $$
DECLARE r text; n bigint; k_a text := teste_aux.kid('cA'); k_u text := teste_aux.kid('uA'); s text := md5('sessao-uA');
BEGIN
  COMMIT;
  PERFORM set_config('app.clinica_id', k_a, true); PERFORM set_config('app.usuario', k_u, true); PERFORM set_config('app.papel','ADMIN',true); PERFORM set_config('app.sessao', s, true);
  SELECT count(*) INTO n FROM saas.agendamento;
  INSERT INTO teste_aux.res(secao,nome,ctx,esperado,obtido,ok) VALUES ('d','transacao 1 com contexto A enxerga linhas','local','POSITIVO',n::text,n>0);
  COMMIT;
  SELECT count(*) INTO n FROM saas.agendamento;
  INSERT INTO teste_aux.res(secao,nome,ctx,esperado,obtido,ok) VALUES ('d','transacao 2 (apos COMMIT) nao enxerga nada','local','0',n::text,n=0);
  r := current_setting('app.sessao', true);
  INSERT INTO teste_aux.res(secao,nome,ctx,esperado,obtido,ok) VALUES ('d','app.sessao apos COMMIT e vazio/nulo','local','vazio',coalesce('"'||r||'"','NULL'),coalesce(r,'')='');
  COMMIT;
  PERFORM set_config('app.clinica_id', k_a, true); PERFORM set_config('app.usuario', k_u, true); PERFORM set_config('app.papel','ADMIN',true); PERFORM set_config('app.sessao', s, true);
  ROLLBACK;
  SELECT count(*) INTO n FROM saas.agendamento;
  INSERT INTO teste_aux.res(secao,nome,ctx,esperado,obtido,ok) VALUES ('d','apos ROLLBACK o contexto some','local','0',n::text,n=0);
  COMMIT;
  PERFORM set_config('app.clinica_id', k_a, false); PERFORM set_config('app.usuario', k_u, false); PERFORM set_config('app.papel','ADMIN',false); PERFORM set_config('app.sessao', s, false);
  COMMIT;
  SELECT count(*) INTO n FROM saas.agendamento;
  INSERT INTO teste_aux.res(secao,nome,ctx,esperado,obtido,ok) VALUES ('d','CONTROLE NEGATIVO: set_config(...,false) vaza entre transacoes (pool!)','sessao','INFO',n::text,NULL);
  PERFORM set_config('app.clinica_id','',false); PERFORM set_config('app.usuario','',false); PERFORM set_config('app.papel','',false); PERFORM set_config('app.sessao','',false);
  COMMIT;
  SELECT count(*) INTO n FROM saas.agendamento;
  INSERT INTO teste_aux.res(secao,nome,ctx,esperado,obtido,ok) VALUES ('d','limpeza do controle: contexto vazio nega de novo','sessao','0',n::text,n=0);
  COMMIT;
END $$;

-- ---------------------------------------------------------------------
-- maquina de estados [r1: o banco impoe; INFO da rodada 0 virou ERRO esperado]
-- ---------------------------------------------------------------------
SELECT teste_aux.sonda('estados','ENC_E: CRIADO -> ATENDIDO (pulo T4/T5, ator sem permissao)','ENC_E','ERRO',ARRAY['update saas.encaminhamento set status=''ATENDIDO'' where id=''{E1}''']);
SELECT teste_aux.sonda('estados','ENC_E: CRIADO -> CONTRARREFERIDO (origem finge contrarreferencia)','ENC_E','ERRO',ARRAY['update saas.encaminhamento set status=''CONTRARREFERIDO'' where id=''{E1}''']);
SELECT teste_aux.sonda('estados','PAC_A: CRIADO -> ATENDIDO','PAC_A','ERRO',ARRAY['update saas.encaminhamento set status=''ATENDIDO'' where id=''{E1}''']);
SELECT teste_aux.sonda('estados','PAC_A: CRIADO -> SOLICITADO sem passar por link/consentimento (T3 pulado)','PAC_A','ERRO',ARRAY['update saas.encaminhamento set status=''SOLICITADO'' where id=''{E1}''']);
SELECT teste_aux.sonda('estados','ADM_A (destino): CRIADO -> AGENDADO sem agendamento','ADM_A','ERRO',ARRAY['update saas.encaminhamento set status=''AGENDADO'' where id=''{E1}''']);
SELECT teste_aux.sonda('estados','ENC_E: estado final CANCELADO -> CRIADO (ressuscitar E6)','ENC_E','ERRO',ARRAY['update saas.encaminhamento set status=''CRIADO'' where id=''{E6}''']);
SELECT teste_aux.sonda('estados','ENC_E: estado final CANCELADO -> AGENDADO','ENC_E','ERRO',ARRAY['update saas.encaminhamento set status=''AGENDADO'' where id=''{E6}''']);
SELECT teste_aux.sonda('estados','SISTEMA: expirado E7 -> ATENDIDO (so EXPIRADO permitido pela politica)','SISTEMA','NEGADO',ARRAY['update saas.encaminhamento set status=''ATENDIDO'' where id=''{E7}''']);
SELECT teste_aux.sonda('estados','[r1] saas_app declarando SISTEMA: E7 -> EXPIRADO (T8 so pelo saas_jobs)','SISTEMA','NEGADO',ARRAY['update saas.encaminhamento set status=''EXPIRADO'' where id=''{E7}''']);
SELECT teste_aux.sonda('estados','[r1] saas_app declarando SISTEMA: UPDATE sem WHERE','SISTEMA','NEGADO',ARRAY['update saas.encaminhamento set status=''EXPIRADO''']);
SELECT teste_aux.sonda('estados','[r1] saas_app declarando SISTEMA: T8 por criterio expira_em < now()','SISTEMA','NEGADO',ARRAY['update saas.encaminhamento set status=''EXPIRADO'' where expira_em < now() and status in (''CRIADO'',''ENVIADO_AO_PACIENTE'',''SOLICITADO'')']);
SELECT teste_aux.sonda('estados','status fora dos 8 valores (CHECK)','ENC_E','ERRO',ARRAY['update saas.encaminhamento set status=''INVENTADO'' where id=''{E1}''']);
SELECT teste_aux.sonda('estados','INSERT direto em status AGENDADO','ENC_E','ERRO',ARRAY['insert into saas.encaminhamento(profissional_origem_id,paciente_id,especialidade_destino_id,motivo_cifrado,urgencia,status,expira_em) values (''{pE}'',''{pacA}'',''{eC}'',''\x00'',''ROTINA'',''AGENDADO'',now()+interval ''1 day'')']);
SELECT teste_aux.sonda('estados','transicao ilegal nao deixa linha no historico (recusada antes)','ENC_E','ERRO',
  ARRAY['update saas.encaminhamento set status=''CONTRARREFERIDO'' where id=''{E1}'''],
  'select count(*) from saas.historico_status_encaminhamento where encaminhamento_id=''{E1}'' and status_novo=''CONTRARREFERIDO''');

-- matriz: todo par (de, para) x ator por UPDATE direto. So T9, T10 e T11 passam, cada um com o seu ator.
DO $$ DECLARE de text; para text; c text; ok boolean;
  st text[] := ARRAY['CRIADO','ENVIADO_AO_PACIENTE','SOLICITADO','AGENDADO','ATENDIDO','CONTRARREFERIDO','EXPIRADO','CANCELADO'];
BEGIN
  FOREACH de IN ARRAY st LOOP FOREACH para IN ARRAY st LOOP
    CONTINUE WHEN de = para;
    FOREACH c IN ARRAY ARRAY['ENC_E','PAC_A','ADM_A','REC_A','MED_A','ADM_B','SISTEMA'] LOOP
      ok := para = 'CANCELADO' AND (
              (c = 'ENC_E' AND de IN ('CRIADO','ENVIADO_AO_PACIENTE','SOLICITADO','AGENDADO'))
           OR (c = 'PAC_A' AND de IN ('ENVIADO_AO_PACIENTE','SOLICITADO','AGENDADO'))
           OR (c IN ('ADM_A','REC_A') AND de IN ('SOLICITADO','AGENDADO')));
      PERFORM teste_aux.sonda('matriz', de||' -> '||para||CASE WHEN ok THEN ' (permitido)' ELSE '' END, c,
        CASE WHEN ok THEN 'POSITIVO' ELSE 'NEGADO' END,
        ARRAY[format('select teste_aux.forca_status(''{E1}'',%L)', de),
              format('update saas.encaminhamento set status=%L where id=''{E1}''', para)]);
    END LOOP;
  END LOOP; END LOOP;
END $$;

-- ---------------------------------------------------------------------
-- r1: itens 1 a 19 do Red Team
-- ---------------------------------------------------------------------
-- item 1: sessao verificavel para todo ator
DO $$ DECLARE c text; t text; BEGIN
  FOREACH c IN ARRAY ARRAY['ADM_A_SEM_SESSAO','PAC_A_SEM_SESSAO','PAC_B_SEM_SESSAO','ENC_E_SEM_SESSAO','ADM_A_SESSAO_EXPIRADA','ADM_A_SESSAO_ENCERRADA'] LOOP
    FOREACH t IN ARRAY ARRAY['paciente','encaminhamento','anexo_encaminhamento','contrarreferencia','agendamento','consentimento','paciente_clinica','evento_auditoria'] LOOP
      PERFORM teste_aux.sonda('r1-1','sem sessao valida: ver '||t,c,'0',ARRAY[format('select 1 from saas.%I',t)]);
    END LOOP;
  END LOOP;
END $$;
-- sessao de paciente com GUCs de ADMIN: so o que e do proprio paciente, nada de equipe
DO $$ DECLARE q text; BEGIN
  FOREACH q IN ARRAY ARRAY['select 1 from saas.paciente_clinica','select 1 from saas.evento_auditoria','select 1 from saas.flag_clinica','select 1 from saas.clinica',
                           'select 1 from saas.usuario','select 1 from saas.agendamento where paciente_id<>''{pacA}''','select 1 from saas.encaminhamento where paciente_id<>''{pacA}''',
                           'select 1 from saas.paciente where id<>''{pacA}''','select 1 from saas.horario_atendimento','select 1 from saas.vaga_encaminhamento'] LOOP
    PERFORM teste_aux.sonda('r1-1','sessao de paciente com GUC de ADMIN: '||q,'ADM_A_COM_SESSAO_DE_PACIENTE','0',ARRAY[q]);
  END LOOP;
END $$;
SELECT teste_aux.sonda('r1-1','app.sessao com hex invalido falha fechado','SESSAO_NAO_HEX','NEGADO',ARRAY['select 1 from saas.agendamento']);
SELECT teste_aux.sonda('r1-1','papel web nao le a tabela sessao','ADM_A','ERRO',ARRAY['select 1 from saas.sessao']);
SELECT teste_aux.sonda('r1-1','papel web nao cria sessao direto','ADM_A','ERRO',ARRAY['insert into saas.sessao(token_hash,tipo,paciente_id,expira_em) values (''\x01'',''PACIENTE'',''{pacB}'',now()+interval ''10 min'')']);
SELECT teste_aux.sonda('r1-1','sessao encerrada por logout deixa de valer','ADM_A','0',ARRAY['select saas.sessao_encerra()'],'select count(*) from saas.agendamento');
-- item 2: papel de jobs separado
SELECT teste_aux.sonda('r1-2','SISTEMA pelo papel web nao altera anexo (RT3)','SISTEMA','ERRO',ARRAY['update saas.anexo_encaminhamento set chave_storage=''x'', status_varredura=''LIMPO''']);
SELECT teste_aux.sonda('r1-2','papel web nao executa funcao de jobs (expirar)','ADM_A','ERRO',ARRAY['select saas.jobs_expirar_encaminhamentos()']);
SELECT teste_aux.sonda('r1-2','papel web nao executa funcao de jobs (varredura)','ADM_A','ERRO',ARRAY['select saas.jobs_anexo_varredura(''{anxE1}'',''LIMPO'')']);
SELECT teste_aux.sonda('r1-2','papel web nao executa funcao de jobs (envio prepara)','ADM_A','ERRO',ARRAY['select * from saas.jobs_envio_prepara(''{anxE1}'')']);
SELECT teste_aux.sonda('r1-2','papel web nao abre sessao de equipe (so saas_auth)','NUNCA','ERRO',ARRAY['select saas.sessao_equipe_abre(''sub-uA'')']);
SELECT teste_aux.sonda('r1-2','saas_app: SET ROLE saas_jobs','NUNCA','ERRO',ARRAY['set local role saas_jobs']);
SELECT teste_aux.sonda('r1-2','saas_app: SET ROLE saas_funcoes','NUNCA','ERRO',ARRAY['set local role saas_funcoes']);
SELECT teste_aux.sonda('r1-2','saas_app nao le envio_notificacao','ADM_A','ERRO',ARRAY['select 1 from saas.envio_notificacao']);
-- item 3: profissional amarrado ao usuario
SELECT teste_aux.sonda('r1-3','MEDICO com GUC profissional_id de outro assina contrarreferencia (RT8)','MED_A_FINGE_PB','ERRO',ARRAY['insert into saas.contrarreferencia(encaminhamento_id,clinica_id,autor_profissional_id,conduta_cifrada) values (''{E8}'',''{cA}'',''{pB}'',''\x02'')']);
SELECT teste_aux.sonda('r1-3','ENCAMINHADOR pE2 com GUC profissional_id de pE nao ve E1 (RT5)','ENC_E2_FINGE_PE','0',ARRAY['select 1 from saas.encaminhamento where profissional_origem_id=''{pE}''']);
SELECT teste_aux.sonda('r1-3','PACIENTE pacA com GUC paciente_id de pacB nao le pacB (RT4)','PAC_A_FINGE_PACB','0',ARRAY['select 1 from saas.paciente where id=''{pacB}''']);
SELECT teste_aux.sonda('r1-3','MEDICO sem profissional_clinica ativo na clinica nao cria encaminhamento','MED_A2','ERRO',ARRAY['select saas.encaminhamento_cria(''P'',''119'',NULL,NULL,NULL,''{eC}'',''\x01'',''ROTINA'')']);
SELECT teste_aux.sonda('r1-3','controle: MEDICO com vinculo ativo cria encaminhamento','MED_A','POSITIVO',ARRAY['select saas.encaminhamento_cria(''P'',''119'',NULL,NULL,NULL,''{eC}'',''\x01'',''ROTINA'')'],
  'select count(*) from saas.encaminhamento where profissional_origem_id=''{pA}''');
SELECT teste_aux.sonda('r1-3','sem sessao: encaminhamento_cria recusado','ENC_E_SEM_SESSAO','ERRO',ARRAY['select saas.encaminhamento_cria(''P'',''119'',NULL,NULL,NULL,''{eC}'',''\x01'',''ROTINA'')']);
-- item 4: autenticacao do encaminhador
SELECT teste_aux.sonda('r1-4','CRM existente no formulario de cadastro: nada criado','VAZIO','0',ARRAY['select saas.encaminhador_cadastra(''3001'',''MG'',''Impostor'',''11999990000'',''x@x'')'],
  'select teste_aux.conta(''select count(*) from saas.profissional where nome=''''Impostor'''''')');
SELECT teste_aux.sonda('r1-4','CRM existente no cadastro: token devolvido nunca confirma','VAZIO','0',
  ARRAY['select set_config(''t.tok'', saas.encaminhador_cadastra(''3001'',''MG'',''Impostor'',''11999990000'',''x@x''), true)'],
  'select count(*) from (select saas.encaminhador_confirma_codigo(current_setting(''t.tok''),''000000'') t) x where t is not null');
SELECT teste_aux.sonda('r1-4','pedir codigo por CRM nao abre sessao nem mostra caso','VAZIO','0',
  ARRAY['select set_config(''app.sessao'', coalesce(saas.encaminhador_confirma_codigo(saas.encaminhador_pede_codigo(''3001'',''MG''),''123456''),''''), true)'],
  'select count(*) from saas.encaminhamento');
SELECT teste_aux.sonda('r1-4','codigo errado no desafio de pE: sem sessao','VAZIO','0',ARRAY['select 1'],
  'select count(*) from (select saas.encaminhador_confirma_codigo(''{desD1}'',''000000'') t) x where t is not null');
SELECT teste_aux.sonda('r1-4','controle: codigo certo no desafio de pE abre sessao e mostra E1','VAZIO','POSITIVO',
  ARRAY['select set_config(''app.sessao'', saas.encaminhador_confirma_codigo(''{desD1}'',''654321''), true)'],
  'select count(*) from saas.encaminhamento where id=''{E1}''');
SELECT teste_aux.sonda('r1-4','CRM novo no formulario nasce sem sessao (isolado)','VAZIO','0',
  ARRAY['select set_config(''t.tok'', saas.encaminhador_cadastra(''9999'',''PE'',''Dr Novo'',''81999990000'',''n@x''), true)'],
  'select count(*) from (select saas.encaminhador_confirma_codigo(current_setting(''t.tok''),''000000'') t) x where t is not null');
-- item 5: FK compostas
SELECT teste_aux.sonda('r1-5','contrarreferencia com clinica_id diferente do destino','MED_A','ERRO',ARRAY['insert into saas.contrarreferencia(encaminhamento_id,clinica_id,autor_profissional_id,conduta_cifrada) values (''{E2}'',''{cA}'',''{pA}'',''\x02'')']);
SELECT teste_aux.sonda('r1-5','consentimento de pacA apontando E2 (de pacB)','PAC_A','ERRO',ARRAY['insert into saas.consentimento(paciente_id,finalidade,encaminhamento_id,clinica_id,texto_aceito,versao_texto,canal) values (''{pacA}'',''COMPARTILHAR_CASO'',''{E2}'',''{cB}'',''t'',''v1'',''SITE'')']);
SELECT teste_aux.sonda('r1-5','agendamento de encaminhamento so por destino_confirma_horario','REC_A','ERRO',ARRAY['insert into saas.agendamento(clinica_id,profissional_clinica_id,paciente_id,inicio,fim,origem,encaminhamento_id,chave_idempotencia) values (''{cA}'',''{pcA}'',''{pacA}'',now()+interval ''60 days'',now()+interval ''60 days 30 min'',''ENCAMINHAMENTO'',''{E1}'',''x5'')']);
-- item 6: paciente nunca por UUID do cliente
SELECT teste_aux.sonda('r1-6','insert direto em paciente_clinica com paciente proprio','ADM_A','ERRO',ARRAY['insert into saas.paciente_clinica(paciente_id,clinica_id) values (''{pacX}'',''{cA}'')']);
SELECT teste_aux.sonda('r1-6','insert direto em paciente','ENC_E','ERRO',ARRAY['insert into saas.paciente(nome,telefone) values (''x'',''1'')']);
SELECT teste_aux.sonda('r1-6','insert direto em encaminhamento','ENC_E','ERRO',ARRAY['insert into saas.encaminhamento(profissional_origem_id,paciente_id,especialidade_destino_id,motivo_cifrado,urgencia,expira_em) values (''{pE}'',''{pacA}'',''{eC}'',''\x00'',''ROTINA'',now()+interval ''1 day'')']);
DO $$ DECLARE c text; BEGIN
  FOREACH c IN ARRAY ARRAY['ENC_E','PAC_A','ADM_A'] LOOP
    PERFORM teste_aux.sonda('r1-6','UPDATE paciente_id de E1',c,'ERRO',ARRAY['update saas.encaminhamento set paciente_id=''{pacB}'' where id=''{E1}''']);
  END LOOP;
END $$;
-- item 7: telefone do paciente
SELECT teste_aux.sonda('r1-7','PACIENTE troca o proprio telefone (RT10)','PAC_A','ERRO',ARRAY['update saas.paciente set telefone=''+5581988888888'' where id=''{pacA}''']);
SELECT teste_aux.sonda('r1-7','recepcao troca telefone por UPDATE direto (RT1)','REC_A','ERRO',ARRAY['update saas.paciente set telefone=''+5581999999999'' where id=''{pacA}''']);
SELECT teste_aux.sonda('r1-7','controle: troca presencial pela clinica que cadastrou','REC_A','POSITIVO',ARRAY['select saas.paciente_troca_telefone_presencial(''{pacA}'',''11900009999'')'],
  'select count(*) from saas.paciente where id=''{pacA}'' and telefone=''11900009999''');
SELECT teste_aux.sonda('r1-7','troca presencial de paciente que a clinica nao cadastrou','REC_A','ERRO',ARRAY['select saas.paciente_troca_telefone_presencial(''{pacX}'',''11900009999'')']);
SELECT teste_aux.sonda('r1-7','troca presencial por outra clinica','ADM_B','ERRO',ARRAY['select saas.paciente_troca_telefone_presencial(''{pacA}'',''11900009999'')']);
SELECT teste_aux.sonda('r1-7','controle: recepcao altera nome de paciente que cadastrou','REC_A','POSITIVO',ARRAY['update saas.paciente set nome=''Paciente A2'' where id=''{pacA}''']);
SELECT teste_aux.sonda('r1-7','outra clinica nao altera nome','ADM_B','0',ARRAY['update saas.paciente set nome=''x'' where id=''{pacA}''']);
-- item 8: deduplicacao
SELECT teste_aux.sonda('r1-8','encaminhador sem vinculo com pacB usa CPF de pacB: nao acha pacB','ENC_E2','0',
  ARRAY['select saas.encaminhamento_cria(''Outro nome'',''21911110002'',NULL,''\xaa02'',''\xbb02'',''{eC}'',''\x01'',''ROTINA'')'],
  'select count(*) from saas.paciente where id=''{pacB}''');
SELECT teste_aux.sonda('r1-8','... e cria paciente novo (visivel so a ele)','ENC_E2','POSITIVO',
  ARRAY['select saas.encaminhamento_cria(''Outro nome'',''21911110002'',NULL,''\xaa02'',''\xbb02'',''{eC}'',''\x01'',''ROTINA'')'],
  'select count(*) from saas.paciente');
SELECT teste_aux.sonda('r1-8','controle: encaminhador ja ligado a pacA reaproveita pacA','ENC_E','POSITIVO',
  ARRAY['select saas.encaminhamento_cria(''x'',''x'',NULL,NULL,''\xbb01'',''{eC}'',''\x01'',''ROTINA'')'],
  'select count(*) from saas.encaminhamento where criado_em = now() and paciente_id=''{pacA}''');
SELECT teste_aux.sonda('r1-8','recepcao A cadastra CPF de pacB: nao acha pacB','REC_A','0',
  ARRAY['select saas.paciente_cadastra_na_clinica(''x'',''x'',NULL,NULL,''\xbb02'')'],
  'select count(*) from saas.paciente where id=''{pacB}''');
SELECT teste_aux.sonda('r1-8','... pacientes com o hash de pacB passam a ser 2 (registro novo)','REC_A','POSITIVO',
  ARRAY['select saas.paciente_cadastra_na_clinica(''x'',''x'',NULL,NULL,''\xbb02'')'],
  'select (teste_aux.conta(''select count(*) from saas.paciente where cpf_hash=''''\xbb02'''''') = 2)::int');
-- item 9: colunas imutaveis por ator
DO $$ DECLARE c text; col text; BEGIN
  FOREACH c IN ARRAY ARRAY['ENC_E','PAC_A','ADM_A','REC_A','MED_A'] LOOP
    FOREACH col IN ARRAY ARRAY['motivo_cifrado=''\x00''','paciente_id=''{pacB}''','profissional_origem_id=''{pE2}''','especialidade_destino_id=''{eD}''',
                               'expira_em=now()+interval ''1 year''','clinica_destino_id=''{cB}''','profissional_destino_id=''{pB}''','criado_em=now()'] LOOP
      PERFORM teste_aux.sonda('r1-9','UPDATE '||split_part(col,'=',1)||' de E1',c,'ERRO',ARRAY['update saas.encaminhamento set '||col||' where id=''{E1}''']);
    END LOOP;
  END LOOP;
END $$;
SELECT teste_aux.sonda('r1-9','controle: origem muda urgencia em CRIADO','ENC_E','POSITIVO',ARRAY['update saas.encaminhamento set urgencia=''URGENTE'' where id=''{E1}''']);
SELECT teste_aux.sonda('r1-9','paciente muda urgencia','PAC_A','ERRO',ARRAY['update saas.encaminhamento set urgencia=''URGENTE'' where id=''{E1}''']);
SELECT teste_aux.sonda('r1-9','destino muda urgencia','ADM_A','ERRO',ARRAY['update saas.encaminhamento set urgencia=''URGENTE'' where id=''{E1}''']);
SELECT teste_aux.sonda('r1-9','origem muda urgencia depois de SOLICITADO','ENC_E','ERRO',ARRAY['select teste_aux.forca_status(''{E1}'',''SOLICITADO'')','update saas.encaminhamento set urgencia=''URGENTE'' where id=''{E1}''']);
-- item 10: transicoes por funcao (T3, T4, T6) e efeitos (cancelamento em cascata, historico)
SELECT teste_aux.sonda('r1-10','T3 paciente_solicita (rede ligada em A)','PAC_A','POSITIVO',
  ARRAY['select teste_aux.forca_status(''{E1}'',''ENVIADO_AO_PACIENTE'')','select saas.paciente_solicita(''{E1}'',''{cA}'',NULL,''t'',''v1'')'],
  'select count(*) from saas.encaminhamento where id=''{E1}'' and status=''SOLICITADO''');
SELECT teste_aux.sonda('r1-10','T3 para clinica com a rede desligada (B)','PAC_A','ERRO',
  ARRAY['select teste_aux.forca_status(''{E1}'',''ENVIADO_AO_PACIENTE'')','select saas.paciente_solicita(''{E1}'',''{cB}'',NULL,''t'',''v1'')']);
SELECT teste_aux.sonda('r1-10','T3 por outro paciente','PAC_B','ERRO',
  ARRAY['select teste_aux.forca_status(''{E1}'',''ENVIADO_AO_PACIENTE'')','select saas.paciente_solicita(''{E1}'',''{cA}'',NULL,''t'',''v1'')']);
SELECT teste_aux.sonda('r1-10','T3 a partir de CRIADO','PAC_A','ERRO',ARRAY['select saas.paciente_solicita(''{E1}'',''{cA}'',NULL,''t'',''v1'')']);
SELECT teste_aux.sonda('r1-10','T4 recepcao do destino confirma horario','REC_A','POSITIVO',
  ARRAY['select teste_aux.forca_status(''{E1}'',''SOLICITADO'')','select saas.destino_confirma_horario(''{E1}'',''{pcA}'',now()+interval ''20 days'',now()+interval ''20 days 30 min'',''conf-1'')'],
  'select count(*) from saas.encaminhamento e join saas.agendamento a on a.encaminhamento_id=e.id where e.id=''{E1}'' and e.status=''AGENDADO'' and a.status=''AGENDADO''');
SELECT teste_aux.sonda('r1-10','T4 por MEDICO','MED_A','ERRO',
  ARRAY['select teste_aux.forca_status(''{E1}'',''SOLICITADO'')','select saas.destino_confirma_horario(''{E1}'',''{pcA}'',now()+interval ''20 days'',now()+interval ''20 days 30 min'',''conf-1'')']);
SELECT teste_aux.sonda('r1-10','T4 por outra clinica','ADM_B','ERRO',
  ARRAY['select teste_aux.forca_status(''{E1}'',''SOLICITADO'')','select saas.destino_confirma_horario(''{E1}'',''{pcB}'',now()+interval ''20 days'',now()+interval ''20 days 30 min'',''conf-1'')']);
SELECT teste_aux.sonda('r1-10','T9 em AGENDADO cancela o agendamento ativo (S1 d)','REC_A','POSITIVO',
  ARRAY['select teste_aux.forca_status(''{E1}'',''SOLICITADO'')','select saas.destino_confirma_horario(''{E1}'',''{pcA}'',now()+interval ''20 days'',now()+interval ''20 days 30 min'',''conf-1'')',
        'ctx:ENC_E','update saas.encaminhamento set status=''CANCELADO'' where id=''{E1}''','ctx:REC_A'],
  'select count(*) from saas.agendamento where encaminhamento_id=''{E1}'' and status=''CANCELADO''');
SELECT teste_aux.sonda('r1-10','historico de T9: ator verificado (ENCAMINHADOR pE, saas_app)','ENC_E','POSITIVO',
  ARRAY['update saas.encaminhamento set status=''CANCELADO'' where id=''{E1}'''],
  'select count(*) from saas.historico_status_encaminhamento where encaminhamento_id=''{E1}'' and transicao=''T9'' and ator_tipo=''ENCAMINHADOR'' and ator_papel=''ENCAMINHADOR'' and ator_id=''{pE}'' and ator_tecnico=''saas_app''');
SELECT teste_aux.sonda('r1-10','T6 grava CONTRARREFERIDO e historico com MEDICO','MED_A','POSITIVO',
  ARRAY['insert into saas.contrarreferencia(encaminhamento_id,clinica_id,autor_profissional_id,conduta_cifrada) values (''{E8}'',''{cA}'',''{pA}'',''\xff'')'],
  'select count(*) from saas.historico_status_encaminhamento h join saas.encaminhamento e on e.id=h.encaminhamento_id where e.id=''{E8}'' and e.status=''CONTRARREFERIDO'' and h.transicao=''T6'' and h.ator_papel=''MEDICO'' and h.ator_id=''{uMedA}''');
SELECT teste_aux.sonda('r1-10','contrarreferencia com encaminhamento CRIADO (T-17)','MED_A','ERRO',ARRAY['insert into saas.contrarreferencia(encaminhamento_id,clinica_id,autor_profissional_id,conduta_cifrada) values (''{E1}'',''{cA}'',''{pA}'',''\xff'')']);
SELECT teste_aux.sonda('r1-10','segunda contrarreferencia do mesmo encaminhamento','MED_A','ERRO',ARRAY['insert into saas.contrarreferencia(encaminhamento_id,clinica_id,autor_profissional_id,conduta_cifrada) values (''{E8}'',''{cA}'',''{pA}'',''\xff'')','insert into saas.contrarreferencia(encaminhamento_id,clinica_id,autor_profissional_id,conduta_cifrada) values (''{E8}'',''{cA}'',''{pA}'',''\xfe'')']);
-- item 11: consentimento
SELECT teste_aux.sonda('r1-11','PAC_A consente para E1 em nome da clinica B (nao destino)','PAC_A','ERRO',ARRAY['insert into saas.consentimento(paciente_id,finalidade,encaminhamento_id,clinica_id,texto_aceito,versao_texto,canal) values (''{pacA}'',''COMPARTILHAR_CASO'',''{E1}'',''{cB}'',''t'',''v1'',''SITE'')']);
SELECT teste_aux.sonda('r1-11','PAC_A consente em nome de pacB','PAC_A','ERRO',ARRAY['insert into saas.consentimento(paciente_id,finalidade,clinica_id,texto_aceito,versao_texto,canal) values (''{pacB}'',''COMUNICACAO_WHATSAPP'',NULL,''t'',''v1'',''SITE'')']);
SELECT teste_aux.sonda('r1-11','recepcao A registra consentimento de pacB (sem vinculo, T-14)','REC_A','ERRO',ARRAY['insert into saas.consentimento(paciente_id,finalidade,clinica_id,texto_aceito,versao_texto,canal) values (''{pacB}'',''AGENDAMENTO'',''{cA}'',''t'',''v1'',''RECEPCAO'')']);
SELECT teste_aux.sonda('r1-11','controle: recepcao A registra consentimento de pacA','REC_A','POSITIVO',ARRAY['insert into saas.consentimento(paciente_id,finalidade,clinica_id,texto_aceito,versao_texto,canal) values (''{pacA}'',''COMUNICACAO_WHATSAPP'',''{cA}'',''t'',''v1'',''RECEPCAO'')']);
SELECT teste_aux.sonda('r1-11','controle: PAC_A consente para E1 e clinica destino A','PAC_A','POSITIVO',ARRAY['insert into saas.consentimento(paciente_id,finalidade,encaminhamento_id,clinica_id,texto_aceito,versao_texto,canal) values (''{pacA}'',''COMPARTILHAR_CASO'',''{E1}'',''{cA}'',''t'',''v2'',''SITE'')']);
-- item 12: auditoria com ator verificado
SELECT teste_aux.sonda('r1-12','ENCAMINHADOR grava auditoria como ADMIN (RT6)','ENC_E','ERRO',ARRAY['insert into saas.evento_auditoria(ator_papel,ator_id,acao,recurso_tipo) values (''ADMIN'',''{uRecA}'',''LER_ENCAMINHAMENTO'',''encaminhamento'')']);
SELECT teste_aux.sonda('r1-12','ENCAMINHADOR grava auditoria com ator_id de outro','ENC_E','ERRO',ARRAY['insert into saas.evento_auditoria(ator_papel,ator_id,acao,recurso_tipo) values (''ENCAMINHADOR'',''{pE2}'',''X'',''X'')']);
SELECT teste_aux.sonda('r1-12','RECEPCAO grava auditoria como ADMIN','REC_A','ERRO',ARRAY['insert into saas.evento_auditoria(ator_papel,clinica_id,acao,recurso_tipo) values (''ADMIN'',''{cA}'',''X'',''X'')']);
SELECT teste_aux.sonda('r1-12','sem sessao nao grava auditoria','SO_PAPEL_ADMIN','ERRO',ARRAY['insert into saas.evento_auditoria(ator_papel,acao,recurso_tipo) values (''ADMIN'',''X'',''X'')']);
SELECT teste_aux.sonda('r1-12','controle: ENCAMINHADOR grava auditoria propria (ator_id preenchido pela sessao)','ENC_E','POSITIVO',ARRAY['insert into saas.evento_auditoria(ator_papel,acao,recurso_tipo) values (''ENCAMINHADOR'',''X'',''X'')']);
-- item 13: link e codigo
SELECT teste_aux.sonda('r1-13','PUBLICO_LINK nao altera link_paciente (RT2)','LINK_E1','ERRO',ARRAY['update saas.link_paciente set tentativas_codigo=0, codigo_hash=''\xbeef'', expira_em=now()+interval ''365 days''']);
SELECT teste_aux.sonda('r1-13','paciente com sessao nao altera link_paciente','PAC_A','ERRO',ARRAY['update saas.link_paciente set tentativas_codigo=0']);
SELECT teste_aux.sonda('r1-13','token desconhecido: link_consulta vazio','VAZIO','0',ARRAY['select 1 from saas.link_consulta(''abcdef0123456789'')']);
SELECT teste_aux.sonda('r1-13','GET (link_consulta) nao consome o link','VAZIO','POSITIVO',ARRAY['select * from saas.link_consulta(''{tokE1}'')','select * from saas.link_consulta(''{tokE1}'')'],'select count(*) from saas.link_consulta(''{tokE1}'')');
SELECT teste_aux.sonda('r1-13','controle: codigo certo abre sessao do paciente e mostra E1','VAZIO','POSITIVO',
  ARRAY['select set_config(''app.sessao'', saas.paciente_confirma_codigo(''{tokE1}'',''123456''), true)'],
  'select count(*) from saas.encaminhamento where id=''{E1}''');
SELECT teste_aux.sonda('r1-13','... e essa sessao nao mostra E3 (outro paciente)','VAZIO','0',
  ARRAY['select set_config(''app.sessao'', saas.paciente_confirma_codigo(''{tokE1}'',''123456''), true)'],
  'select count(*) from saas.encaminhamento where id=''{E3}''');
SELECT teste_aux.sonda('r1-13','link usado nao abre segunda sessao','VAZIO','0',
  ARRAY['select saas.paciente_confirma_codigo(''{tokE1}'',''123456'')'],
  'select count(*) from (select saas.paciente_confirma_codigo(''{tokE1}'',''123456'') t) x where t is not null');
SELECT teste_aux.sonda('r1-13','limite somado por encaminhamento: link revogado com 9 + 1 erro bloqueia o codigo certo','VAZIO','0',
  ARRAY['select saas.paciente_confirma_codigo(''{tokE1}'',''000000'')'],
  'select count(*) from (select saas.paciente_confirma_codigo(''{tokE1}'',''123456'') t) x where t is not null');
SELECT teste_aux.sonda('r1-13','link revogado nao confirma','VAZIO','0',ARRAY['select 1'],
  'select count(*) from (select saas.paciente_confirma_codigo(''{tokL0}'',''123456'') t) x where t is not null');
SELECT teste_aux.sonda('r1-13','pedido de codigo aceito','VAZIO','POSITIVO',ARRAY['select 1'],'select saas.paciente_pede_codigo(''{tokE1}'')::int');
SELECT teste_aux.sonda('r1-13','quarto pedido de codigo na mesma hora recusado','VAZIO','0',
  ARRAY['select saas.paciente_pede_codigo(''{tokE1}'')','select saas.paciente_pede_codigo(''{tokE1}'')','select saas.paciente_pede_codigo(''{tokE1}'')'],
  'select saas.paciente_pede_codigo(''{tokE1}'')::int');
-- item 14: anexo
SELECT teste_aux.sonda('r1-14','controle: origem anexa sem informar chave; servidor gera','ENC_E','POSITIVO',
  ARRAY['insert into saas.anexo_encaminhamento(encaminhamento_id,tipo_mime,tamanho_bytes,sha256,enviado_por_tipo,enviado_por_id) values (''{E1}'',''application/pdf'',10,''\x01'',''PROFISSIONAL'',''{pE}'')'],
  'select count(*) from saas.anexo_encaminhamento where encaminhamento_id=''{E1}'' and chave_storage ~ ''^[0-9a-f-]{36}$'' and status_varredura=''PENDENTE''');
SELECT teste_aux.sonda('r1-14','cliente escolhe chave_storage','ENC_E','ERRO',ARRAY['insert into saas.anexo_encaminhamento(encaminhamento_id,chave_storage,tipo_mime,tamanho_bytes,sha256,enviado_por_tipo,enviado_por_id) values (''{E1}'',''obj-E2'',''application/pdf'',10,''\x01'',''PROFISSIONAL'',''{pE}'')']);
SELECT teste_aux.sonda('r1-14','cliente grava status LIMPO no upload','ENC_E','ERRO',ARRAY['insert into saas.anexo_encaminhamento(encaminhamento_id,tipo_mime,tamanho_bytes,sha256,enviado_por_tipo,enviado_por_id,status_varredura) values (''{E1}'',''application/pdf'',10,''\x01'',''PROFISSIONAL'',''{pE}'',''LIMPO'')']);
SELECT teste_aux.sonda('r1-14','origem altera anexo','ENC_E','ERRO',ARRAY['update saas.anexo_encaminhamento set chave_storage=''x'' where encaminhamento_id=''{E1}''']);
-- item 15: agendamento pelo paciente e flag da rede
SELECT teste_aux.sonda('r1-15','PACIENTE insere agendamento (RT7)','PAC_B','ERRO',ARRAY['insert into saas.agendamento(clinica_id,profissional_clinica_id,paciente_id,inicio,fim,origem,chave_idempotencia) values (''{cB}'',''{pcB}'',''{pacB}'',now()+interval ''1 day'',now()+interval ''1 day 30 min'',''SITE'',''k1'')']);
SELECT teste_aux.sonda('r1-15','catalogo: clinica com rede desligada nao aparece','ENC_E','0',ARRAY['select 1 from saas.catalogo_rede(''{eC}'') where clinica_id=''{cB}''']);
SELECT teste_aux.sonda('r1-15','controle: catalogo mostra clinica com rede ligada','ENC_E','POSITIVO',ARRAY['select 1 from saas.catalogo_rede(''{eC}'') where clinica_id=''{cA}''']);
SELECT teste_aux.sonda('r1-15','catalogo sem sessao vazio','VAZIO','0',ARRAY['select 1 from saas.catalogo_rede(''{eC}'')']);
SELECT teste_aux.sonda('r1-15','modo VAGAS recusado ate a Fase 6','ADM_A','ERRO',ARRAY['update saas.clinica set modo_recebimento=''VAGAS'' where id=''{cA}''']);
-- item 17: catalogo e profissional
SELECT teste_aux.sonda('r1-17','ENCAMINHADOR nao le tabela clinica (cnpj)','ENC_E','0',ARRAY['select 1 from saas.clinica']);
SELECT teste_aux.sonda('r1-17','PACIENTE nao le tabela clinica','PAC_A','0',ARRAY['select 1 from saas.clinica']);
SELECT teste_aux.sonda('r1-17','ENCAMINHADOR nao le telefone de medico','ENC_E','ERRO',ARRAY['select telefone from saas.profissional']);
SELECT teste_aux.sonda('r1-17','PACIENTE nao le e-mail de medico','PAC_A','ERRO',ARRAY['select email from saas.profissional']);
SELECT teste_aux.sonda('r1-17','equipe nao le telefone de medico','ADM_A','ERRO',ARRAY['select telefone from saas.profissional']);
SELECT teste_aux.sonda('r1-17','profissional sem sessao: 0 linhas','SO_PAPEL_ADMIN','0',ARRAY['select 1 from saas.profissional']);
SELECT teste_aux.sonda('r1-17','profissional com GUC lixo','GUC_LIXO','INFO',ARRAY['select 1 from saas.profissional']);
SELECT teste_aux.sonda('r1-17','ENCAMINHADOR nao altera o proprio CRM (T-15)','ENC_E','ERRO',ARRAY['update saas.profissional set crm=''2001'' where id=''{pE}''']);
SELECT teste_aux.sonda('r1-17','ENCAMINHADOR nao se liga a usuario da equipe (T-15)','ENC_E','ERRO',ARRAY['update saas.profissional set usuario_id=''{uA}'' where id=''{pE}''']);
SELECT teste_aux.sonda('r1-17','ENCAMINHADOR nao cadastra profissional direto (RT9, sem oraculo de CRM)','ENC_E','ERRO',ARRAY['insert into saas.profissional(crm,crm_uf,nome) values (''2001'',''RJ'',''x'')']);
\o
SELECT t.tgname AS gatilho_em_encaminhamento, pg_get_triggerdef(t.oid) AS definicao
  FROM pg_trigger t WHERE t.tgrelid='saas.encaminhamento'::regclass AND NOT t.tgisinternal ORDER BY 1;

-- =====================================================================
-- PARTE 2b: jobs e listeners (saas_jobs: sem privilegio em tabela)
-- =====================================================================
\echo
\echo '===== PARTE 2b: testes como saas_jobs ====='
\connect - saas_jobs
SET search_path = saas, public;
SELECT current_user AS papel_de_conexao, rolsuper, rolbypassrls FROM pg_roles WHERE rolname = current_user;
\o /dev/null
DO $$ DECLARE t text; BEGIN
  FOR t IN SELECT tablename FROM pg_tables WHERE schemaname='saas' AND tablename <> 'especialidade' ORDER BY 1 LOOP
    PERFORM teste_aux.sonda('jobs','saas_jobs nao le '||t,'NUNCA','ERRO',ARRAY[format('select 1 from saas.%I',t)]);
  END LOOP;
END $$;
SELECT teste_aux.sonda('jobs','saas_jobs nao altera anexo direto (RT3)','NUNCA','ERRO',ARRAY['update saas.anexo_encaminhamento set chave_storage=''x''']);
SELECT teste_aux.sonda('jobs','saas_jobs nao altera encaminhamento direto','NUNCA','ERRO',ARRAY['update saas.encaminhamento set status=''EXPIRADO''']);
SELECT teste_aux.sonda('jobs','saas_jobs nao executa funcao da web','NUNCA','ERRO',ARRAY['select saas.encaminhamento_cria(''P'',''1'',NULL,NULL,NULL,''{eC}'',''\x01'',''ROTINA'')']);
SELECT teste_aux.sonda('jobs','saas_jobs nao abre sessao de equipe','NUNCA','ERRO',ARRAY['select saas.sessao_equipe_abre(''sub-uA'')']);
SELECT teste_aux.sonda('jobs','T8 com WHERE: expira exatamente 1 (E7)','NUNCA','POSITIVO',ARRAY['select 1'],'select (saas.jobs_expirar_encaminhamentos() = 1)::int');
SELECT teste_aux.sonda('jobs','T8 nao toca nao vencidos (segunda chamada = 0)','NUNCA','0',ARRAY['select saas.jobs_expirar_encaminhamentos()'],'select saas.jobs_expirar_encaminhamentos()');
SELECT teste_aux.sonda('jobs','T8 deixou E1 em CRIADO','NUNCA','POSITIVO',ARRAY['select saas.jobs_expirar_encaminhamentos()'],
  'select teste_aux.conta(''select count(*) from saas.encaminhamento where id=''''{E1}'''' and status=''''CRIADO'''''')');
SELECT teste_aux.sonda('jobs','T8 historico com ator SISTEMA e ator_tecnico saas_jobs','NUNCA','POSITIVO',ARRAY['select saas.jobs_expirar_encaminhamentos()'],
  'select teste_aux.conta(''select count(*) from saas.historico_status_encaminhamento where encaminhamento_id=''''{E7}'''' and transicao=''''T8'''' and ator_tipo=''''SISTEMA'''' and ator_tecnico=''''saas_jobs'''''')');
SELECT teste_aux.sonda('jobs','T5 ConsultaRealizada (agendamento REALIZADO de E9)','NUNCA','POSITIVO',ARRAY['select 1'],'select saas.jobs_consulta_realizada(''{agE9}'')::int');
SELECT teste_aux.sonda('jobs','T5 reentregue: sem efeito duplo','NUNCA','0',ARRAY['select saas.jobs_consulta_realizada(''{agE9}'')'],'select saas.jobs_consulta_realizada(''{agE9}'')::int');
SELECT teste_aux.sonda('jobs','T5 historico com autor de negocio lido do agendamento (uMedA)','NUNCA','POSITIVO',ARRAY['select saas.jobs_consulta_realizada(''{agE9}'')'],
  'select teste_aux.conta(''select count(*) from saas.historico_status_encaminhamento where encaminhamento_id=''''{E9}'''' and transicao=''''T5'''' and ator_tipo=''''SISTEMA'''' and autor_negocio_id=''''{uMedA}'''''')');
SELECT teste_aux.sonda('jobs','T5 com agendamento sem encaminhamento: nada','NUNCA','0',ARRAY['select 1'],'select saas.jobs_consulta_realizada(''{agA1}'')::int');
SELECT teste_aux.sonda('jobs','T5 com agendamento nao REALIZADO: nada','NUNCA','0',ARRAY['select teste_aux.forca_agendamento(''{agE9}'',''AGENDADO'')'],'select saas.jobs_consulta_realizada(''{agE9}'')::int');
SELECT teste_aux.sonda('jobs','T7 agendamento cancelado volta E9 a SOLICITADO','NUNCA','POSITIVO',ARRAY['select teste_aux.forca_agendamento(''{agE9}'',''CANCELADO'')'],'select saas.jobs_agendamento_desfeito(''{agE9}'')::int');
SELECT teste_aux.sonda('jobs','T7 com agendamento ainda REALIZADO: nada','NUNCA','0',ARRAY['select 1'],'select saas.jobs_agendamento_desfeito(''{agE9}'')::int');
SELECT teste_aux.sonda('jobs','T2 link aceito pelo provedor: E5 vai a ENVIADO_AO_PACIENTE','NUNCA','POSITIVO',
  ARRAY['select set_config(''t.envio'', saas.jobs_envio_link_paciente(''{E5}'')::text, true)','select * from saas.jobs_envio_prepara(current_setting(''t.envio'')::uuid)'],
  'select saas.jobs_envio_resultado(current_setting(''t.envio'')::uuid,''ACEITO'',''prov-1'')::int');
SELECT teste_aux.sonda('jobs','envio preparado devolve 1 contato e 1 segredo','NUNCA','POSITIVO',
  ARRAY['select set_config(''t.envio'', saas.jobs_envio_link_paciente(''{E5}'')::text, true)'],
  'select count(*) from saas.jobs_envio_prepara(current_setting(''t.envio'')::uuid) where contato is not null and length(segredo)=64');
SELECT teste_aux.sonda('jobs','mesmo envio nao e preparado duas vezes','NUNCA','ERRO',
  ARRAY['select set_config(''t.envio'', saas.jobs_envio_link_paciente(''{E5}'')::text, true)','select * from saas.jobs_envio_prepara(current_setting(''t.envio'')::uuid)','select * from saas.jobs_envio_prepara(current_setting(''t.envio'')::uuid)']);
SELECT teste_aux.sonda('jobs','reemissao deixa so 1 link ativo por encaminhamento','NUNCA','POSITIVO',
  ARRAY['select set_config(''t.e1'', saas.jobs_envio_link_paciente(''{E5}'')::text, true)','select * from saas.jobs_envio_prepara(current_setting(''t.e1'')::uuid)',
        'select set_config(''t.e2'', saas.jobs_envio_link_paciente(''{E5}'')::text, true)','select * from saas.jobs_envio_prepara(current_setting(''t.e2'')::uuid)'],
  'select (teste_aux.conta(''select count(*) from saas.link_paciente where encaminhamento_id=''''{E5}'''' and usado_em is null and revogado_em is null'') = 1)::int');
SELECT teste_aux.sonda('jobs','origem nao verificada: nenhum link sai ao paciente (S-02)','NUNCA','ERRO',ARRAY['select saas.jobs_envio_link_paciente(''{E10}'')']);
SELECT teste_aux.sonda('jobs','varredura PENDENTE -> LIMPO','NUNCA','POSITIVO',ARRAY['select saas.jobs_anexo_varredura(''{anxE1}'',''LIMPO'')'],
  'select teste_aux.conta(''select count(*) from saas.anexo_encaminhamento where id=''''{anxE1}'''' and status_varredura=''''LIMPO'''' and chave_storage=''''obj-E1'''''')');
SELECT teste_aux.sonda('jobs','varredura LIMPO -> INFECTADO (sem volta)','NUNCA','ERRO',ARRAY['select saas.jobs_anexo_varredura(''{anxE1}'',''LIMPO'')','select saas.jobs_anexo_varredura(''{anxE1}'',''INFECTADO'')']);
SELECT teste_aux.sonda('jobs','varredura com resultado PENDENTE','NUNCA','ERRO',ARRAY['select saas.jobs_anexo_varredura(''{anxE1}'',''PENDENTE'')']);
\o

-- =====================================================================
-- PARTE 2c: componente de login (saas_auth)
-- =====================================================================
\echo
\echo '===== PARTE 2c: testes como saas_auth ====='
\connect - saas_auth
SET search_path = saas, public;
\o /dev/null
SELECT teste_aux.sonda('auth','saas_auth abre sessao de usuario ativo','NUNCA','POSITIVO',ARRAY['select 1'],'select count(*) from (select saas.sessao_equipe_abre(''sub-uA'') t) x where length(t)=64');
SELECT teste_aux.sonda('auth','saas_auth com sub inexistente','NUNCA','ERRO',ARRAY['select saas.sessao_equipe_abre(''sub-nao-existe'')']);
SELECT teste_aux.sonda('auth','saas_auth nao le usuario','NUNCA','ERRO',ARRAY['select 1 from saas.usuario']);
SELECT teste_aux.sonda('auth','saas_auth nao le sessao','NUNCA','ERRO',ARRAY['select 1 from saas.sessao']);
SELECT teste_aux.sonda('auth','saas_auth nao executa funcao de jobs','NUNCA','ERRO',ARRAY['select saas.jobs_expirar_encaminhamentos()']);
SELECT teste_aux.sonda('auth','saas_auth nao executa funcao da web','NUNCA','ERRO',ARRAY['select 1 from saas.catalogo_rede(''{eC}'')']);
\o

-- ---------------------------------------------------------------------
-- relatorio
-- ---------------------------------------------------------------------
\connect - pgtest
\echo
\echo '===== RESUMO POR SECAO ====='
SELECT secao, count(*) AS total, count(*) FILTER (WHERE ok) AS passou, count(*) FILTER (WHERE ok = false) AS falhou, count(*) FILTER (WHERE ok IS NULL) AS info
  FROM teste_aux.res GROUP BY secao ORDER BY secao;
SELECT count(*) AS total, count(*) FILTER (WHERE ok) AS passou, count(*) FILTER (WHERE ok = false) AS falhou, count(*) FILTER (WHERE ok IS NULL) AS info,
       count(*) FILTER (WHERE ok AND esperado IN ('ERRO','0','NEGADO')) AS sondas_de_ataque_negadas,
       count(*) FILTER (WHERE ok AND esperado IN ('POSITIVO','OK')) AS controles_positivos_ok
  FROM teste_aux.res;
\echo
\echo '===== FALHAS (esperado x obtido) ====='
\pset format wrapped
\pset columns 200
SELECT n, secao, nome, ctx, esperado, obtido FROM teste_aux.res WHERE ok = false ORDER BY n;
\echo
\echo '===== INFO (so registro) ====='
SELECT n, secao, nome, ctx, obtido FROM teste_aux.res WHERE ok IS NULL ORDER BY n;
\echo
\echo '===== TODAS AS SONDAS ====='
SELECT n, secao, CASE WHEN ok THEN 'PASSOU' WHEN ok = false THEN 'FALHOU' ELSE 'INFO' END AS resultado, nome, ctx, esperado, obtido FROM teste_aux.res ORDER BY n;
\pset format aligned

-- =====================================================================
-- PARTE 3: dono/superusuario. Gatilhos e restricoes que valem ate para eles
-- =====================================================================
\echo
\echo '===== PARTE 3: gatilhos e restricoes (como dono saas_owner e como superusuario) ====='
SET search_path = saas, public;
DO $$
DECLARE r text; n bigint;
BEGIN
  SET LOCAL ROLE saas_owner;
  BEGIN UPDATE evento_auditoria SET acao='X'; GET DIAGNOSTICS n = ROW_COUNT; r := CASE WHEN n=0 THEN '0 linhas (FORCE RLS do dono: sem politica de UPDATE)' ELSE 'ALTEROU '||n||' (FALHA)' END; EXCEPTION WHEN OTHERS THEN r := 'bloqueado: '||SQLERRM; END;
  RAISE NOTICE 'owner UPDATE evento_auditoria -> %', r;
  BEGIN DELETE FROM evento_auditoria; GET DIAGNOSTICS n = ROW_COUNT; r := CASE WHEN n=0 THEN '0 linhas (FORCE RLS do dono: sem politica de DELETE)' ELSE 'APAGOU '||n||' (FALHA)' END; EXCEPTION WHEN OTHERS THEN r := 'bloqueado: '||SQLERRM; END;
  RAISE NOTICE 'owner DELETE evento_auditoria -> %', r;
  BEGIN TRUNCATE evento_auditoria; r := 'EXECUTOU (FALHA)'; EXCEPTION WHEN OTHERS THEN r := 'bloqueado: '||SQLERRM; END;
  RAISE NOTICE 'owner TRUNCATE evento_auditoria -> %', r;
  BEGIN UPDATE historico_status_encaminhamento SET status_novo='X'; GET DIAGNOSTICS n = ROW_COUNT; r := CASE WHEN n=0 THEN '0 linhas (FORCE RLS do dono)' ELSE 'ALTEROU '||n||' (FALHA)' END; EXCEPTION WHEN OTHERS THEN r := 'bloqueado: '||SQLERRM; END;
  RAISE NOTICE 'owner UPDATE historico -> %', r;
  BEGIN SELECT count(*) INTO n FROM sessao; r := n||' linhas (FALHA se > 0)'; EXCEPTION WHEN OTHERS THEN r := 'bloqueado: '||SQLERRM; END;
  RAISE NOTICE 'owner SELECT sessao -> %', r;
END $$;
RESET ROLE;
DO $$
DECLARE r text;
BEGIN
  BEGIN UPDATE evento_auditoria SET acao='X'; r := 'EXECUTOU (FALHA)'; EXCEPTION WHEN OTHERS THEN r := 'bloqueado: '||SQLERRM; END;
  RAISE NOTICE 'superusuario UPDATE evento_auditoria -> %', r;
  BEGIN DELETE FROM evento_auditoria; r := 'EXECUTOU (FALHA)'; EXCEPTION WHEN OTHERS THEN r := 'bloqueado: '||SQLERRM; END;
  RAISE NOTICE 'superusuario DELETE evento_auditoria -> %', r;
  BEGIN UPDATE encaminhamento SET status='CRIADO' WHERE id='eeeeeeee-0000-0000-0005-000000000006'; r := 'EXECUTOU (FALHA)'; EXCEPTION WHEN OTHERS THEN r := 'bloqueado: '||SQLERRM; END;
  RAISE NOTICE 'superusuario CANCELADO -> CRIADO (estado final) -> %', r;
  BEGIN UPDATE encaminhamento SET motivo_cifrado='\x00' WHERE id='eeeeeeee-0000-0000-0005-000000000001'; r := 'EXECUTOU (FALHA)'; EXCEPTION WHEN OTHERS THEN r := 'bloqueado: '||SQLERRM; END;
  RAISE NOTICE 'superusuario altera motivo_cifrado -> %', r;
  BEGIN UPDATE anexo_encaminhamento SET chave_storage='outra' WHERE id='eeeeeeee-0000-0000-0008-000000000001'; r := 'EXECUTOU (FALHA)'; EXCEPTION WHEN OTHERS THEN r := 'bloqueado: '||SQLERRM; END;
  RAISE NOTICE 'superusuario troca chave_storage de anexo -> %', r;
  BEGIN UPDATE link_paciente SET tentativas_codigo=0 WHERE id='eeeeeeee-0000-0000-0007-000000000000'; r := 'EXECUTOU (FALHA)'; EXCEPTION WHEN OTHERS THEN r := 'bloqueado: '||SQLERRM; END;
  RAISE NOTICE 'superusuario zera tentativas do link -> %', r;
  BEGIN INSERT INTO link_paciente(encaminhamento_id,paciente_id,token_hash,expira_em) VALUES ('eeeeeeee-0000-0000-0005-000000000001','aaaaaaaa-0000-0000-0003-000000000001','\x99',now()+interval '1 day'); r := 'EXECUTOU (FALHA)'; EXCEPTION WHEN OTHERS THEN r := 'bloqueado: '||SQLERRM; END;
  RAISE NOTICE 'superusuario cria segundo link ativo para E1 -> %', r;
END $$;

\echo
\echo '===== INTEGRIDADE: fotografia antes x depois (nenhuma sonda persistiu mudanca) ====='
DO $$
DECLARE t text; h text; difs int := 0;
BEGIN
  FOR t, h IN SELECT s.tab, s.h FROM teste_aux.snap s ORDER BY 1 LOOP
    DECLARE novo text;
    BEGIN
      EXECUTE format('SELECT md5(coalesce(string_agg(x::text, ''|'' ORDER BY x::text),'''')) FROM saas.%I x', t) INTO novo;
      IF novo <> h THEN difs := difs + 1; RAISE NOTICE 'tabela % MUDOU', t; END IF;
    END;
  END LOOP;
  RAISE NOTICE 'tabelas alteradas apos todas as sondas: %', difs;
END $$;
\echo '===== FIM ====='
