-- =====================================================================
-- F4 (gates de banco da Fase 2): R-08, I-21, O3, envios pendentes apos cancelamento, alerta de volume (E-09).
-- Sondas NOVAS do Arquiteto. Alvo: banco migrado pelo Flyway. Executado como superusuario do cluster
-- efemero; papeis reais por \c. As partes que dependem do log do servidor (R-08 e volume) gravam marcas
-- 'ACEITE_MARCA <nome>' com RAISE LOG; o runner le o log entre as marcas.
-- =====================================================================
\set ON_ERROR_STOP on
\set QUIET on
\pset pager off
SET search_path = saas, public;
CREATE SCHEMA aceite;
CREATE TABLE aceite.res(n serial, crit text, descricao text, papel text, esperado text, obtido text, ok boolean);
CREATE TABLE aceite.vistos(papel text, id uuid);
GRANT USAGE ON SCHEMA aceite TO PUBLIC;
GRANT INSERT, SELECT ON aceite.res, aceite.vistos TO PUBLIC;
GRANT USAGE ON SEQUENCE aceite.res_n_seq TO PUBLIC;
CREATE FUNCTION aceite.tenta(q text) RETURNS text LANGUAGE plpgsql AS $$
DECLARE n bigint;
BEGIN EXECUTE q; GET DIAGNOSTICS n = ROW_COUNT; RETURN 'OK n=' || n;
EXCEPTION WHEN OTHERS THEN RETURN 'ERRO: ' || left(replace(SQLERRM, E'\n', ' '), 120); END $$;
CREATE FUNCTION aceite.val(q text) RETURNS text LANGUAGE plpgsql AS $$
DECLARE v text;
BEGIN EXECUTE q INTO v; RETURN coalesce(v, 'NULL');
EXCEPTION WHEN OTHERS THEN RETURN 'ERRO: ' || left(replace(SQLERRM, E'\n', ' '), 120); END $$;
CREATE FUNCTION aceite.reg(crit text, descr text, esperado text, obtido text) RETURNS void LANGUAGE sql AS $$
  INSERT INTO aceite.res(crit, descricao, papel, esperado, obtido, ok)
  VALUES (crit, descr, current_user, esperado, coalesce(obtido, 'NULL'),
    CASE WHEN esperado = 'NEGADO' THEN coalesce(obtido, 'NULL') LIKE 'ERRO%' OR coalesce(obtido, 'NULL') IN ('OK n=0','0','NULL','false','f','')
         WHEN esperado = 'POSITIVO' THEN NOT (coalesce(obtido, 'NULL') LIKE 'ERRO%' OR coalesce(obtido, 'NULL') IN ('OK n=0','0','NULL','false','f',''))
         WHEN esperado LIKE 'IGUAL:%' THEN obtido = substr(esperado, 7)
         WHEN esperado LIKE 'DIFERENTE:%' THEN obtido IS DISTINCT FROM substr(esperado, 11)
    END) $$;
CREATE FUNCTION aceite.marca(nome text) RETURNS void LANGUAGE plpgsql AS $$ BEGIN RAISE LOG 'ACEITE_MARCA %', nome; END $$;

-- ---------------------------------------------------------------------
-- Semente (superusuario)
-- ---------------------------------------------------------------------
\set cA 'a4000000-0000-0000-0000-000000000001'
\set cB 'b4000000-0000-0000-0000-000000000001'
\set esp 'd4000000-0000-0000-0000-000000000001'
\set pcA 'a4000000-0000-0000-0004-000000000001'
INSERT INTO clinica(id,nome) VALUES (:'cA','Clinica F4 A'),(:'cB','Clinica F4 B');
INSERT INTO flag_clinica(clinica_id,chave,ligada) VALUES (:'cA','REDE_ENCAMINHAMENTO',true),(:'cB','REDE_ENCAMINHAMENTO',false);
INSERT INTO especialidade(id,nome) VALUES (:'esp','Ortopedia F4');
INSERT INTO clinica_especialidade VALUES (:'cA',:'esp'),(:'cB',:'esp');
INSERT INTO usuario(id,sub_oidc,nome,email) VALUES
 ('a4000000-0000-0000-0001-000000000002','f4-recA','Rec F4 A','r4@exemplo.invalid'),
 ('a4000000-0000-0000-0001-000000000009','f4-medico','Medico F4 com conta','m4@exemplo.invalid');
