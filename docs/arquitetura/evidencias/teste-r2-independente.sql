-- =====================================================================
-- teste-r1-independente.sql : casos NOVOS do Testador, rodada 1 (Executor nao viu).
-- Roda como superusuario do cluster descartavel (pgtest); cada sonda troca para o papel de
-- banco com set_config('role') dentro de subtransacao e e DESFEITA. Semente propria.
-- Secoes:
--  P  matriz de privilegios: papel de banco x tabela x SELECT/INSERT/UPDATE/DELETE/TRUNCATE
--     (e coluna a coluna), mais EXECUTE por funcao, comparados com modelo-dados-v2.md
--  S  sessao expirada / revogada / usuario inativo / vinculo inativo / token lixo reutilizados
--  M  maquina de estados: 8 status de origem x 8 de destino x 17 atores, UPDATE direto
--  F  transicoes pelas funcoes (T1..T8) chamadas pelo ator errado e em estado errado
--  B  tentativas de contornar o gatilho (outra coluna, UPDATE de agendamento, DELETE+INSERT,
--     TRUNCATE, GUC saas.transicao, SET ROLE, funcao de gatilho chamada direto)
--  J  papel de jobs: o que ele consegue ler ou provocar
-- Convencao de esperado: ERRO | NEGADO (erro ou 0 linhas) | 0 | POSITIVO (>0) | OK | INFO
-- =====================================================================
\set ON_ERROR_STOP on
\set QUIET on
\pset pager off
\pset format aligned
SET search_path = saas, public;
\o /dev/null
CREATE SCHEMA t;
CREATE TABLE t.res(n serial, secao text, nome text, ctx text, esperado text, obtido text, ok boolean);
CREATE TABLE t.ctx(nome text PRIMARY KEY, tok text, clinica text, papel text);
CREATE FUNCTION t.tok(n text) RETURNS text LANGUAGE sql IMMUTABLE AS $$ SELECT md5('tok-' || n) $$;
GRANT USAGE ON SCHEMA t TO PUBLIC;

-- ---------------------------------------------------------------------
-- Semente (superusuario). Ids fixos legiveis.
-- ---------------------------------------------------------------------
\set cA 'aaaaaaaa-0000-0000-0000-000000000001'
\set cB 'bbbbbbbb-0000-0000-0000-000000000001'
INSERT INTO clinica(id,nome) VALUES (:'cA','Clinica A'),(:'cB','Clinica B');
INSERT INTO flag_clinica(clinica_id,chave,ligada) VALUES (:'cA','REDE_ENCAMINHAMENTO',true),(:'cB','REDE_ENCAMINHAMENTO',true);
INSERT INTO especialidade(id,nome) VALUES ('dddddddd-0000-0000-0000-000000000001','Ortopedia');
INSERT INTO clinica_especialidade VALUES (:'cA','dddddddd-0000-0000-0000-000000000001'),(:'cB','dddddddd-0000-0000-0000-000000000001');

INSERT INTO usuario(id,sub_oidc,nome,email,ativo) VALUES
 ('a0000000-0000-0000-0001-000000000001','admA','AdmA','a@a',true),
 ('a0000000-0000-0000-0001-000000000002','recA','RecA','r@a',true),
 ('a0000000-0000-0000-0001-000000000003','medA','MedA','m@a',true),
 ('a0000000-0000-0000-0001-000000000004','medA2','MedA2','m2@a',true),
 ('b0000000-0000-0000-0001-000000000001','admB','AdmB','a@b',true),
 ('b0000000-0000-0000-0001-000000000002','recB','RecB','r@b',true),
 ('b0000000-0000-0000-0001-000000000003','medB','MedB','m@b',true),
 ('a0000000-0000-0000-0001-000000000008','inatU','InativoU','i@a',false),
 ('a0000000-0000-0000-0001-000000000009','inatUC','InativoUC','i2@a',true);
INSERT INTO usuario_clinica(usuario_id,clinica_id,papel,ativo) VALUES
 ('a0000000-0000-0000-0001-000000000001',:'cA','ADMIN',true),
 ('a0000000-0000-0000-0001-000000000002',:'cA','RECEPCAO',true),
 ('a0000000-0000-0000-0001-000000000003',:'cA','MEDICO',true),
 ('a0000000-0000-0000-0001-000000000004',:'cA','MEDICO',true),
 ('b0000000-0000-0000-0001-000000000001',:'cB','ADMIN',true),
 ('b0000000-0000-0000-0001-000000000002',:'cB','RECEPCAO',true),
 ('b0000000-0000-0000-0001-000000000003',:'cB','MEDICO',true),
 ('a0000000-0000-0000-0001-000000000008',:'cA','ADMIN',true),
 ('a0000000-0000-0000-0001-000000000009',:'cA','ADMIN',false);
INSERT INTO profissional(id,crm,crm_uf,nome,telefone,usuario_id,canal_verificado_em) VALUES
 ('a0000000-0000-0000-0002-000000000003','3','PE','MedA','8130','a0000000-0000-0000-0001-000000000003',now()),
 ('a0000000-0000-0000-0002-000000000004','4','PE','MedA2','8140','a0000000-0000-0000-0001-000000000004',now()),
 ('b0000000-0000-0000-0002-000000000003','13','PE','MedB','8230','b0000000-0000-0000-0001-000000000003',now()),
 ('e0000000-0000-0000-0002-000000000001','101','PE','EncO','8101',NULL,now()),
 ('e0000000-0000-0000-0002-000000000002','102','PE','EncX','8102',NULL,now()),
 ('e0000000-0000-0000-0002-000000000003','103','PE','EncNV','8103',NULL,NULL);
INSERT INTO profissional_clinica(id,profissional_id,clinica_id,recebe_encaminhamento) VALUES
 ('a0000000-0000-0000-0004-000000000003','a0000000-0000-0000-0002-000000000003',:'cA',true),
 ('a0000000-0000-0000-0004-000000000004','a0000000-0000-0000-0002-000000000004',:'cA',true),
 ('b0000000-0000-0000-0004-000000000003','b0000000-0000-0000-0002-000000000003',:'cB',true);
INSERT INTO paciente(id,nome,telefone,cadastrado_por_clinica_id,cpf_cifrado,cpf_hash) VALUES
 ('c0000000-0000-0000-0003-000000000001','PacP','+5581900000001',NULL,'\xaa01','\xbb01'),
 ('c0000000-0000-0000-0003-000000000002','PacQ','+5581900000002',NULL,'\xaa02','\xbb02'),
 ('a0000000-0000-0000-0003-000000000001','PacA','+5581900000011',:'cA','\xaa11','\xbb11'),
 ('b0000000-0000-0000-0003-000000000001','PacB','+5581900000021',:'cB','\xaa21','\xbb21');
INSERT INTO paciente_clinica(paciente_id,clinica_id) VALUES
 ('a0000000-0000-0000-0003-000000000001',:'cA'),('b0000000-0000-0000-0003-000000000001',:'cB');

-- Uma encaminhamento por status (fixture: gatilhos de usuario desligados so aqui).
ALTER TABLE encaminhamento DISABLE TRIGGER USER;
ALTER TABLE contrarreferencia DISABLE TRIGGER USER;
ALTER TABLE agendamento DISABLE TRIGGER USER;
CREATE TABLE t.estados(st text PRIMARY KEY, enc uuid, ord int);
INSERT INTO t.estados VALUES
 ('CRIADO','e1000000-0000-0000-0005-000000000001',1),('ENVIADO_AO_PACIENTE','e1000000-0000-0000-0005-000000000002',2),
 ('SOLICITADO','e1000000-0000-0000-0005-000000000003',3),('AGENDADO','e1000000-0000-0000-0005-000000000004',4),
 ('ATENDIDO','e1000000-0000-0000-0005-000000000005',5),('CONTRARREFERIDO','e1000000-0000-0000-0005-000000000006',6),
 ('EXPIRADO','e1000000-0000-0000-0005-000000000007',7),('CANCELADO','e1000000-0000-0000-0005-000000000008',8);
INSERT INTO encaminhamento(id,profissional_origem_id,paciente_id,especialidade_destino_id,clinica_destino_id,motivo_cifrado,urgencia,status,expira_em)
SELECT e.enc,'e0000000-0000-0000-0002-000000000001','c0000000-0000-0000-0003-000000000001','dddddddd-0000-0000-0000-000000000001',
       CASE WHEN e.ord >= 3 THEN :'cA'::uuid END,'\xcc01','ROTINA',e.st, now() + interval '10 days' FROM t.estados e;
-- origem por MEDICO de B (paciente Q), CRIADO
INSERT INTO encaminhamento(id,profissional_origem_id,paciente_id,especialidade_destino_id,motivo_cifrado,urgencia,status,expira_em)
VALUES ('e1000000-0000-0000-0005-000000000009','b0000000-0000-0000-0002-000000000003','c0000000-0000-0000-0003-000000000002','dddddddd-0000-0000-0000-000000000001','\xcc02','ROTINA','CRIADO',now()+interval '10 days');
INSERT INTO consentimento(paciente_id,finalidade,encaminhamento_id,clinica_id,texto_aceito,versao_texto,canal)
SELECT 'c0000000-0000-0000-0003-000000000001','COMPARTILHAR_CASO',enc,:'cA','ok','v1','SITE' FROM t.estados WHERE ord >= 3;
INSERT INTO paciente_clinica(paciente_id,clinica_id,encaminhamento_id) VALUES
 ('c0000000-0000-0000-0003-000000000001',:'cA','e1000000-0000-0000-0005-000000000004');
INSERT INTO agendamento(id,clinica_id,profissional_clinica_id,paciente_id,inicio,fim,origem,encaminhamento_id,status,chave_idempotencia,status_alterado_por) VALUES
 ('a1000000-0000-0000-0006-000000000004',:'cA','a0000000-0000-0000-0004-000000000003','c0000000-0000-0000-0003-000000000001','2030-01-01 10:00+00','2030-01-01 10:30+00','ENCAMINHAMENTO','e1000000-0000-0000-0005-000000000004','AGENDADO','k4','a0000000-0000-0000-0001-000000000002'),
 ('a1000000-0000-0000-0006-000000000005',:'cA','a0000000-0000-0000-0004-000000000003','c0000000-0000-0000-0003-000000000001','2030-01-02 10:00+00','2030-01-02 10:30+00','ENCAMINHAMENTO','e1000000-0000-0000-0005-000000000005','REALIZADO','k5','a0000000-0000-0000-0001-000000000002'),
 ('a1000000-0000-0000-0006-000000000006',:'cA','a0000000-0000-0000-0004-000000000003','c0000000-0000-0000-0003-000000000001','2030-01-03 10:00+00','2030-01-03 10:30+00','ENCAMINHAMENTO','e1000000-0000-0000-0005-000000000006','REALIZADO','k6','a0000000-0000-0000-0001-000000000002');
INSERT INTO contrarreferencia(encaminhamento_id,clinica_id,autor_profissional_id,conduta_cifrada)
VALUES ('e1000000-0000-0000-0005-000000000006',:'cA','a0000000-0000-0000-0002-000000000003','\xdd01');
INSERT INTO anexo_encaminhamento(encaminhamento_id,tipo_mime,tamanho_bytes,sha256,enviado_por_tipo,enviado_por_id)
VALUES ('e1000000-0000-0000-0005-000000000003','application/pdf',10,'\xee','PROFISSIONAL','e0000000-0000-0000-0002-000000000001');
ALTER TABLE encaminhamento ENABLE TRIGGER USER;
ALTER TABLE contrarreferencia ENABLE TRIGGER USER;
ALTER TABLE agendamento ENABLE TRIGGER USER;

-- Sessoes. Token em claro = t.tok(nome); o banco guarda sha256.
CREATE FUNCTION t.sess(nome text, tipo text, usu uuid, pac uuid, prof uuid, criada interval, dura interval, encerrada boolean DEFAULT false) RETURNS void
LANGUAGE plpgsql AS $$ DECLARE l uuid; d uuid;
BEGIN
  IF tipo = 'PACIENTE' THEN
    INSERT INTO link_paciente(encaminhamento_id,paciente_id,token_hash,expira_em,usado_em)
      VALUES (CASE WHEN pac = 'c0000000-0000-0000-0003-000000000002' THEN 'e1000000-0000-0000-0005-000000000009' ELSE 'e1000000-0000-0000-0005-000000000002' END::uuid,pac,sha256(convert_to('lnk-'||nome,'UTF8')),now()+interval '2 days',now()) RETURNING id INTO l;
  END IF;
  INSERT INTO sessao(token_hash,tipo,usuario_id,paciente_id,profissional_id,link_paciente_id,criada_em,expira_em,encerrada_em)
  VALUES (sha256(decode(t.tok(nome),'hex')),tipo,usu,pac,prof,l,now()-criada,now()-criada+dura,CASE WHEN encerrada THEN now() END);
END $$;
SELECT t.sess('admA','EQUIPE','a0000000-0000-0000-0001-000000000001',NULL,NULL,'1 min','1 hour');
SELECT t.sess('recA','EQUIPE','a0000000-0000-0000-0001-000000000002',NULL,NULL,'1 min','1 hour');
SELECT t.sess('medA','EQUIPE','a0000000-0000-0000-0001-000000000003',NULL,NULL,'1 min','1 hour');
SELECT t.sess('medA2','EQUIPE','a0000000-0000-0000-0001-000000000004',NULL,NULL,'1 min','1 hour');
SELECT t.sess('admB','EQUIPE','b0000000-0000-0000-0001-000000000001',NULL,NULL,'1 min','1 hour');
SELECT t.sess('recB','EQUIPE','b0000000-0000-0000-0001-000000000002',NULL,NULL,'1 min','1 hour');
SELECT t.sess('medB','EQUIPE','b0000000-0000-0000-0001-000000000003',NULL,NULL,'1 min','1 hour');
SELECT t.sess('inatU','EQUIPE','a0000000-0000-0000-0001-000000000008',NULL,NULL,'1 min','1 hour');
SELECT t.sess('inatUC','EQUIPE','a0000000-0000-0000-0001-000000000009',NULL,NULL,'1 min','1 hour');
SELECT t.sess('expirada','EQUIPE','a0000000-0000-0000-0001-000000000001',NULL,NULL,'3 hours','1 hour');
SELECT t.sess('revogada','EQUIPE','a0000000-0000-0000-0001-000000000001',NULL,NULL,'1 min','1 hour',true);
SELECT t.sess('encO','ENCAMINHADOR',NULL,NULL,'e0000000-0000-0000-0002-000000000001','1 min','1 hour');
SELECT t.sess('encX','ENCAMINHADOR',NULL,NULL,'e0000000-0000-0000-0002-000000000002','1 min','1 hour');
SELECT t.sess('pacP','PACIENTE',NULL,'c0000000-0000-0000-0003-000000000001',NULL,'1 min','10 min');
SELECT t.sess('pacQ','PACIENTE',NULL,'c0000000-0000-0000-0003-000000000002',NULL,'1 min','10 min');
SELECT t.sess('pacExp','PACIENTE',NULL,'c0000000-0000-0000-0003-000000000001',NULL,'1 hour','10 min');