INSERT INTO usuario_clinica(usuario_id,clinica_id,papel) VALUES ('a4000000-0000-0000-0001-000000000002',:'cA','RECEPCAO');
-- profissionais: P1 canal verificado; P2 com usuario (sem canal); P3 e P4 sem canal e sem usuario (cadastro nao verificado)
INSERT INTO profissional(id,crm,crm_uf,nome,telefone,canal_verificado_em,usuario_id) VALUES
 ('e4000000-0000-0000-0002-000000000001','F4001','PE','Dra Verificada','+5581999994001',now(),NULL),
 ('e4000000-0000-0000-0002-000000000002','F4002','PE','Dr Com Conta',NULL,NULL,'a4000000-0000-0000-0001-000000000009'),
 ('e4000000-0000-0000-0002-000000000003','F4003','PE','Cadastro Nao Verificado 1','+5581999994003',NULL,NULL),
 ('e4000000-0000-0000-0002-000000000004','F4004','PE','Cadastro Nao Verificado 2','+5581999994004',NULL,NULL);
INSERT INTO profissional_clinica(id,profissional_id,clinica_id,recebe_encaminhamento) VALUES (:'pcA','e4000000-0000-0000-0002-000000000002',:'cA',true);
-- pacientes: PA (cadastro da clinica A) e PV (volume)
INSERT INTO paciente(id,nome,telefone,data_nascimento,cadastrado_por_clinica_id) VALUES
 ('c4000000-0000-0000-0003-000000000001','Paciente F4 A','+5581988884001','1960-01-01',:'cA'),
 ('c4000000-0000-0000-0003-000000000002','Paciente F4 Volume','+5581988884002','1961-01-01',:'cA');
INSERT INTO paciente_clinica(paciente_id,clinica_id) VALUES
 ('c4000000-0000-0000-0003-000000000001',:'cA'),('c4000000-0000-0000-0003-000000000002',:'cA');
-- encaminhamento E1 (CRIADO) de P1 para PA, com link usado e sessao de paciente do caso
INSERT INTO encaminhamento(id,profissional_origem_id,paciente_id,especialidade_destino_id,motivo_cifrado,urgencia,expira_em) VALUES
 ('e4000000-0000-0000-0005-000000000001','e4000000-0000-0000-0002-000000000001','c4000000-0000-0000-0003-000000000001',:'esp','\xf4c1','ROTINA',now()+interval '20 days');
INSERT INTO link_paciente(id,encaminhamento_id,paciente_id,token_hash,expira_em,usado_em) VALUES
 ('e4000000-0000-0000-0007-000000000001','e4000000-0000-0000-0005-000000000001','c4000000-0000-0000-0003-000000000001',sha256(decode(repeat('f4',32),'hex')),now()+interval '1 day',now());
INSERT INTO sessao(token_hash,tipo,usuario_id,expira_em) VALUES
 (sha256(decode(repeat('a4',32),'hex')),'EQUIPE','a4000000-0000-0000-0001-000000000002',now()+interval '2 hours');
INSERT INTO sessao(token_hash,tipo,profissional_id,expira_em) VALUES
 (sha256(decode(repeat('e4',32),'hex')),'ENCAMINHADOR','e4000000-0000-0000-0002-000000000001',now()+interval '2 hours');
INSERT INTO sessao(token_hash,tipo,paciente_id,link_paciente_id,expira_em) VALUES
 (sha256(decode(repeat('c4',32),'hex')),'PACIENTE','c4000000-0000-0000-0003-000000000001','e4000000-0000-0000-0007-000000000001',now()+interval '20 minutes');
-- agendamentos de PA na clinica A: AG1 (sera cancelado pela recepcao), AG3 (continua ativo)
INSERT INTO agendamento(id,clinica_id,profissional_clinica_id,paciente_id,inicio,fim,origem,chave_idempotencia) VALUES
 ('a4000000-0000-0000-0006-000000000001',:'cA',:'pcA','c4000000-0000-0000-0003-000000000001',now()+interval '5 days',now()+interval '5 days 30 minutes','RECEPCAO','f4-ag1'),
 ('a4000000-0000-0000-0006-000000000003',:'cA',:'pcA','c4000000-0000-0000-0003-000000000001',now()+interval '6 days',now()+interval '6 days 30 minutes','RECEPCAO','f4-ag3'),
 ('a4000000-0000-0000-0006-000000000004',:'cA',:'pcA','c4000000-0000-0000-0003-000000000002',now()+interval '7 days',now()+interval '7 days 30 minutes','RECEPCAO','f4-ag4');