INSERT INTO t.ctx(nome,tok,clinica,papel) VALUES
 ('ENC_O',t.tok('encO'),NULL,NULL),
 ('ENC_O_FINGE_ADMIN_A',t.tok('encO'),:'cA','ADMIN'),
 ('ENC_X',t.tok('encX'),NULL,NULL),
 ('PAC_P',t.tok('pacP'),NULL,NULL),
 ('PAC_Q',t.tok('pacQ'),NULL,NULL),
 ('ADM_A',t.tok('admA'),:'cA','ADMIN'),
 ('REC_A',t.tok('recA'),:'cA','RECEPCAO'),
 ('MED_A',t.tok('medA'),:'cA','MEDICO'),
 ('MED_A2',t.tok('medA2'),:'cA','MEDICO'),
 ('ADM_B',t.tok('admB'),:'cB','ADMIN'),
 ('REC_B',t.tok('recB'),:'cB','RECEPCAO'),
 ('MED_B',t.tok('medB'),:'cB','MEDICO'),
 ('REC_A_FINGE_ADMIN',t.tok('recA'),:'cA','ADMIN'),
 ('REC_A_NA_CLIN_B',t.tok('recA'),:'cB','RECEPCAO'),
 ('ADM_B_NA_CLIN_A',t.tok('admB'),:'cA','ADMIN'),
 ('USR_INATIVO',t.tok('inatU'),:'cA','ADMIN'),
 ('VINCULO_INATIVO',t.tok('inatUC'),:'cA','ADMIN'),
 ('SESSAO_EXPIRADA',t.tok('expirada'),:'cA','ADMIN'),
 ('SESSAO_REVOGADA',t.tok('revogada'),:'cA','ADMIN'),
 ('PAC_P_EXPIRADA',t.tok('pacExp'),NULL,NULL),
 ('SEM_SESSAO',NULL,:'cA','ADMIN'),
 ('TOKEN_VAZIO','',:'cA','ADMIN'),
 ('TOKEN_ALEATORIO',t.tok('naoexiste'),:'cA','ADMIN'),
 ('TOKEN_HASH_DA_SESSAO',encode(sha256(decode(t.tok('admA'),'hex')),'hex'),:'cA','ADMIN');

-- fotografia para provar que nada persistiu
CREATE TABLE t.snap(tab text PRIMARY KEY, h text);
CREATE FUNCTION t.foto() RETURNS void LANGUAGE plpgsql AS $$ DECLARE r record; h text;
BEGIN
  DELETE FROM t.snap;
  FOR r IN SELECT tablename FROM pg_tables WHERE schemaname='saas' LOOP
    EXECUTE format('SELECT coalesce(md5(string_agg(x::text,''|'' ORDER BY x::text)),''vazio'') FROM saas.%I x', r.tablename) INTO h;
    INSERT INTO t.snap VALUES (r.tablename,h);
  END LOOP;
END $$;
SELECT t.foto();
CREATE TABLE t.snap0 AS SELECT * FROM t.snap;

-- ---------------------------------------------------------------------
-- Harness. t.run: executa passos como papel+ctx numa subtransacao e desfaz sempre.
-- ---------------------------------------------------------------------
CREATE FUNCTION t.run(rol text, ctxn text, passos text[]) RETURNS text LANGUAGE plpgsql AS $$
DECLARE c t.ctx; s text; n bigint := 0; res text; v text;
BEGIN
  SELECT * INTO c FROM t.ctx WHERE nome = ctxn;
  BEGIN
    PERFORM set_config('role', rol, true);
    IF ctxn IS NOT NULL THEN
      PERFORM set_config('app.sessao', coalesce(c.tok,''), true);
      PERFORM set_config('app.clinica_id', coalesce(c.clinica,''), true);
      PERFORM set_config('app.papel', coalesce(c.papel,''), true);
    END IF;
    FOREACH s IN ARRAY passos LOOP
      EXECUTE s; GET DIAGNOSTICS n = ROW_COUNT;
    END LOOP;
    res := 'OK n=' || n;
    RAISE EXCEPTION USING ERRCODE = 'P0999', MESSAGE = 'desfaz';
  EXCEPTION
    WHEN SQLSTATE 'P0999' THEN NULL;
    WHEN OTHERS THEN res := 'ERRO[' || SQLSTATE || ']: ' || left(replace(SQLERRM, E'\n', ' '), 110);
  END;
  RETURN res;
END $$;

CREATE FUNCTION t.chk(secao text, nome text, ctxn text, rol text, esp text, passos text[]) RETURNS void LANGUAGE plpgsql AS $$
DECLARE r text := t.run(rol, ctxn, passos); n bigint; ok boolean;
BEGIN
  n := coalesce(substring(r from '^OK n=(\d+)')::bigint, -1);
  ok := CASE esp
    WHEN 'ERRO' THEN r LIKE 'ERRO%'
    WHEN 'NEGADO' THEN r LIKE 'ERRO%' OR n = 0
    WHEN '0' THEN n = 0
    WHEN 'POSITIVO' THEN n > 0
    WHEN 'OK' THEN r LIKE 'OK%'
    ELSE true END;
  INSERT INTO t.res(secao,nome,ctx,esperado,obtido,ok) VALUES (secao,nome,ctxn,esp,r,ok);
END $$;
CREATE FUNCTION t.chk(secao text, nome text, ctxn text, rol text, esp text, sql text) RETURNS void LANGUAGE sql AS
$$ SELECT t.chk(secao, nome, ctxn, rol, esp, ARRAY[sql]) $$;
-- resultados de blocos que terminam em ROLLBACK: acumulados em variavel local (variavel plpgsql nao e desfeita)
CREATE FUNCTION t.a(rs jsonb, secao text, nome text, cond boolean, detalhe text DEFAULT '') RETURNS jsonb LANGUAGE sql IMMUTABLE AS
$$ SELECT rs || jsonb_build_array(jsonb_build_object('secao',secao,'nome',nome,'ok',coalesce(cond,false),'obtido',coalesce(cond::text,'NULL')||' '||detalhe)) $$;
CREATE FUNCTION t.flush(rs jsonb) RETURNS void LANGUAGE sql AS
$$ INSERT INTO t.res(secao,nome,ctx,esperado,obtido,ok)
   SELECT x->>'secao', x->>'nome', 'superuser', 'VERDADEIRO', x->>'obtido', (x->>'ok')::boolean FROM jsonb_array_elements(rs) x $$;