-- E2: encaminhamento AGENDADO na clinica A (estado forcado so na fixture, como nas baterias da Fase 1)
SET session_replication_role = replica;
INSERT INTO encaminhamento(id,profissional_origem_id,paciente_id,especialidade_destino_id,clinica_destino_id,motivo_cifrado,urgencia,status,expira_em) VALUES
 ('e4000000-0000-0000-0005-000000000002','e4000000-0000-0000-0002-000000000001','c4000000-0000-0000-0003-000000000001',:'esp',:'cA','\xf4c2','ROTINA','AGENDADO',now()+interval '20 days');
INSERT INTO consentimento(paciente_id,finalidade,encaminhamento_id,clinica_id,texto_aceito,versao_texto,canal) VALUES
 ('c4000000-0000-0000-0003-000000000001','COMPARTILHAR_CASO','e4000000-0000-0000-0005-000000000002',:'cA','t','f4','SITE');
INSERT INTO agendamento(id,clinica_id,profissional_clinica_id,paciente_id,inicio,fim,origem,encaminhamento_id,chave_idempotencia) VALUES
 ('a4000000-0000-0000-0006-000000000002',:'cA',:'pcA','c4000000-0000-0000-0003-000000000001',now()+interval '8 days',now()+interval '8 days 30 minutes','ENCAMINHAMENTO','e4000000-0000-0000-0005-000000000002','f4-ag2');
SET session_replication_role = origin;
-- envios pendentes ligados aos agendamentos (nenhuma funcao os cria ainda; fixture do superusuario)
INSERT INTO envio_notificacao(id,finalidade,canal,destinatario_tipo,destinatario_id,agendamento_id,chave_idempotencia) VALUES
 ('f4000000-0000-0000-0008-000000000001','CONFIRMACAO_AGENDAMENTO','WHATSAPP','PACIENTE','c4000000-0000-0000-0003-000000000001','a4000000-0000-0000-0006-000000000001','f4-c1'),
 ('f4000000-0000-0000-0008-000000000002','LEMBRETE','WHATSAPP','PACIENTE','c4000000-0000-0000-0003-000000000001','a4000000-0000-0000-0006-000000000001','f4-l1'),
 ('f4000000-0000-0000-0008-000000000003','CONFIRMACAO_AGENDAMENTO','WHATSAPP','PACIENTE','c4000000-0000-0000-0003-000000000001','a4000000-0000-0000-0006-000000000003','f4-c3'),
 ('f4000000-0000-0000-0008-000000000004','LEMBRETE','WHATSAPP','PACIENTE','c4000000-0000-0000-0003-000000000001','a4000000-0000-0000-0006-000000000002','f4-l2');
INSERT INTO envio_notificacao(id,finalidade,canal,destinatario_tipo,destinatario_id,agendamento_id,chave_idempotencia)
  SELECT ('f4000000-0000-0000-0009-'||lpad(i::text,12,'0'))::uuid,'LEMBRETE','WHATSAPP','PACIENTE','c4000000-0000-0000-0003-000000000002',
         'a4000000-0000-0000-0006-000000000004','f4-vol-'||lpad(i::text,2,'0')
    FROM generate_series(1,21) i;
\set ON_ERROR_STOP off

-- =====================================================================
-- F4.1 R-08: alerta de DDL pela tabela alvo (o runner confere o log entre as marcas)
-- Cada DDL como saas_owner (a credencial de migracao assume esse papel) e desfeito por ROLLBACK:
-- o alerta tem que ficar no log mesmo assim.
-- =====================================================================
SELECT aceite.marca('R08_A_INICIO');
BEGIN; SET LOCAL ROLE saas_owner; CREATE POLICY aceite_f4_a ON saas.encaminhamento FOR SELECT USING (true); ROLLBACK;
SELECT aceite.marca('R08_A_FIM');
SELECT aceite.marca('R08_B_INICIO');
BEGIN; SET LOCAL ROLE saas_owner; ALTER POLICY encaminhamento_paciente ON saas.encaminhamento USING (true); ROLLBACK;
SELECT aceite.marca('R08_B_FIM');
SELECT aceite.marca('R08_C_INICIO');
BEGIN; SET LOCAL ROLE saas_owner; CREATE TRIGGER aceite_f4_c BEFORE UPDATE ON saas.paciente FOR EACH ROW EXECUTE FUNCTION saas.bloqueia_alteracao(); ROLLBACK;
SELECT aceite.marca('R08_C_FIM');
SELECT aceite.marca('R08_D_INICIO');
BEGIN; SET LOCAL ROLE saas_owner; ALTER TABLE saas.historico_status_encaminhamento DISABLE TRIGGER historico_so_inclusao; ROLLBACK;
SELECT aceite.marca('R08_D_FIM');
SELECT aceite.marca('R08_E_INICIO');
BEGIN; SET LOCAL ROLE saas_owner; ALTER TABLE saas.consentimento NO FORCE ROW LEVEL SECURITY; ROLLBACK;
SELECT aceite.marca('R08_E_FIM');
SELECT aceite.marca('R08_F_INICIO');
BEGIN; SET LOCAL ROLE saas_owner; DROP POLICY encaminhamento_origem ON saas.encaminhamento; ROLLBACK;
SELECT aceite.marca('R08_F_FIM');
SELECT aceite.marca('R08_G_INICIO');
BEGIN; SET LOCAL ROLE saas_owner; CREATE RULE aceite_f4_g AS ON UPDATE TO saas.agendamento DO INSTEAD NOTHING; ROLLBACK;
SELECT aceite.marca('R08_G_FIM');
SELECT aceite.marca('R08_H_INICIO');
BEGIN; SET LOCAL ROLE saas_owner; ALTER POLICY encaminhamento_destino ON saas.encaminhamento RENAME TO aceite_f4_h; ROLLBACK;
SELECT aceite.marca('R08_H_FIM');

-- =====================================================================
-- F4.2 I-21: funcoes SECURITY DEFINER sem sessao nao respondem
-- =====================================================================
\c - saas_app
RESET app.sessao;
SELECT aceite.reg('F4.2','rede_ligada sem sessao para clinica com a rede ligada: negado ou falso','NEGADO',
  aceite.val($$select saas.rede_ligada('a4000000-0000-0000-0000-000000000001')::text$$));
SELECT aceite.reg('F4.2','transicao_cancelamento sem sessao com linha real: nulo','NEGADO',
  aceite.val($$select saas.transicao_cancelamento(e) from saas.encaminhamento e where e.id = 'e4000000-0000-0000-0005-000000000001'$$));
SELECT aceite.reg('F4.2','regressao: consentimento_ativo sem sessao: falso','NEGADO',
  aceite.val($$select saas.consentimento_ativo('e4000000-0000-0000-0005-000000000002','a4000000-0000-0000-0000-000000000001')::text$$));
SELECT aceite.reg('F4.2','regressao: catalogo_rede sem sessao: 0 linhas','IGUAL:0',
  aceite.val($$select count(*)::text from saas.catalogo_rede('d4000000-0000-0000-0000-000000000001')$$));
SELECT set_config('app.sessao', repeat('e4',32), false) \gset
SELECT aceite.reg('F4.2','controle: catalogo_rede com sessao valida lista a clinica com a rede ligada (e so ela)','IGUAL:1',
  aceite.val($$select count(*)::text from saas.catalogo_rede('d4000000-0000-0000-0000-000000000001')$$));
RESET app.sessao;

-- =====================================================================
-- F4.3 O3: profissional sem canal verificado e sem usuario fora da visao publica
-- =====================================================================
SELECT set_config('app.sessao', repeat('c4',32), false) \gset
INSERT INTO aceite.vistos SELECT 'PACIENTE', id FROM saas.profissional;
SELECT set_config('app.sessao', repeat('e4',32), false) \gset
INSERT INTO aceite.vistos SELECT 'ENCAMINHADOR', id FROM saas.profissional;
RESET app.sessao;
\c - pgtest
SET search_path = saas, public;
SELECT aceite.reg('F4.3','sessao de PACIENTE nao ve cadastro nao verificado (sem canal e sem usuario)','IGUAL:0',
  (SELECT count(*)::text FROM aceite.vistos v JOIN profissional p ON p.id = v.id
    WHERE v.papel = 'PACIENTE' AND p.canal_verificado_em IS NULL AND p.usuario_id IS NULL));