-- fixture: executa SQL como superusuario com os gatilhos de encaminhamento desligados so durante o comando
CREATE FUNCTION t.forca(q text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  ALTER TABLE saas.encaminhamento DISABLE TRIGGER USER;
  EXECUTE q;
  ALTER TABLE saas.encaminhamento ENABLE TRIGGER USER;
END $$;
-- afirmacao como superusuario (sem papel): esperado 'POSITIVO' = consulta devolve >0 linhas
CREATE FUNCTION t.afirma(secao text, nome text, cond boolean, detalhe text DEFAULT '') RETURNS void LANGUAGE sql AS
$$ INSERT INTO t.res(secao,nome,ctx,esperado,obtido,ok) VALUES (secao,nome,'superuser','VERDADEIRO',coalesce(cond::text,'NULL')||' '||detalhe,coalesce(cond,false)) $$;

-- =====================================================================
-- teste-r2-independente.sql : Testador, rodada 2. Fixture e harness = os do teste-r1-independente.sql
-- ORIGINAL (rodada 1, sem nenhuma das adaptacoes A1..A6 do Executor).
-- O. As 3 falhas da rodada 1 na FORMA ORIGINAL (blocos copiados sem alteracao do .sql da rodada 1).
--    Blocos DO sem tratamento de erro: se o modelo recusar por excecao, o bloco aborta; o psql
--    segue (ON_ERROR_STOP off) e o ERROR impresso e o resultado esperado.
-- N. Sondas novas da rodada 2.
-- =====================================================================
\set ON_ERROR_STOP off
\o
\echo '##### O.1 S-inativo (original): 4 chk copiados'
\o /dev/null
-- usuario desativado com sessao ainda dentro da validade: politicas que usam so ator_tipo() IS NOT NULL
SELECT t.chk('S-inativo','USR_INATIVO le profissional (politica profissional_ver: ator_tipo() IS NOT NULL)','USR_INATIVO','saas_app','0','select 1 from saas.profissional');
SELECT t.chk('S-inativo','USR_INATIVO le profissional_especialidade','USR_INATIVO','saas_app','0','select 1 from saas.profissional_especialidade');
SELECT t.chk('S-inativo','USR_INATIVO chama catalogo_rede (ator_tipo() IS NOT NULL)','USR_INATIVO','saas_app','0','select * from saas.catalogo_rede(''dddddddd-0000-0000-0000-000000000001'')');
\o
\echo '##### O.2 B-agenda (original, sem tratamento de erro): 2 blocos DO. ERROR abaixo = recusa do modelo'
-- invariante do documento: AGENDADO <=> existe agendamento ativo. Reativar agendamento depois de T7 deixa SOLICITADO com agendamento ativo
DO $$ DECLARE rs jsonb := '[]'; r boolean; st text; n int;
BEGIN BEGIN
  UPDATE saas.agendamento SET status='CANCELADO' WHERE id='a1000000-0000-0000-0006-000000000004';
  PERFORM set_config('role','saas_jobs',true); r := saas.jobs_agendamento_desfeito('a1000000-0000-0000-0006-000000000004'); PERFORM set_config('role','pgtest',true);
  SELECT status INTO st FROM saas.encaminhamento WHERE id='e1000000-0000-0000-0005-000000000004';
  rs := t.a(rs, 'B-agenda','pre: T7 devolveu o encaminhamento a SOLICITADO', st = 'SOLICITADO', st);
  -- recepcao (saas_app) reativa o agendamento cancelado
  PERFORM set_config('role','saas_app',true); PERFORM set_config('app.sessao',t.tok('recA'),true);
  PERFORM set_config('app.clinica_id','aaaaaaaa-0000-0000-0000-000000000001',true); PERFORM set_config('app.papel','RECEPCAO',true);
  UPDATE saas.agendamento SET status='AGENDADO' WHERE id='a1000000-0000-0000-0006-000000000004';
  GET DIAGNOSTICS n = ROW_COUNT;
  PERFORM set_config('role','pgtest',true);
  SELECT e.status INTO st FROM saas.encaminhamento e WHERE e.id='e1000000-0000-0000-0005-000000000004';
  rs := t.a(rs, 'B-agenda','INVARIANTE (maquina-estados, status AGENDADO): encaminhamento SOLICITADO nao pode ter agendamento ativo de origem ENCAMINHAMENTO; REC_A reativou CANCELADO->AGENDADO por UPDATE direto',
    NOT (n = 1 AND st = 'SOLICITADO' AND EXISTS (SELECT 1 FROM saas.agendamento WHERE encaminhamento_id='e1000000-0000-0000-0005-000000000004' AND status IN ('AGENDADO','CONFIRMADO'))),
    'linhas_atualizadas='||n||' status_encaminhamento='||st);
  RAISE EXCEPTION USING ERRCODE='P0998', MESSAGE='desfaz';
EXCEPTION WHEN SQLSTATE 'P0998' THEN NULL;
END;
PERFORM t.flush(rs);
END $$;
-- agendamento REALIZADO voltando a AGENDADO depois de T5
DO $$ DECLARE rs jsonb := '[]'; n int; st text;
BEGIN BEGIN
  PERFORM set_config('role','saas_app',true); PERFORM set_config('app.sessao',t.tok('recA'),true);
  PERFORM set_config('app.clinica_id','aaaaaaaa-0000-0000-0000-000000000001',true); PERFORM set_config('app.papel','RECEPCAO',true);
  UPDATE saas.agendamento SET status='AGENDADO' WHERE id='a1000000-0000-0000-0006-000000000005';
  GET DIAGNOSTICS n = ROW_COUNT;
  PERFORM set_config('role','pgtest',true);
  SELECT status INTO st FROM saas.encaminhamento WHERE id='e1000000-0000-0000-0005-000000000005';
  rs := t.a(rs, 'B-agenda','INVARIANTE: agendamento REALIZADO de encaminhamento ATENDIDO nao deveria voltar a AGENDADO (agenda reaberta apos T5)', NOT (n = 1 AND st = 'ATENDIDO'),
    'linhas_atualizadas='||n||' status_encaminhamento='||st);
  RAISE EXCEPTION USING ERRCODE='P0998', MESSAGE='desfaz';
EXCEPTION WHEN SQLSTATE 'P0998' THEN NULL;
END;
PERFORM t.flush(rs);
END $$;
\echo '##### O.2b: estado dos agendamentos depois dos blocos (nada persistiu)'
SELECT id, status FROM saas.agendamento ORDER BY id;
\echo '##### O.3 J-link (original)'
-- envio PENDENTE criado enquanto CRIADO e consumido depois que o encaminhamento foi CANCELADO: emite link vivo?
DO $$ DECLARE rs jsonb := '[]'; v uuid; r record; n int; st text; c int;
BEGIN BEGIN
  PERFORM set_config('role','saas_jobs',true);
  v := saas.jobs_envio_link_paciente('e1000000-0000-0000-0005-000000000001');
  PERFORM set_config('role','pgtest',true);
  PERFORM set_config('app.sessao',t.tok('encO'),true);
  PERFORM set_config('role','saas_app',true);
  UPDATE saas.encaminhamento SET status='CANCELADO' WHERE id='e1000000-0000-0000-0005-000000000001';       -- T9 legitimo pela origem
  PERFORM set_config('role','saas_jobs',true);
  BEGIN
    SELECT * INTO r FROM saas.jobs_envio_prepara(v);
    PERFORM set_config('role','pgtest',true);
    SELECT status INTO st FROM saas.encaminhamento WHERE id='e1000000-0000-0000-0005-000000000001';
    SELECT count(*) INTO c FROM saas.link_paciente WHERE encaminhamento_id='e1000000-0000-0000-0005-000000000001' AND usado_em IS NULL AND revogado_em IS NULL AND expira_em > now();
    rs := t.a(rs, 'J-link','envio PENDENTE de link NAO pode gerar link vivo (e entregar token + telefone) apos o encaminhamento virar CANCELADO',
      NOT (r.segredo IS NOT NULL AND c = 1), 'encaminhamento='||st||' token_entregue='||(r.segredo IS NOT NULL)||' links_ativos='||c||' contato='||coalesce(r.contato,'-'));
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('role','pgtest',true);
    rs := t.a(rs, 'J-link','envio PENDENTE de link apos CANCELADO e recusado', true, SQLERRM);
  END;
  RAISE EXCEPTION USING ERRCODE='P0998', MESSAGE='desfaz';
EXCEPTION WHEN SQLSTATE 'P0998' THEN NULL;
END;
PERFORM t.flush(rs);
END $$;
-- link ainda vivo depois que o encaminhamento foi CANCELADO pela origem (T9): o paciente ainda abre sessao por ele?
SELECT t.chk('J-link','link nao usado de encaminhamento CANCELADO (T9) ainda e valido em link_consulta','ENC_O','saas_app','0',
  ARRAY['select set_config(''role'',''pgtest'',true)',
        'select t.forca($q$insert into saas.link_paciente(encaminhamento_id,paciente_id,token_hash,expira_em) values (''e1000000-0000-0000-0005-000000000001'',''c0000000-0000-0000-0003-000000000001'',sha256(decode(repeat(''ab'',32),''hex'')),now()+interval ''2 days'')$q$)',
        'select set_config(''role'',''saas_app'',true)',
        'update saas.encaminhamento set status=''CANCELADO'' where id=''e1000000-0000-0000-0005-000000000001''',
        'select * from saas.link_consulta(repeat(''ab'',32))']);
\set ON_ERROR_STOP on
\o /dev/null
-- =====================================================================
-- N. SONDAS NOVAS DA RODADA 2 (identidade do paciente, sessao por caso, cancelamento)
-- =====================================================================
CREATE FUNCTION t.como(rol text, ctxn text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE c t.ctx;
BEGIN PERFORM set_config('role','pgtest',true); SELECT * INTO c FROM t.ctx WHERE nome = ctxn;
  PERFORM set_config('role', rol, true);
  PERFORM set_config('app.sessao', coalesce(c.tok,''), true);
  PERFORM set_config('app.clinica_id', coalesce(c.clinica,''), true);
  PERFORM set_config('app.papel', coalesce(c.papel,''), true);
END $$;
CREATE FUNCTION t.como_tok(rol text, tok text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN PERFORM set_config('role', rol, true); PERFORM set_config('app.sessao', coalesce(tok,''), true);
  PERFORM set_config('app.clinica_id','',true); PERFORM set_config('app.papel','',true);
END $$;
-- cria encaminhamento pelo ator e devolve o paciente_id resultante
CREATE FUNCTION t.cria(ctxn text, nome text, tel text, nasc date, cpf bytea) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE e uuid; p uuid;
BEGIN PERFORM t.como('saas_app', ctxn);
  e := saas.encaminhamento_cria(nome, tel, nasc, CASE WHEN cpf IS NOT NULL THEN '\xaa99'::bytea END, cpf,
        'dddddddd-0000-0000-0000-000000000001', '\xcc99', 'ROTINA');
  PERFORM set_config('role','pgtest',true);
  SELECT paciente_id INTO p FROM saas.encaminhamento WHERE id = e; RETURN p;
END $$;
CREATE FUNCTION t.cadastra(ctxn text, nome text, tel text, nasc date, cpf bytea) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE p uuid;
BEGIN PERFORM t.como('saas_app', ctxn);
  p := saas.paciente_cadastra_na_clinica(nome, tel, nasc, CASE WHEN cpf IS NOT NULL THEN '\xaa98'::bytea END, cpf);
  PERFORM set_config('role','pgtest',true); RETURN p;
END $$;
-- fluxo REAL: link -> codigo -> sessao de paciente do caso (so funcoes dos papeis saas_jobs e saas_app)
CREATE FUNCTION t.abre(enc uuid) RETURNS text LANGUAGE plpgsql AS $$
DECLARE v uuid; vc uuid; r record; tok text; cod text; ok boolean; sess text;
BEGIN
  PERFORM set_config('role','saas_jobs',true);
  v := saas.jobs_envio_link_paciente(enc);
  SELECT * INTO r FROM saas.jobs_envio_prepara(v); tok := r.segredo;
  PERFORM saas.jobs_envio_resultado(v,'ACEITO','p');
  PERFORM set_config('role','saas_app',true); PERFORM set_config('app.sessao','',true);
  ok := saas.paciente_pede_codigo(tok);
  PERFORM set_config('role','saas_jobs',true);
  SELECT envio_id INTO vc FROM saas.jobs_envios_pendentes(100) WHERE finalidade='CODIGO_PACIENTE' LIMIT 1;
  SELECT * INTO r FROM saas.jobs_envio_prepara(vc); cod := r.segredo;
  PERFORM set_config('role','saas_app',true);
  sess := saas.paciente_confirma_codigo(tok, cod);
  PERFORM set_config('role','pgtest',true); RETURN sess;
END $$;
-- estado "vivo" para o teste de cancelamento: link ativo + envio de link + envio de codigo PENDENTES
CREATE FUNCTION t.vivo(enc uuid, tag text, OUT tok text, OUT env_link uuid, OUT env_cod uuid) LANGUAGE plpgsql AS $$
DECLARE lid uuid; pac uuid;
BEGIN
  SELECT paciente_id INTO pac FROM saas.encaminhamento WHERE id = enc;
  tok := t.tok('vivo'||tag);
  INSERT INTO saas.link_paciente(encaminhamento_id,paciente_id,token_hash,expira_em) VALUES (enc,pac,saas.hash_token(tok),now()+interval '2 days') RETURNING id INTO lid;
  INSERT INTO saas.envio_notificacao(finalidade,canal,destinatario_tipo,destinatario_id,encaminhamento_id,chave_idempotencia)
    VALUES ('LINK_PACIENTE','WHATSAPP','PACIENTE',pac,enc,'vL'||tag) RETURNING id INTO env_link;
  INSERT INTO saas.envio_notificacao(finalidade,canal,destinatario_tipo,destinatario_id,encaminhamento_id,link_paciente_id,chave_idempotencia)
    VALUES ('CODIGO_PACIENTE','WHATSAPP','PACIENTE',pac,enc,lid,'vC'||tag) RETURNING id INTO env_cod;
END $$;
-- confere o que o cancelamento deveria ter invalidado
CREATE FUNCTION t.confere(rs jsonb, nome text, enc uuid, tok text, el uuid, ec uuid) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE vivos int; st_l text; st_c text; cons int; pede boolean; conf text; segL text; segC text; st text; sai text := '';
BEGIN
  SELECT count(*) INTO vivos FROM saas.link_paciente WHERE encaminhamento_id=enc AND usado_em IS NULL AND revogado_em IS NULL AND expira_em>now();
  SELECT status INTO st_l FROM saas.envio_notificacao WHERE id=el; SELECT status INTO st_c FROM saas.envio_notificacao WHERE id=ec;
  SELECT status INTO st FROM saas.encaminhamento WHERE id=enc;
  PERFORM set_config('role','saas_app',true); PERFORM set_config('app.sessao','',true);
  SELECT count(*) INTO cons FROM saas.link_consulta(tok);
  pede := saas.paciente_pede_codigo(tok); conf := saas.paciente_confirma_codigo(tok,'000000');
  PERFORM set_config('role','saas_jobs',true);
  BEGIN SELECT segredo INTO segL FROM saas.jobs_envio_prepara(el); EXCEPTION WHEN OTHERS THEN segL := NULL; END;
  BEGIN SELECT segredo INTO segC FROM saas.jobs_envio_prepara(ec); EXCEPTION WHEN OTHERS THEN segC := NULL; END;
  PERFORM set_config('role','pgtest',true);
  RETURN t.a(rs,'N3-cancelamento',nome||': link revogado, envios FALHOU, nenhum segredo/contato sai, link_consulta=0, pede_codigo=false, confirma=NULL',
    vivos=0 AND st_l='FALHOU' AND st_c='FALHOU' AND cons=0 AND NOT pede AND conf IS NULL AND segL IS NULL AND segC IS NULL,
    format('status=%s links_vivos=%s envio_link=%s envio_cod=%s link_consulta=%s pede=%s confirma=%s segredo_link=%s segredo_cod=%s',st,vivos,st_l,st_c,cons,pede,coalesce(conf,'NULL'),coalesce(segL,'NULL'),coalesce(segC,'NULL')));
END $$;

-- ---------------------------------------------------------------------
-- N1. Criterio de identidade do paciente (r2-4)
-- ---------------------------------------------------------------------
DO $$ DECLARE rs jsonb := '[]'; pp uuid := 'c0000000-0000-0000-0003-000000000001'; pa uuid := 'a0000000-0000-0000-0003-000000000001';
  p uuid; nm text; tl text; antes text; depois text;
BEGIN BEGIN
  UPDATE saas.paciente SET data_nascimento='1990-05-05' WHERE id IN (pp, pa);
  SELECT md5(x::text) INTO antes FROM saas.paciente x WHERE id = pp;
  p := t.cria('ENC_O','PacP','+5581900000001','1990-05-05',NULL);        rs := t.a(rs,'N1-identidade','controle: nome+telefone+nascimento iguais, sem CPF, mesmo encaminhador: mesma pessoa', p = pp, p::text);
  p := t.cria('ENC_O','Outro Nome','+5500','1985-01-01','\xbb01');      rs := t.a(rs,'N1-identidade','controle: CPF igual (HMAC) com nome, telefone e nascimento diferentes: mesma pessoa', p = pp, p::text);
  p := t.cria('ENC_O','  PACP  ','+5581900000001','1990-05-05',NULL);   rs := t.a(rs,'N1-identidade','controle: nome com caixa e espacos diferentes: mesma pessoa', p = pp, p::text);
  p := t.cria('ENC_O','PacP','+5581900000001','1990-05-05','\xbb99');   rs := t.a(rs,'N1-identidade','ATAQUE: nome+telefone+nascimento iguais mas CPF DIFERENTE nao funde', p <> pp, p::text);
  p := t.cria('ENC_O','Fulano','+5581900000001','1990-05-05',NULL);     rs := t.a(rs,'N1-identidade','ATAQUE: so o telefone igual nao funde', p <> pp, p::text);
  p := t.cria('ENC_O','PacP','+5581900000001',NULL,NULL);               rs := t.a(rs,'N1-identidade','ATAQUE: sem nascimento e sem CPF nunca deduplica', p <> pp, p::text);
  p := t.cria('ENC_O','PacP','+5581900000001','1991-05-05',NULL);       rs := t.a(rs,'N1-identidade','ATAQUE: nascimento diferente nao funde', p <> pp, p::text);
  p := t.cria('ENC_O','PacP','+5581900000002','1990-05-05',NULL);       rs := t.a(rs,'N1-identidade','ATAQUE: telefone diferente (mesmo nome e nascimento) nao funde', p <> pp, p::text);
  p := t.cria('ENC_X','PacP','+5581900000001','1990-05-05',NULL);       rs := t.a(rs,'N1-identidade','ATAQUE: outro encaminhador (sem vinculo com a paciente) com dados exatos nao funde', p <> pp, p::text);
  p := t.cria('ENC_X','PacP','+5500','1990-05-05','\xbb01');            rs := t.a(rs,'N1-identidade','ATAQUE: outro encaminhador com o CPF dela (sem vinculo) nao funde', p <> pp, p::text);
  p := t.cadastra('REC_B','PacA','+5581900000011','1990-05-05',NULL);   rs := t.a(rs,'N1-identidade','ATAQUE: recepcao da clinica B com dados exatos de paciente da clinica A nao recebe o registro de A', p <> pa, p::text);
  p := t.cadastra('REC_A','PacA','+5581900000011','1990-05-05',NULL);   rs := t.a(rs,'N1-identidade','controle: recepcao da propria clinica, dados exatos: mesma pessoa', p = pa, p::text);
  p := t.cadastra('REC_A','PacA','+5581900000011','1990-05-05','\xbb77'); rs := t.a(rs,'N1-identidade','ATAQUE: recepcao A, dados exatos com CPF diferente: nao funde', p <> pa, p::text);
  SELECT md5(x::text) INTO depois FROM saas.paciente x WHERE id = pp;
  rs := t.a(rs,'N1-identidade','deduplicar nao altera o registro existente (nome, telefone, nascimento, CPF)', antes = depois);
  RAISE EXCEPTION USING ERRCODE='P0998', MESSAGE='desfaz';
EXCEPTION WHEN SQLSTATE 'P0998' THEN NULL;
END;
PERFORM t.flush(rs);
END $$;

-- ---------------------------------------------------------------------
-- N2. Sessao por caso (r2-5, I-19), aberta pelo fluxo REAL link -> codigo -> sessao
-- ---------------------------------------------------------------------
DO $$ DECLARE rs jsonb := '[]'; s1 text; s2 text; eb uuid := 'e1000000-0000-0000-0005-0000000000b1'; n int; ok boolean; msg text;
  e1 uuid := 'e1000000-0000-0000-0005-000000000001'; e2 uuid := 'e1000000-0000-0000-0005-000000000002'; e3 uuid := 'e1000000-0000-0000-0005-000000000003';
  e4 uuid := 'e1000000-0000-0000-0005-000000000004'; cA uuid := 'aaaaaaaa-0000-0000-0000-000000000001';
BEGIN BEGIN
  -- a mesma paciente (P) tem 8 casos; e1 (CRIADO) e um caso novo eb (CRIADO) abrem sessoes pelo fluxo real
  INSERT INTO saas.encaminhamento(id,profissional_origem_id,paciente_id,especialidade_destino_id,motivo_cifrado,urgencia,status,expira_em)
    VALUES (eb,'e0000000-0000-0000-0002-000000000001','c0000000-0000-0000-0003-000000000001','dddddddd-0000-0000-0000-000000000001','\xcc03','ROTINA','CRIADO',now()+interval '10 days');
  s1 := t.abre(e1);
  rs := t.a(rs,'N2-sessao-caso','fluxo real abre sessao de paciente para o caso e1', s1 IS NOT NULL, coalesce(left(s1,6),'NULL'));
  s2 := t.abre(eb);
  rs := t.a(rs,'N2-sessao-caso','fluxo real abre segunda sessao (caso eb) da mesma paciente', s2 IS NOT NULL, coalesce(left(s2,6),'NULL'));
  PERFORM t.como_tok('saas_app', s1);
  SELECT count(*) INTO n FROM saas.encaminhamento;                       rs := t.a(rs,'N2-sessao-caso','sessao do caso e1 ve so 1 encaminhamento (de 9 da mesma paciente)', n = 1, 'n='||n);
  SELECT count(*) INTO n FROM saas.encaminhamento WHERE id = eb;         rs := t.a(rs,'N2-sessao-caso','sessao do caso e1 nao ve o caso eb', n = 0, 'n='||n);
  SELECT count(*) INTO n FROM saas.agendamento;                          rs := t.a(rs,'N2-sessao-caso','sessao e1 nao ve agendamento de outro caso (e4)', n = 0, 'n='||n);
  SELECT count(*) INTO n FROM saas.consentimento;                        rs := t.a(rs,'N2-sessao-caso','sessao e1 nao ve consentimento de outro caso', n = 0, 'n='||n);
  SELECT count(*) INTO n FROM saas.anexo_encaminhamento;                 rs := t.a(rs,'N2-sessao-caso','sessao e1 nao ve anexo de outro caso (e3)', n = 0, 'n='||n);
  SELECT count(*) INTO n FROM saas.historico_status_encaminhamento WHERE encaminhamento_id <> e1; rs := t.a(rs,'N2-sessao-caso','sessao e1 nao ve historico de outro caso', n = 0, 'n='||n);
  SELECT count(*) INTO n FROM saas.contrarreferencia;                    rs := t.a(rs,'N2-sessao-caso','sessao e1 nao ve contrarreferencia de outro caso', n = 0, 'n='||n);
  UPDATE saas.encaminhamento SET status='CANCELADO' WHERE id IN (e3,e4,eb); GET DIAGNOSTICS n = ROW_COUNT;
  rs := t.a(rs,'N2-sessao-caso','sessao e1 nao cancela (T10) outro caso da mesma paciente (e3, e4, eb)', n = 0, 'n='||n);
  UPDATE saas.consentimento SET revogado_em = now() WHERE encaminhamento_id = e3; GET DIAGNOSTICS n = ROW_COUNT;
  rs := t.a(rs,'N2-sessao-caso','sessao e1 nao revoga consentimento de outro caso', n = 0, 'n='||n);
  BEGIN PERFORM saas.paciente_solicita(eb, cA, NULL, 'ok', 'v1'); ok := false; EXCEPTION WHEN OTHERS THEN ok := true; END;
  rs := t.a(rs,'N2-sessao-caso','sessao e1 nao solicita (T3) o caso eb (que esta CRIADO/ENVIADO de outro link)', ok);
  PERFORM t.como_tok('saas_app', s2);
  BEGIN PERFORM saas.paciente_solicita(e1, cA, NULL, 'ok', 'v1'); ok := false; EXCEPTION WHEN OTHERS THEN ok := true; END;
  rs := t.a(rs,'N2-sessao-caso','sessao do caso eb nao solicita o caso e1', ok);
  SELECT count(*) INTO n FROM saas.encaminhamento WHERE id = eb;         rs := t.a(rs,'N2-sessao-caso','controle: sessao eb ve o proprio caso', n = 1, 'n='||n);
  PERFORM t.como_tok('saas_app', s1);
  BEGIN PERFORM saas.paciente_solicita(e1, cA, NULL, 'ok', 'v1'); ok := true; EXCEPTION WHEN OTHERS THEN ok := false; msg := SQLERRM; END;
  rs := t.a(rs,'N2-sessao-caso','controle: sessao e1 solicita o proprio caso e1', ok, coalesce(msg,''));
  -- caso cancelado pela origem: a sessao antiga nao o reabre nem o solicita
  PERFORM t.como('saas_app','ENC_O'); UPDATE saas.encaminhamento SET status='CANCELADO' WHERE id = e1; GET DIAGNOSTICS n = ROW_COUNT;
  rs := t.a(rs,'N2-sessao-caso','pre: origem cancela e1 (T9)', n = 1, 'n='||n);
  PERFORM t.como_tok('saas_app', s1);
  BEGIN UPDATE saas.encaminhamento SET status='SOLICITADO' WHERE id = e1; GET DIAGNOSTICS n = ROW_COUNT; ok := (n = 0); EXCEPTION WHEN OTHERS THEN ok := true; END;
  rs := t.a(rs,'N2-sessao-caso','sessao antiga nao reabre caso CANCELADO por UPDATE', ok);
  BEGIN PERFORM saas.paciente_solicita(e1, cA, NULL, 'ok', 'v1'); ok := false; EXCEPTION WHEN OTHERS THEN ok := true; END;
  rs := t.a(rs,'N2-sessao-caso','sessao antiga nao solicita caso CANCELADO', ok);
  RAISE EXCEPTION USING ERRCODE='P0998', MESSAGE='desfaz';
EXCEPTION WHEN SQLSTATE 'P0998' THEN NULL;
  WHEN OTHERS THEN PERFORM set_config('role','pgtest',true); rs := t.a(rs,'N2-sessao-caso','ERRO INESPERADO no bloco N2', false, SQLERRM);
END;
PERFORM t.flush(rs);
END $$;

-- ---------------------------------------------------------------------
-- N3. Cancelamento (e demais estados finais) invalida link e envio, por todos os caminhos
-- ---------------------------------------------------------------------
-- T9 (origem) em ENVIADO_AO_PACIENTE
DO $$ DECLARE rs jsonb := '[]'; v record; e uuid := 'e1000000-0000-0000-0005-000000000002'; n int; ok boolean;
BEGIN BEGIN
  SELECT * INTO v FROM t.vivo(e,'a');
  PERFORM t.como('saas_app','ENC_O'); UPDATE saas.encaminhamento SET status='CANCELADO' WHERE id=e; GET DIAGNOSTICS n=ROW_COUNT; PERFORM set_config('role','pgtest',true);
  rs := t.a(rs,'N3-cancelamento','pre T9: UPDATE aplicado', n=1);
  rs := t.confere(rs,'T9 (origem) de ENVIADO_AO_PACIENTE', e, v.tok, v.env_link, v.env_cod);
  RAISE EXCEPTION USING ERRCODE='P0998', MESSAGE='desfaz';
EXCEPTION WHEN SQLSTATE 'P0998' THEN NULL; WHEN OTHERS THEN PERFORM set_config('role','pgtest',true); rs := t.a(rs,'N3-cancelamento','ERRO INESPERADO T9', false, SQLERRM); END;
PERFORM t.flush(rs); END $$;
-- T10 (paciente, sessao do proprio caso e2)
DO $$ DECLARE rs jsonb := '[]'; v record; e uuid := 'e1000000-0000-0000-0005-000000000002'; n int; ok boolean;
BEGIN BEGIN
  SELECT * INTO v FROM t.vivo(e,'b');
  PERFORM t.como_tok('saas_app', t.tok('pacP')); UPDATE saas.encaminhamento SET status='CANCELADO' WHERE id=e; GET DIAGNOSTICS n=ROW_COUNT; PERFORM set_config('role','pgtest',true);
  rs := t.a(rs,'N3-cancelamento','pre T10: UPDATE aplicado', n=1);
  rs := t.confere(rs,'T10 (paciente) de ENVIADO_AO_PACIENTE', e, v.tok, v.env_link, v.env_cod);
  RAISE EXCEPTION USING ERRCODE='P0998', MESSAGE='desfaz';
EXCEPTION WHEN SQLSTATE 'P0998' THEN NULL; WHEN OTHERS THEN PERFORM set_config('role','pgtest',true); rs := t.a(rs,'N3-cancelamento','ERRO INESPERADO T10', false, SQLERRM); END;
PERFORM t.flush(rs); END $$;
-- T11 (recepcao do destino) em SOLICITADO e em AGENDADO (cascata do agendamento)
DO $$ DECLARE rs jsonb := '[]'; v record; e uuid; n int; ag text; i int;
BEGIN
  FOR i IN 3..4 LOOP
  BEGIN
    e := ('e1000000-0000-0000-0005-00000000000'||i)::uuid;
    SELECT * INTO v FROM t.vivo(e,'c'||i);
    PERFORM t.como('saas_app','REC_A'); UPDATE saas.encaminhamento SET status='CANCELADO' WHERE id=e; GET DIAGNOSTICS n=ROW_COUNT; PERFORM set_config('role','pgtest',true);
    rs := t.a(rs,'N3-cancelamento','pre T11 e'||i||': UPDATE aplicado', n=1);
    rs := t.confere(rs,'T11 (recepcao destino) de '||CASE i WHEN 3 THEN 'SOLICITADO' ELSE 'AGENDADO' END, e, v.tok, v.env_link, v.env_cod);
    RAISE EXCEPTION USING ERRCODE='P0998', MESSAGE='desfaz';
  EXCEPTION WHEN SQLSTATE 'P0998' THEN NULL; WHEN OTHERS THEN PERFORM set_config('role','pgtest',true); rs := t.a(rs,'N3-cancelamento','ERRO INESPERADO T11 e'||i, false, SQLERRM); END;
  END LOOP;
PERFORM t.flush(rs); END $$;
-- T8 (expiracao pelos jobs) em CRIADO
DO $$ DECLARE rs jsonb := '[]'; v record; e uuid := 'e1000000-0000-0000-0005-000000000001'; n int;
BEGIN BEGIN
  SELECT * INTO v FROM t.vivo(e,'d');
  PERFORM t.forca($q$UPDATE saas.encaminhamento SET expira_em = now() - interval '1 day' WHERE id = 'e1000000-0000-0000-0005-000000000001'$q$);
  PERFORM set_config('role','saas_jobs',true); n := saas.jobs_expirar_encaminhamentos(); PERFORM set_config('role','pgtest',true);
  rs := t.a(rs,'N3-cancelamento','pre T8: job expirou', n >= 1, 'n='||n);
  rs := t.confere(rs,'T8 (expiracao) de CRIADO', e, v.tok, v.env_link, v.env_cod);
  RAISE EXCEPTION USING ERRCODE='P0998', MESSAGE='desfaz';
EXCEPTION WHEN SQLSTATE 'P0998' THEN NULL; WHEN OTHERS THEN PERFORM set_config('role','pgtest',true); rs := t.a(rs,'N3-cancelamento','ERRO INESPERADO T8', false, SQLERRM); END;
PERFORM t.flush(rs); END $$;
-- T6 (contrarreferencia) em ATENDIDO
DO $$ DECLARE rs jsonb := '[]'; v record; e uuid := 'e1000000-0000-0000-0005-000000000005'; n int;
BEGIN BEGIN
  SELECT * INTO v FROM t.vivo(e,'e');
  PERFORM t.como('saas_app','MED_A');
  INSERT INTO saas.contrarreferencia(encaminhamento_id,clinica_id,autor_profissional_id,conduta_cifrada)
    VALUES (e,'aaaaaaaa-0000-0000-0000-000000000001','a0000000-0000-0000-0002-000000000003','\xdd05'); GET DIAGNOSTICS n=ROW_COUNT; PERFORM set_config('role','pgtest',true);
  rs := t.a(rs,'N3-cancelamento','pre T6: contrarreferencia gravada', n=1);
  rs := t.confere(rs,'T6 (contrarreferencia) de ATENDIDO', e, v.tok, v.env_link, v.env_cod);
  RAISE EXCEPTION USING ERRCODE='P0998', MESSAGE='desfaz';
EXCEPTION WHEN SQLSTATE 'P0998' THEN NULL; WHEN OTHERS THEN PERFORM set_config('role','pgtest',true); rs := t.a(rs,'N3-cancelamento','ERRO INESPERADO T6', false, SQLERRM); END;
PERFORM t.flush(rs); END $$;
-- Outras finalidades de envio ligadas ao agendamento/caso: o cancelamento as derruba?
DO $$ DECLARE rs jsonb := '[]'; e uuid := 'e1000000-0000-0000-0005-000000000004'; ag uuid := 'a1000000-0000-0000-0006-000000000004'; pac uuid := 'c0000000-0000-0000-0003-000000000001';
  fin text; ev uuid; st text; r record; n int; ok boolean; i int := 0;
BEGIN
  FOREACH fin IN ARRAY ARRAY['CONFIRMACAO_AGENDAMENTO','LEMBRETE'] LOOP
  BEGIN
    i := i + 1;
    INSERT INTO saas.envio_notificacao(finalidade,canal,destinatario_tipo,destinatario_id,encaminhamento_id,agendamento_id,chave_idempotencia)
      VALUES (fin,'WHATSAPP','PACIENTE',pac,e,ag,'x'||i) RETURNING id INTO ev;
    PERFORM t.como('saas_app','REC_A'); UPDATE saas.encaminhamento SET status='CANCELADO' WHERE id=e; PERFORM set_config('role','pgtest',true);
    SELECT status INTO st FROM saas.envio_notificacao WHERE id=ev;
    PERFORM set_config('role','saas_jobs',true);
    BEGIN SELECT * INTO r FROM saas.jobs_envio_prepara(ev); n := CASE WHEN r.canal IS NULL THEN 0 ELSE 1 END; EXCEPTION WHEN OTHERS THEN n := 0; END;
    PERFORM set_config('role','pgtest',true);
    rs := t.a(rs,'N3-cancelamento','envio '||fin||' PENDENTE de agendamento cancelado (T11) nao pode sair ao paciente', n = 0 OR st = 'FALHOU',
      'status_apos_cancelar='||st||' prepara_devolveu_contato='||(n=1)||' contato='||coalesce(r.contato,'-'));
    RAISE EXCEPTION USING ERRCODE='P0998', MESSAGE='desfaz';
  EXCEPTION WHEN SQLSTATE 'P0998' THEN NULL; WHEN OTHERS THEN PERFORM set_config('role','pgtest',true); rs := t.a(rs,'N3-cancelamento','ERRO INESPERADO '||fin, false, SQLERRM); END;
  END LOOP;
PERFORM t.flush(rs); END $$;
SELECT t.chk('Z','sentinela',NULL,'pgtest','OK','select 1');

-- =====================================================================
-- Integridade: nada persistiu
-- =====================================================================
SELECT t.foto();
SELECT t.afirma('Z-integridade','fotografia de todas as tabelas igual antes e depois das sondas (exceto sessao/link criados por fixture e evento_auditoria)',
  NOT EXISTS (SELECT 1 FROM t.snap a JOIN t.snap0 b USING (tab) WHERE a.h <> b.h AND a.tab NOT IN ('sessao','link_paciente')),
  coalesce((SELECT string_agg(a.tab, ',') FROM t.snap a JOIN t.snap0 b USING (tab) WHERE a.h <> b.h),'nenhuma alterada'));

-- =====================================================================
-- Resultado
-- =====================================================================
\o
\echo '===== RESUMO POR SECAO ====='
SELECT secao, count(*) total, count(*) FILTER (WHERE ok) passou, count(*) FILTER (WHERE NOT ok) falhou FROM t.res GROUP BY 1 ORDER BY 1;
\echo '===== FALHAS (esperado x obtido) ====='
SELECT n, secao, nome, ctx, esperado, obtido FROM t.res WHERE NOT ok ORDER BY n;
\echo '===== INFO ====='
SELECT n, secao, nome, obtido FROM t.res WHERE esperado = 'INFO' ORDER BY n;
SELECT count(*) total, count(*) FILTER (WHERE ok) passou, count(*) FILTER (WHERE NOT ok) falhou FROM t.res;
\echo '===== FIM ====='
\echo '===== RESULTADOS DAS SONDAS NOVAS (N*) e das originais (S-inativo, J-link) ====='
SELECT n, secao, left(nome,150) nome, ok, left(obtido,230) obtido FROM t.res WHERE secao LIKE 'N%' OR secao IN ('S-inativo','J-link','B-agenda') ORDER BY n;