SELECT aceite.reg('F4.3','sessao de ENCAMINHADOR nao ve cadastro nao verificado','IGUAL:0',
  (SELECT count(*)::text FROM aceite.vistos v JOIN profissional p ON p.id = v.id
    WHERE v.papel = 'ENCAMINHADOR' AND p.canal_verificado_em IS NULL AND p.usuario_id IS NULL));
SELECT aceite.reg('F4.3','controle: profissional verificado e profissional com conta continuam visiveis ao paciente','IGUAL:2',
  (SELECT count(DISTINCT v.id)::text FROM aceite.vistos v WHERE v.papel = 'PACIENTE'
     AND v.id IN ('e4000000-0000-0000-0002-000000000001','e4000000-0000-0000-0002-000000000002')));

-- =====================================================================
-- F4.4 cancelar agendamento derruba envios CONFIRMACAO e LEMBRETE pendentes
-- =====================================================================
\c - saas_app
SELECT set_config('app.sessao', repeat('a4',32), false), set_config('app.clinica_id', 'a4000000-0000-0000-0000-000000000001', false),
       set_config('app.papel', 'RECEPCAO', false) \gset
SELECT aceite.reg('F4.4','controle: recepcao cancela o agendamento AG1','IGUAL:OK n=1',
  aceite.tenta($$update saas.agendamento set status = 'CANCELADO' where id = 'a4000000-0000-0000-0006-000000000001'$$));
SELECT aceite.reg('F4.4','controle: recepcao cancela o encaminhamento AGENDADO E2 (T11, cancela o agendamento AG2 em cascata)','IGUAL:OK n=1',
  aceite.tenta($$update saas.encaminhamento set status = 'CANCELADO' where id = 'e4000000-0000-0000-0005-000000000002'$$));
\c - saas_jobs
SELECT aceite.reg('F4.4','CONFIRMACAO pendente de agendamento cancelado nao entrega contato','NEGADO',
  aceite.val($$select contato from saas.jobs_envio_prepara('f4000000-0000-0000-0008-000000000001')$$));
SELECT aceite.reg('F4.4','LEMBRETE pendente de agendamento cancelado nao entrega contato','NEGADO',
  aceite.val($$select contato from saas.jobs_envio_prepara('f4000000-0000-0000-0008-000000000002')$$));
SELECT aceite.reg('F4.4','LEMBRETE pendente de agendamento cancelado em cascata (T11) nao entrega contato','NEGADO',
  aceite.val($$select contato from saas.jobs_envio_prepara('f4000000-0000-0000-0008-000000000004')$$));
SELECT aceite.reg('F4.4','controle: CONFIRMACAO de agendamento ativo continua entregando o contato','IGUAL:+5581988884001',
  aceite.val($$select contato from saas.jobs_envio_prepara('f4000000-0000-0000-0008-000000000003')$$));

-- =====================================================================
-- F4.5 E-09: volume de preparos por destinatario vira alerta no log (o runner confere entre as marcas)
-- =====================================================================
\c - pgtest
SELECT aceite.marca('VOL_INICIO');
\c - saas_jobs
DO $$ BEGIN FOR i IN 1..19 LOOP
  PERFORM * FROM saas.jobs_envio_prepara(('f4000000-0000-0000-0009-'||lpad(i::text,12,'0'))::uuid);
END LOOP; END $$;
SELECT aceite.marca('VOL_19');
DO $$ BEGIN FOR i IN 20..21 LOOP
  PERFORM * FROM saas.jobs_envio_prepara(('f4000000-0000-0000-0009-'||lpad(i::text,12,'0'))::uuid);
END LOOP; END $$;
SELECT aceite.marca('VOL_FIM');
\c - pgtest
SET search_path = saas, public;
SELECT aceite.reg('F4.5','controle: os 21 preparos do mesmo destinatario aconteceram','IGUAL:21',
  (SELECT count(*)::text FROM envio_notificacao WHERE chave_idempotencia LIKE 'f4-vol-%' AND status <> 'PENDENTE'));
SELECT crit, ok, esperado, obtido, descricao FROM aceite.res ORDER BY n;
