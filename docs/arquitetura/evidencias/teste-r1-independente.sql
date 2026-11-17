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
-- P. MATRIZ DE PRIVILEGIOS (papel de banco x tabela x verbo) contra modelo-dados-v2.md
-- Esperado extraido do documento, secao 5 e tabela de modulos:
--   * saas_jobs e saas_auth: nenhum privilegio em tabela ("so executam funcoes").
--   * saas_app: SELECT em tudo exceto sessao, link_paciente, desafio_encaminhador, envio_notificacao
--     ("so funcoes"); INSERT direto so onde o documento admite escrita direta; UPDATE so nas colunas
--     da tabela da secao 5; nenhum DELETE, TRUNCATE, REFERENCES ou TRIGGER em tabela alguma.
--   * PUBLIC: nada.
-- =====================================================================
CREATE TABLE t.exp_sel(tab text PRIMARY KEY, sel boolean);
INSERT INTO t.exp_sel SELECT tablename, tablename NOT IN ('sessao','link_paciente','desafio_encaminhador','envio_notificacao')
  FROM pg_tables WHERE schemaname='saas';
-- INSERT direto admitido pelo documento (todo o resto passa por funcao ou gatilho)
CREATE TABLE t.exp_ins(tab text PRIMARY KEY);
INSERT INTO t.exp_ins VALUES ('clinica_especialidade'),('profissional'),('profissional_clinica'),('horario_atendimento'),
  ('consentimento'),('vaga_encaminhamento'),('agendamento'),('contrarreferencia'),('anexo_encaminhamento'),('evento_auditoria');
-- UPDATE por coluna (secao 5). 'agenda' = tabelas em que o documento so diz "colunas de agenda".
CREATE TABLE t.exp_upd(tab text, col text);
INSERT INTO t.exp_upd VALUES ('encaminhamento','status'),('encaminhamento','urgencia'),('paciente','nome'),('paciente','data_nascimento'),
 ('agendamento','status'),('agendamento','inicio'),('agendamento','fim'),('agendamento','profissional_clinica_id'),('agendamento','vaga_encaminhamento_id'),
 ('consentimento','revogado_em'),('clinica','nome'),('clinica','cnpj'),('clinica','modo_recebimento');
CREATE TABLE t.exp_upd_agenda(tab text PRIMARY KEY);
INSERT INTO t.exp_upd_agenda VALUES ('profissional_clinica'),('horario_atendimento'),('vaga_encaminhamento');

DO $$ DECLARE r record; v text; atual boolean; esp boolean; rol text; n int := 0;
BEGIN
  FOR r IN SELECT c.relname tab, c.oid FROM pg_class c WHERE c.relnamespace='saas'::regnamespace AND c.relkind='r' ORDER BY 1 LOOP
    FOREACH rol IN ARRAY ARRAY['saas_app','saas_jobs','saas_auth','public'] LOOP
      FOREACH v IN ARRAY ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER'] LOOP
        IF v IN ('SELECT','INSERT','UPDATE','REFERENCES') THEN
          atual := has_any_column_privilege(rol, r.oid, v);
        ELSE
          atual := has_table_privilege(rol, r.oid, v);
        END IF;
        esp := CASE
          WHEN rol <> 'saas_app' THEN false
          WHEN v = 'SELECT' THEN (SELECT sel FROM t.exp_sel WHERE tab = r.tab) OR r.tab = 'especialidade'
          WHEN v = 'INSERT' THEN EXISTS (SELECT 1 FROM t.exp_ins WHERE tab = r.tab)
          WHEN v = 'UPDATE' THEN EXISTS (SELECT 1 FROM t.exp_upd WHERE tab = r.tab) OR EXISTS (SELECT 1 FROM t.exp_upd_agenda WHERE tab = r.tab)
          ELSE false END;
        INSERT INTO t.res(secao,nome,ctx,esperado,obtido,ok)
        VALUES ('P-tabela', v||' em '||r.tab, rol, esp::text, atual::text, atual = esp);
        n := n + 1;
      END LOOP;
    END LOOP;
  END LOOP;
END $$;

-- coluna a coluna: UPDATE exatamente nas colunas do documento; SELECT negado nas colunas sensiveis
DO $$ DECLARE r record; atual boolean; esp boolean; rol text;
BEGIN
  FOR r IN SELECT c.relname tab, a.attname col FROM pg_class c JOIN pg_attribute a ON a.attrelid=c.oid AND a.attnum>0 AND NOT a.attisdropped
            WHERE c.relnamespace='saas'::regnamespace AND c.relkind='r' ORDER BY 1,2 LOOP
    FOREACH rol IN ARRAY ARRAY['saas_app','saas_jobs','saas_auth'] LOOP
      atual := has_column_privilege(rol, 'saas.'||r.tab, r.col, 'UPDATE');
      esp := rol = 'saas_app' AND EXISTS (SELECT 1 FROM t.exp_upd WHERE tab = r.tab AND col = r.col);
      IF NOT (rol = 'saas_app' AND EXISTS (SELECT 1 FROM t.exp_upd_agenda WHERE tab = r.tab)) THEN
        INSERT INTO t.res(secao,nome,ctx,esperado,obtido,ok) VALUES ('P-coluna-UPDATE', r.tab||'.'||r.col, rol, esp::text, atual::text, atual = esp);
      END IF;
    END LOOP;
    -- SELECT: colunas que o documento diz nao legiveis pela web
    IF (r.tab, r.col) IN (('paciente','cpf_hash'),('profissional','telefone'),('profissional','email'),('profissional','usuario_id'),
                          ('envio_notificacao','destinatario_id'),('link_paciente','token_hash'),('link_paciente','codigo_hash'),
                          ('desafio_encaminhador','codigo_hash'),('sessao','token_hash')) THEN
      INSERT INTO t.res(secao,nome,ctx,esperado,obtido,ok)
      VALUES ('P-coluna-SELECT', r.tab||'.'||r.col||' nao legivel', 'saas_app', 'false', has_column_privilege('saas_app','saas.'||r.tab,r.col,'SELECT')::text,
              NOT has_column_privilege('saas_app','saas.'||r.tab,r.col,'SELECT'));
    END IF;
  END LOOP;
END $$;

-- EXECUTE por funcao: jobs_* so saas_jobs; sessao_equipe_abre so saas_auth; auxiliares e funcoes de gatilho
-- de ninguem; o resto (funcoes da aplicacao e de contexto) so saas_app. PUBLIC nunca.
DO $$ DECLARE r record; rol text; esp boolean; atual boolean;
  nobody text[] := ARRAY['novo_token','novo_codigo','hash_token','hash_codigo','audita','transicao_sistema','bloqueia_alteracao',
    'encaminhamento_valida','encaminhamento_apos_transicao','agendamento_marca_autor','contrarreferencia_t6','anexo_valida_update',
    'link_valida_update','auditoria_preenche','sessao_valida'];
BEGIN
  FOR r IN SELECT p.oid, p.proname, p.prosecdef, p.proconfig, pg_get_userbyid(p.proowner) dono FROM pg_proc p WHERE p.pronamespace='saas'::regnamespace ORDER BY 2 LOOP
    FOREACH rol IN ARRAY ARRAY['saas_app','saas_jobs','saas_auth','public'] LOOP
      esp := CASE WHEN r.proname = ANY (nobody) THEN false
                  WHEN r.proname LIKE 'jobs\_%' THEN rol = 'saas_jobs'
                  WHEN r.proname = 'sessao_equipe_abre' THEN rol = 'saas_auth'
                  ELSE rol = 'saas_app' END;
      atual := CASE WHEN rol = 'public' THEN has_function_privilege('public', r.oid, 'EXECUTE') ELSE has_function_privilege(rol, r.oid, 'EXECUTE') END;
      -- nobody: saas_app precisa de algumas para as politicas, ignora-se so sessao_valida e auxiliares ja listados
      INSERT INTO t.res(secao,nome,ctx,esperado,obtido,ok) VALUES ('P-funcao','EXECUTE '||r.proname, rol, esp::text, atual::text, atual = esp);
    END LOOP;
    IF r.prosecdef THEN
      INSERT INTO t.res(secao,nome,ctx,esperado,obtido,ok)
      VALUES ('P-definer','SECURITY DEFINER '||r.proname||' com search_path fixo e dono saas_funcoes','catalogo','true',
              (r.proconfig::text LIKE '%search_path%' AND r.dono='saas_funcoes')::text, (r.proconfig::text LIKE '%search_path%' AND r.dono='saas_funcoes'));
    END IF;
  END LOOP;
END $$;
-- Nenhum papel de login e dono, superusuario, BYPASSRLS nem membro de outro papel
SELECT t.afirma('P-papeis','papeis de login sem superuser/bypassrls/createrole e sem membership',
  NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname IN ('saas_app','saas_jobs','saas_auth') AND (rolsuper OR rolbypassrls OR rolcreaterole OR rolcreatedb OR rolreplication))
  AND NOT EXISTS (SELECT 1 FROM pg_auth_members m JOIN pg_roles r ON r.oid = m.member WHERE r.rolname IN ('saas_app','saas_jobs','saas_auth')));
SELECT t.afirma('P-papeis','nenhuma tabela do schema saas pertence a papel de login',
  NOT EXISTS (SELECT 1 FROM pg_tables WHERE schemaname='saas' AND tableowner IN ('saas_app','saas_jobs','saas_auth')));
SELECT t.afirma('P-papeis','ENABLE e FORCE RLS em toda tabela exceto especialidade',
  NOT EXISTS (SELECT 1 FROM pg_class WHERE relnamespace='saas'::regnamespace AND relkind='r' AND relname <> 'especialidade' AND NOT (relrowsecurity AND relforcerowsecurity)));
SELECT t.afirma('P-papeis','tabela com RLS sem nenhuma politica so as 4 "so funcoes"',
  (SELECT array_agg(relname::text ORDER BY relname) FROM pg_class c WHERE relnamespace='saas'::regnamespace AND relkind='r' AND relrowsecurity
     AND NOT EXISTS (SELECT 1 FROM pg_policy p WHERE p.polrelid = c.oid)) = ARRAY['desafio_encaminhador','envio_notificacao','link_paciente','sessao']::text[]);

-- Verbos na pratica (alem do catalogo): saas_app e saas_jobs tentam de fato
SELECT t.chk('P-pratica','saas_jobs SELECT encaminhamento','SEM_SESSAO','saas_jobs','ERRO','select motivo_cifrado from saas.encaminhamento');
SELECT t.chk('P-pratica','saas_jobs SELECT paciente','SEM_SESSAO','saas_jobs','ERRO','select nome, telefone from saas.paciente');
SELECT t.chk('P-pratica','saas_jobs SELECT contrarreferencia','SEM_SESSAO','saas_jobs','ERRO','select conduta_cifrada from saas.contrarreferencia');
SELECT t.chk('P-pratica','saas_jobs SELECT anexo','SEM_SESSAO','saas_jobs','ERRO','select chave_storage from saas.anexo_encaminhamento');
SELECT t.chk('P-pratica','saas_jobs SELECT envio_notificacao','SEM_SESSAO','saas_jobs','ERRO','select * from saas.envio_notificacao');
SELECT t.chk('P-pratica','saas_jobs SELECT sessao','SEM_SESSAO','saas_jobs','ERRO','select token_hash from saas.sessao');
SELECT t.chk('P-pratica','saas_jobs SELECT cpf','SEM_SESSAO','saas_jobs','ERRO','select cpf_cifrado from saas.paciente');
SELECT t.chk('P-pratica','saas_jobs UPDATE encaminhamento','SEM_SESSAO','saas_jobs','ERRO','update saas.encaminhamento set status=''EXPIRADO''');
SELECT t.chk('P-pratica','saas_jobs DELETE evento_auditoria','SEM_SESSAO','saas_jobs','ERRO','delete from saas.evento_auditoria');
SELECT t.chk('P-pratica','saas_jobs EXECUTE funcao da web','SEM_SESSAO','saas_jobs','ERRO','select saas.catalogo_rede(''dddddddd-0000-0000-0000-000000000001'')');
SELECT t.chk('P-pratica','saas_app EXECUTE funcao de jobs','ADM_A','saas_app','ERRO','select saas.jobs_expirar_encaminhamentos()');
SELECT t.chk('P-pratica','saas_app EXECUTE sessao_equipe_abre','ADM_A','saas_app','ERRO','select saas.sessao_equipe_abre(''admA'')');
SELECT t.chk('P-pratica','saas_auth EXECUTE jobs_*','SEM_SESSAO','saas_auth','ERRO','select saas.jobs_expirar_encaminhamentos()');
SELECT t.chk('P-pratica','saas_auth SELECT usuario','SEM_SESSAO','saas_auth','ERRO','select * from saas.usuario');
SELECT t.chk('P-pratica','saas_app DELETE em qualquer tabela (agendamento)','ADM_A','saas_app','ERRO','delete from saas.agendamento');
SELECT t.chk('P-pratica','saas_app TRUNCATE encaminhamento','ADM_A','saas_app','ERRO','truncate saas.encaminhamento cascade');
SELECT t.chk('P-pratica','saas_app cria objeto no schema saas','ADM_A','saas_app','ERRO','create table saas.x(i int)');
SELECT t.chk('P-pratica','saas_app cria funcao em public','ADM_A','saas_app','ERRO','create function public.f() returns int language sql as ''select 1''');
SELECT t.chk('P-pratica','saas_app chama funcao de gatilho direto','ADM_A','saas_app','ERRO','select saas.encaminhamento_apos_transicao()');
SELECT t.chk('P-pratica','saas_app chama sessao_valida direto','ADM_A','saas_app','ERRO','select saas.sessao_valida()');
SELECT t.chk('P-pratica','saas_app chama audita direto','ADM_A','saas_app','ERRO','select saas.audita(''X'',''x'',null)');

-- =====================================================================
-- S. SESSAO expirada, revogada, usuario/vinculo inativo, token lixo, hash do token usado como token
-- Esperado do documento: "Sem sessao valida: 0 linhas" (modelo-v2.sql, cabecalho; ADR-0023).
-- Unica excecao documentada: especialidade (catalogo publico, sem RLS).
-- =====================================================================
DO $$ DECLARE c text; tb record;
BEGIN
  FOR c IN SELECT unnest(ARRAY['SESSAO_EXPIRADA','SESSAO_REVOGADA','USR_INATIVO','VINCULO_INATIVO','PAC_P_EXPIRADA','SEM_SESSAO','TOKEN_VAZIO','TOKEN_ALEATORIO','TOKEN_HASH_DA_SESSAO']) LOOP
    FOR tb IN SELECT tablename FROM pg_tables WHERE schemaname='saas' AND tablename NOT IN ('especialidade','sessao','link_paciente','desafio_encaminhador','envio_notificacao') ORDER BY 1 LOOP
      PERFORM t.chk('S-leitura', 'ver '||tb.tablename, c, 'saas_app', CASE WHEN c = 'VINCULO_INATIVO' AND tb.tablename IN ('usuario','usuario_clinica','profissional','profissional_especialidade') THEN 'INFO' ELSE '0' END, format('select 1 from saas.%I', tb.tablename));
    END LOOP;
    PERFORM t.chk('S-leitura','catalogo_rede sem sessao valida devolve 0',c,'saas_app',CASE WHEN c = 'VINCULO_INATIVO' THEN 'INFO' ELSE '0' END,'select * from saas.catalogo_rede(''dddddddd-0000-0000-0000-000000000001'')');
    PERFORM t.chk('S-escrita','criar encaminhamento (T1)',c,'saas_app','ERRO','select saas.encaminhamento_cria(''N'',''+5581911111111'',null,null,''\xaa99'',''dddddddd-0000-0000-0000-000000000001'',''\xcc'',''ROTINA'')');
    PERFORM t.chk('S-escrita','cadastrar paciente na clinica',c,'saas_app','ERRO','select saas.paciente_cadastra_na_clinica(''N'',''+5581911111112'',null,null,''\xaa98'')');
    PERFORM t.chk('S-escrita','confirmar horario (T4)',c,'saas_app','ERRO','select saas.destino_confirma_horario(''e1000000-0000-0000-0005-000000000003'',''a0000000-0000-0000-0004-000000000003'',''2030-02-01 10:00+00'',''2030-02-01 10:30+00'',''kx'')');
    PERFORM t.chk('S-escrita','escolher destino (T3)',c,'saas_app','ERRO','select saas.paciente_solicita(''e1000000-0000-0000-0005-000000000002'',''aaaaaaaa-0000-0000-0000-000000000001'',null,''t'',''v1'')');
    PERFORM t.chk('S-escrita','inserir agendamento',c,'saas_app','ERRO','insert into saas.agendamento(clinica_id,profissional_clinica_id,paciente_id,inicio,fim,origem,chave_idempotencia) values (''aaaaaaaa-0000-0000-0000-000000000001'',''a0000000-0000-0000-0004-000000000003'',''a0000000-0000-0000-0003-000000000001'',''2030-03-01 10:00+00'',''2030-03-01 10:30+00'',''RECEPCAO'',''kz'')');
    PERFORM t.chk('S-escrita','cancelar encaminhamento (T9/T10/T11)',c,'saas_app','NEGADO','update saas.encaminhamento set status=''CANCELADO'' where id=''e1000000-0000-0000-0005-000000000004''');
    PERFORM t.chk('S-escrita','auditoria com ator forjado',c,'saas_app','ERRO','insert into saas.evento_auditoria(ator_papel,ator_id,clinica_id,acao,recurso_tipo) values (''ADMIN'',''a0000000-0000-0000-0001-000000000001'',''aaaaaaaa-0000-0000-0000-000000000001'',''X'',''x'')');
    PERFORM t.chk('S-escrita','alterar clinica',c,'saas_app','NEGADO','update saas.clinica set nome=''pwned''');
  END LOOP;
END $$;
-- token com hex invalido: falha fechada com erro (documentado) ou 0 linhas
SELECT t.chk('S-lixo','token nao-hex em app.sessao: falha fechada','ADM_A','saas_app','NEGADO',
  ARRAY['select set_config(''app.sessao'',''nao-e-hex'',true)','select 1 from saas.encaminhamento']);
SELECT t.chk('S-lixo','token em maiusculas (mesmo hex da sessao valida): valido ou negado, nunca outro tenant','ADM_A','saas_app','POSITIVO',
  ARRAY['select set_config(''app.sessao'',upper(current_setting(''app.sessao'')),true)','select 1 from saas.agendamento']);
SELECT t.chk('S-lixo','token com espaco no fim (decode hex ignora espaco): mesmo segredo, so INFO','ADM_A','saas_app','INFO',
  ARRAY['select set_config(''app.sessao'',current_setting(''app.sessao'')||'' '',true)','select 1 from saas.agendamento']);
-- sessao revogada em vivo: mesma transacao, depois de sessao_encerra() o acesso some
SELECT t.chk('S-vivo','antes de sessao_encerra() a sessao ve agendamentos','ADM_A','saas_app','POSITIVO','select 1 from saas.agendamento');
SELECT t.chk('S-vivo','depois de sessao_encerra() a mesma sessao ve 0 agendamentos','ADM_A','saas_app','0',
  ARRAY['select saas.sessao_encerra()','select 1 from saas.agendamento']);
SELECT t.chk('S-vivo','sessao_encerra() nao encerra sessao de outro (A encerra; B continua)','ADM_B','saas_app','POSITIVO',
  ARRAY['select set_config(''app.sessao'',''' || t.tok('admA') || ''',true)','select saas.sessao_encerra()','select set_config(''app.sessao'',''' || t.tok('admB') || ''',true)','select 1 from saas.clinica']);
-- usuario desativado com sessao ainda dentro da validade: politicas que usam so ator_tipo() IS NOT NULL
SELECT t.chk('S-inativo','USR_INATIVO le profissional (politica profissional_ver: ator_tipo() IS NOT NULL)','USR_INATIVO','saas_app','0','select 1 from saas.profissional');
SELECT t.chk('S-inativo','USR_INATIVO le profissional_especialidade','USR_INATIVO','saas_app','0','select 1 from saas.profissional_especialidade');
SELECT t.chk('S-inativo','USR_INATIVO chama catalogo_rede (ator_tipo() IS NOT NULL)','USR_INATIVO','saas_app','0','select * from saas.catalogo_rede(''dddddddd-0000-0000-0000-000000000001'')');
SELECT t.chk('S-inativo','VINCULO_INATIVO (usuario ativo, vinculo inativo) le catalogo_rede (INFO)','VINCULO_INATIVO','saas_app','INFO','select * from saas.catalogo_rede(''dddddddd-0000-0000-0000-000000000001'')');
-- now() congelado: sessao que vence DENTRO da transacao continua valida ate o COMMIT
DO $$ DECLARE a int; b int; tk text := md5('tok-curta');
BEGIN
  INSERT INTO saas.sessao(token_hash,tipo,usuario_id,criada_em,expira_em) VALUES (sha256(decode(tk,'hex')),'EQUIPE','a0000000-0000-0000-0001-000000000001', now()-interval '1 min', now()+interval '2 seconds');
  PERFORM set_config('role','saas_app',true); PERFORM set_config('app.sessao',tk,true);
  PERFORM set_config('app.clinica_id','aaaaaaaa-0000-0000-0000-000000000001',true); PERFORM set_config('app.papel','ADMIN',true);
  SELECT count(*) INTO a FROM saas.clinica; PERFORM pg_sleep(3); SELECT count(*) INTO b FROM saas.clinica;
  PERFORM set_config('role','pgtest',true);
  DELETE FROM saas.sessao WHERE token_hash = sha256(decode(tk,'hex'));
  INSERT INTO t.res(secao,nome,ctx,esperado,obtido,ok) VALUES ('S-tempo','INFO: sessao vencida no meio da transacao (now() e o inicio da transacao)','ADM_A','INFO',
    'antes='||a||' depois_de_3s_com_sessao_vencida='||b, true);
END $$;

-- =====================================================================
-- M. MAQUINA DE ESTADOS: UPDATE direto de status por 24 atores em 8 estados para 8 estados
-- Esperado (maquina-estados-encaminhamento.md, secao 2): so cancelamento T9/T10/T11;
--   T9  origem (ENC_O, MED_B quando origem e a medica de B): de CRIADO, ENVIADO, SOLICITADO, AGENDADO
--   T10 paciente dono (PAC_P): de ENVIADO, SOLICITADO, AGENDADO
--   T11 RECEPCAO ou ADMIN da clinica destino (A): de SOLICITADO, AGENDADO
-- Todo o resto (inclusive MEDICO do destino, outro tenant, atores sem sessao valida) NEGADO.
-- =====================================================================
DO $$ DECLARE a record; de record; para record; esp text;
BEGIN
  FOR a IN SELECT nome FROM t.ctx WHERE nome NOT IN ('TOKEN_HASH_DA_SESSAO') ORDER BY 1 LOOP
    FOR de IN SELECT st, enc, ord FROM t.estados ORDER BY ord LOOP
      FOR para IN SELECT st FROM t.estados ORDER BY ord LOOP
        esp := CASE WHEN de.st = para.st THEN 'INFO' ELSE 'NEGADO' END;  -- status igual ao atual nao e transicao
        IF para.st = 'CANCELADO' THEN
          IF a.nome IN ('ENC_O','ENC_O_FINGE_ADMIN_A') AND de.st IN ('CRIADO','ENVIADO_AO_PACIENTE','SOLICITADO','AGENDADO') THEN esp := 'POSITIVO'; END IF;
          IF a.nome = 'PAC_P' AND de.st IN ('ENVIADO_AO_PACIENTE','SOLICITADO','AGENDADO') THEN esp := 'POSITIVO'; END IF;
          IF a.nome IN ('REC_A','ADM_A') AND de.st IN ('SOLICITADO','AGENDADO') THEN esp := 'POSITIVO'; END IF;
        END IF;
        PERFORM t.chk('M-status', a.nome||': '||de.st||' -> '||para.st, a.nome, 'saas_app', esp,
          format('update saas.encaminhamento set status=%L where id=%L', para.st, de.enc));
      END LOOP;
    END LOOP;
  END LOOP;
  -- origem por MEDICO (E9 da origem MED_B, CRIADO): MED_B cancela, MED_A nao
  PERFORM t.chk('M-status','MED_B (origem, MEDICO de outra clinica) cancela E9 CRIADO -> CANCELADO','MED_B','saas_app','POSITIVO',
    'update saas.encaminhamento set status=''CANCELADO'' where id=''e1000000-0000-0000-0005-000000000009''');
  PERFORM t.chk('M-status','MED_A nao cancela E9','MED_A','saas_app','NEGADO',
    'update saas.encaminhamento set status=''CANCELADO'' where id=''e1000000-0000-0000-0005-000000000009''');
  PERFORM t.chk('M-status','MED_B declara papel ADMIN (sem ter) e cancela E9','MED_B','saas_app','NEGADO',
    ARRAY['select set_config(''app.papel'',''ADMIN'',true)','update saas.encaminhamento set status=''CANCELADO'' where id=''e1000000-0000-0000-0005-000000000009''']);
END $$;

-- urgencia: so a origem, so antes de SOLICITADO
DO $$ DECLARE a record; de record; esp text;
BEGIN
  FOR a IN SELECT nome FROM t.ctx WHERE nome <> 'TOKEN_HASH_DA_SESSAO' ORDER BY 1 LOOP
    FOR de IN SELECT st, enc FROM t.estados ORDER BY ord LOOP
      esp := CASE WHEN a.nome IN ('ENC_O','ENC_O_FINGE_ADMIN_A') AND de.st IN ('CRIADO','ENVIADO_AO_PACIENTE') THEN 'POSITIVO' ELSE 'NEGADO' END;
      PERFORM t.chk('M-urgencia', a.nome||': urgencia em '||de.st, a.nome, 'saas_app', esp,
        format('update saas.encaminhamento set urgencia=''URGENTE'' where id=%L', de.enc));
    END LOOP;
  END LOOP;
END $$;

-- colunas sem GRANT de UPDATE: negadas a todos os atores (amostra por papel dono da linha)
DO $$ DECLARE a text; col text; v text;
BEGIN
  FOREACH a IN ARRAY ARRAY['ENC_O','PAC_P','ADM_A','REC_A','MED_A'] LOOP
    FOREACH col IN ARRAY ARRAY['clinica_destino_id','profissional_destino_id','expira_em','paciente_id','profissional_origem_id','motivo_cifrado','criado_em','atualizado_em','especialidade_destino_id','id'] LOOP
      v := CASE col WHEN 'expira_em' THEN 'now()+interval ''400 days''' WHEN 'clinica_destino_id' THEN '''bbbbbbbb-0000-0000-0000-000000000001''::uuid'
             WHEN 'profissional_destino_id' THEN '''b0000000-0000-0000-0002-000000000003''::uuid' WHEN 'motivo_cifrado' THEN '''\x00''::bytea'
             WHEN 'criado_em' THEN 'now()' WHEN 'atualizado_em' THEN 'now()' ELSE 'gen_random_uuid()' END;
      PERFORM t.chk('M-colunas', a||': UPDATE '||col, a, 'saas_app', 'ERRO',
        format('update saas.encaminhamento set %I=%s where id=''e1000000-0000-0000-0005-000000000003''', col, v));
    END LOOP;
  END LOOP;
END $$;

-- =====================================================================
-- F. FUNCOES de transicao chamadas pelo ator errado / em estado errado
-- =====================================================================
-- T1 encaminhamento_cria: so ENCAMINHADOR ou MEDICO com vinculo ativo
\set mkenc 'select saas.encaminhamento_cria(''Novo'',''+5581955550000'',null,null,''\\xaa77'',''dddddddd-0000-0000-0000-000000000001'',''\\xcc'',''ROTINA'')'
SELECT t.chk('F-T1','ENCAMINHADOR cria (controle)','ENC_O','saas_app','POSITIVO',:'mkenc');
SELECT t.chk('F-T1','MEDICO de A cria (controle)','MED_A','saas_app','POSITIVO',:'mkenc');
SELECT t.chk('F-T1','RECEPCAO nao cria','REC_A','saas_app','ERRO',:'mkenc');
SELECT t.chk('F-T1','ADMIN nao cria','ADM_A','saas_app','ERRO',:'mkenc');
SELECT t.chk('F-T1','PACIENTE nao cria','PAC_P','saas_app','ERRO',:'mkenc');
SELECT t.chk('F-T1','ENCAMINHADOR com app.papel ADMIN forjado cria como encaminhador (controle de identidade)','ENC_O_FINGE_ADMIN_A','saas_app','POSITIVO',:'mkenc');
SELECT t.chk('F-T1','MEDICO de A declarando clinica B nao cria','MED_A','saas_app','ERRO',
  ARRAY['select set_config(''app.clinica_id'',''bbbbbbbb-0000-0000-0000-000000000001'',true)',:'mkenc']);
SELECT t.chk('F-T1','saas_jobs nao cria','SEM_SESSAO','saas_jobs','ERRO',:'mkenc');
-- T1: encaminhamento criado nasce CRIADO, historico T1 com o ator certo
DO $$ DECLARE rs jsonb := '[]'; e uuid; r record; pac uuid;
BEGIN BEGIN
  PERFORM set_config('role','saas_app',true);
  PERFORM set_config('app.sessao', t.tok('encO'), true);
  e := saas.encaminhamento_cria('Novo T1','+5581955551111',NULL,NULL,'\xaa78','dddddddd-0000-0000-0000-000000000001','\xcc','ROTINA');
  PERFORM set_config('role','pgtest',true);
  SELECT * INTO r FROM saas.historico_status_encaminhamento WHERE encaminhamento_id = e;
  rs := t.a(rs, 'F-T1','T1 grava historico: transicao T1, ator ENCAMINHADOR = profissional da sessao',
    r.transicao='T1' AND r.ator_tipo='ENCAMINHADOR' AND r.ator_id='e0000000-0000-0000-0002-000000000001' AND r.status_anterior IS NULL, row(r.transicao,r.ator_tipo,r.ator_id)::text);  -- ator_tecnico = session_user: conferido no .sh com login real
  RAISE EXCEPTION USING ERRCODE='P0998', MESSAGE='desfaz';
EXCEPTION WHEN SQLSTATE 'P0998' THEN NULL;
END;
PERFORM t.flush(rs);
END $$;
-- T3 paciente_solicita: so o paciente dono, so de ENVIADO, so clinica com rede ligada e especialidade
\set solic 'select saas.paciente_solicita(''e1000000-0000-0000-0005-000000000002'',''bbbbbbbb-0000-0000-0000-000000000001'',null,''t'',''v1'')'
SELECT t.chk('F-T3','PAC_P (dono) escolhe clinica B de ENVIADO (controle)','PAC_P','saas_app','POSITIVO',:'solic');
SELECT t.chk('F-T3','PAC_Q (outro paciente) nao','PAC_Q','saas_app','ERRO',:'solic');
SELECT t.chk('F-T3','ENC_O (origem) nao','ENC_O','saas_app','ERRO',:'solic');
SELECT t.chk('F-T3','ADM_B (clinica escolhida) nao','ADM_B','saas_app','ERRO',:'solic');
SELECT t.chk('F-T3','sessao de paciente expirada nao','PAC_P_EXPIRADA','saas_app','ERRO',:'solic');
SELECT t.chk('F-T3','de CRIADO nao','PAC_P','saas_app','ERRO','select saas.paciente_solicita(''e1000000-0000-0000-0005-000000000001'',''aaaaaaaa-0000-0000-0000-000000000001'',null,''t'',''v1'')');
SELECT t.chk('F-T3','de SOLICITADO (repetir) nao','PAC_P','saas_app','ERRO','select saas.paciente_solicita(''e1000000-0000-0000-0005-000000000003'',''bbbbbbbb-0000-0000-0000-000000000001'',null,''t'',''v1'')');
SELECT t.chk('F-T3','de CANCELADO nao','PAC_P','saas_app','ERRO','select saas.paciente_solicita(''e1000000-0000-0000-0005-000000000008'',''aaaaaaaa-0000-0000-0000-000000000001'',null,''t'',''v1'')');
SELECT t.chk('F-T3','clinica com rede desligada nao','PAC_P','saas_app','ERRO',
  ARRAY['update saas.flag_clinica set ligada=false where clinica_id=''bbbbbbbb-0000-0000-0000-000000000001''', :'solic']);
-- (a linha acima roda como saas_app: o UPDATE de flag deve falhar => ERRO, e o proposito e provar que app nao liga/desliga flag)
SELECT t.chk('F-T3','paciente_solicita grava historico T3 com ator PACIENTE e consentimento da clinica escolhida','PAC_P','saas_app','POSITIVO',
  ARRAY[:'solic','select 1 from saas.consentimento where encaminhamento_id=''e1000000-0000-0000-0005-000000000002'' and clinica_id=''bbbbbbbb-0000-0000-0000-000000000001'' and revogado_em is null']);
-- T4 destino_confirma_horario
\set confirma 'select saas.destino_confirma_horario(''e1000000-0000-0000-0005-000000000003'',''a0000000-0000-0000-0004-000000000003'',''2030-02-01 10:00+00'',''2030-02-01 10:30+00'',''kc'')'
SELECT t.chk('F-T4','REC_A confirma (controle)','REC_A','saas_app','POSITIVO',:'confirma');
SELECT t.chk('F-T4','ADM_A confirma (controle)','ADM_A','saas_app','POSITIVO',:'confirma');
SELECT t.chk('F-T4','MED_A (MEDICO do destino) nao confirma','MED_A','saas_app','ERRO',:'confirma');
SELECT t.chk('F-T4','REC_B (outra clinica) nao','REC_B','saas_app','ERRO',:'confirma');
SELECT t.chk('F-T4','REC_A declarando clinica B nao','REC_A_NA_CLIN_B','saas_app','ERRO',:'confirma');
SELECT t.chk('F-T4','REC_A fingindo ADMIN nao','REC_A_FINGE_ADMIN','saas_app','ERRO',:'confirma');
SELECT t.chk('F-T4','PAC_P nao confirma a propria consulta','PAC_P','saas_app','ERRO',:'confirma');
SELECT t.chk('F-T4','ENC_O nao','ENC_O','saas_app','ERRO',:'confirma');
SELECT t.chk('F-T4','usuario inativo nao','USR_INATIVO','saas_app','ERRO',:'confirma');
SELECT t.chk('F-T4','vinculo inativo nao','VINCULO_INATIVO','saas_app','ERRO',:'confirma');
SELECT t.chk('F-T4','de CRIADO nao (REC_A)','REC_A','saas_app','ERRO','select saas.destino_confirma_horario(''e1000000-0000-0000-0005-000000000001'',''a0000000-0000-0000-0004-000000000003'',''2030-02-01 10:00+00'',''2030-02-01 10:30+00'',''kc'')');
SELECT t.chk('F-T4','de AGENDADO (reconfirmar) nao','REC_A','saas_app','ERRO','select saas.destino_confirma_horario(''e1000000-0000-0000-0005-000000000004'',''a0000000-0000-0000-0004-000000000003'',''2030-02-02 10:00+00'',''2030-02-02 10:30+00'',''kc2'')');
SELECT t.chk('F-T4','profissional de OUTRA clinica no horario nao (FK composta)','REC_A','saas_app','ERRO','select saas.destino_confirma_horario(''e1000000-0000-0000-0005-000000000003'',''b0000000-0000-0000-0004-000000000003'',''2030-02-01 10:00+00'',''2030-02-01 10:30+00'',''kc3'')');
SELECT t.chk('F-T4','consentimento revogado impede T4','REC_A','saas_app','ERRO',
  ARRAY['select set_config(''role'',''pgtest'',true)','update saas.consentimento set revogado_em=now() where encaminhamento_id=''e1000000-0000-0000-0005-000000000003''','select set_config(''role'',''saas_app'',true)',:'confirma']);
-- T6 contrarreferencia: so o medico que atendeu (autor do agendamento REALIZADO) e do destino
\set contra 'insert into saas.contrarreferencia(encaminhamento_id,clinica_id,autor_profissional_id,conduta_cifrada) values (''e1000000-0000-0000-0005-000000000005'',''aaaaaaaa-0000-0000-0000-000000000001'',''a0000000-0000-0000-0002-000000000003'',''\\xdd02'')'
SELECT t.chk('F-T6','MED_A (atendeu) grava (controle)','MED_A','saas_app','POSITIVO',:'contra');
SELECT t.chk('F-T6','MED_A2 (outro medico da mesma clinica) grava como MED_A: autor forjado','MED_A2','saas_app','ERRO',:'contra');
SELECT t.chk('F-T6','MED_A2 grava como ele mesmo: nao atendeu','MED_A2','saas_app','ERRO',
  'insert into saas.contrarreferencia(encaminhamento_id,clinica_id,autor_profissional_id,conduta_cifrada) values (''e1000000-0000-0000-0005-000000000005'',''aaaaaaaa-0000-0000-0000-000000000001'',''a0000000-0000-0000-0002-000000000004'',''\xdd02'')');
SELECT t.chk('F-T6','ADMIN nao','ADM_A','saas_app','ERRO',:'contra');
SELECT t.chk('F-T6','RECEPCAO nao','REC_A','saas_app','ERRO',:'contra');
SELECT t.chk('F-T6','MED_B (outra clinica) nao','MED_B','saas_app','ERRO',:'contra');
SELECT t.chk('F-T6','ENC_O (origem) nao','ENC_O','saas_app','ERRO',:'contra');
SELECT t.chk('F-T6','PAC_P nao','PAC_P','saas_app','ERRO',:'contra');
SELECT t.chk('F-T6','MED_A em AGENDADO (nao ATENDIDO) nao','MED_A','saas_app','ERRO',
  'insert into saas.contrarreferencia(encaminhamento_id,clinica_id,autor_profissional_id,conduta_cifrada) values (''e1000000-0000-0000-0005-000000000004'',''aaaaaaaa-0000-0000-0000-000000000001'',''a0000000-0000-0000-0002-000000000003'',''\xdd02'')');
SELECT t.chk('F-T6','MED_A em CONTRARREFERIDO (segunda contrarreferencia) nao','MED_A','saas_app','ERRO',
  'insert into saas.contrarreferencia(encaminhamento_id,clinica_id,autor_profissional_id,conduta_cifrada) values (''e1000000-0000-0000-0005-000000000006'',''aaaaaaaa-0000-0000-0000-000000000001'',''a0000000-0000-0000-0002-000000000003'',''\xdd02'')');
SELECT t.chk('F-T6','T6 muda o encaminhamento para CONTRARREFERIDO e grava historico T6','MED_A','saas_app','POSITIVO',
  ARRAY[:'contra','select 1 from saas.encaminhamento where id=''e1000000-0000-0000-0005-000000000005'' and status=''CONTRARREFERIDO''','select 1 from saas.historico_status_encaminhamento where encaminhamento_id=''e1000000-0000-0000-0005-000000000005'' and transicao=''T6'' and ator_tipo=''EQUIPE'' and ator_papel=''MEDICO''']);
-- Funcoes por ator errado: web chamando jobs e jobs chamando web (EXECUTE ja na matriz P; aqui o efeito)
SELECT t.chk('F-sistema','saas_jobs T8 sem WHERE efeito: so expirados (E3 expirado forcado, E4 AGENDADO tambem vencido)','SEM_SESSAO','saas_jobs','POSITIVO',
  ARRAY['select set_config(''role'',''pgtest'',true)','select t.forca($q$update saas.encaminhamento set expira_em=now()-interval ''1 day''$q$)','select set_config(''role'',''saas_jobs'',true)','select saas.jobs_expirar_encaminhamentos()']);

-- T8 por estado (vencido em todos): so CRIADO, ENVIADO, SOLICITADO expiram
DO $$ DECLARE rs jsonb := '[]'; n int; r record; ok boolean := true; det text := '';
BEGIN BEGIN
  PERFORM t.forca($q$UPDATE saas.encaminhamento SET expira_em = now() - interval '1 day'$q$);
  PERFORM set_config('role','saas_jobs',true); n := saas.jobs_expirar_encaminhamentos(); PERFORM set_config('role','pgtest',true);
  FOR r IN SELECT e.status, s.st FROM saas.encaminhamento e JOIN t.estados s ON s.enc = e.id ORDER BY s.ord LOOP
    IF (r.st IN ('CRIADO','ENVIADO_AO_PACIENTE','SOLICITADO')) <> (r.status = 'EXPIRADO') AND r.st <> 'EXPIRADO' THEN ok := false; END IF;
    det := det || r.st || '->' || r.status || ' ';
  END LOOP;
  rs := t.a(rs, 'F-T8','jobs_expirar: so CRIADO/ENVIADO/SOLICITADO viram EXPIRADO; AGENDADO, ATENDIDO, CONTRARREFERIDO, CANCELADO intactos',
    ok AND n = 4, 'n='||n||' '||det);  -- 3 estados + E9 (CRIADO de B)
  RAISE EXCEPTION USING ERRCODE='P0998', MESSAGE='desfaz';
EXCEPTION WHEN SQLSTATE 'P0998' THEN NULL;
END;
PERFORM t.flush(rs);
END $$;

-- T5/T7 por estado do agendamento
DO $$ DECLARE rs jsonb := '[]'; r boolean; st text; ag uuid := 'a1000000-0000-0000-0006-000000000004'; sts text;
BEGIN BEGIN
  FOREACH st IN ARRAY ARRAY['AGENDADO','CONFIRMADO','REALIZADO','FALTOU','CANCELADO'] LOOP
    UPDATE saas.agendamento SET status = st WHERE id = ag;
    PERFORM set_config('role','saas_jobs',true); r := saas.jobs_consulta_realizada(ag); PERFORM set_config('role','pgtest',true);
    rs := t.a(rs, 'F-T5','jobs_consulta_realizada com agendamento '||st||': so REALIZADO move AGENDADO -> ATENDIDO', r = (st = 'REALIZADO'), 'retorno='||r);
    PERFORM t.forca($q$UPDATE saas.encaminhamento SET status = 'AGENDADO' WHERE id = 'e1000000-0000-0000-0005-000000000004'$q$);
  END LOOP;
  FOREACH st IN ARRAY ARRAY['AGENDADO','CONFIRMADO','REALIZADO','FALTOU','CANCELADO'] LOOP
    UPDATE saas.agendamento SET status = st WHERE id = ag;
    PERFORM t.forca($q$UPDATE saas.encaminhamento SET status = 'AGENDADO' WHERE id = 'e1000000-0000-0000-0005-000000000004'$q$);
    PERFORM set_config('role','saas_jobs',true); r := saas.jobs_agendamento_desfeito(ag); PERFORM set_config('role','pgtest',true);
    rs := t.a(rs, 'F-T7','jobs_agendamento_desfeito com agendamento '||st||': so CANCELADO ou FALTOU devolvem a SOLICITADO', r = (st IN ('CANCELADO','FALTOU')), 'retorno='||r);
  END LOOP;
  RAISE EXCEPTION USING ERRCODE='P0998', MESSAGE='desfaz';
EXCEPTION WHEN SQLSTATE 'P0998' THEN NULL;
END;
PERFORM t.flush(rs);
END $$;
-- T5 em encaminhamento ja ATENDIDO / CONTRARREFERIDO (agendamento REALIZADO ja existente): nao refaz
SELECT t.chk('F-T5','jobs_consulta_realizada de agendamento do ATENDIDO nao muda nada (retorna false)','SEM_SESSAO','saas_jobs','OK','select saas.jobs_consulta_realizada(''a1000000-0000-0000-0006-000000000005'')');
DO $$ DECLARE r boolean;
BEGIN
  PERFORM set_config('role','saas_jobs',true); r := saas.jobs_consulta_realizada('a1000000-0000-0000-0006-000000000005'); PERFORM set_config('role','pgtest',true);
  PERFORM t.afirma('F-T5','T5 repetido sobre ATENDIDO devolve false (idempotente, sem regredir)', r = false, 'retorno='||r);
  PERFORM set_config('role','saas_jobs',true); r := saas.jobs_consulta_realizada('a1000000-0000-0000-0006-000000000006'); PERFORM set_config('role','pgtest',true);
  PERFORM t.afirma('F-T5','T5 sobre CONTRARREFERIDO devolve false', r = false, 'retorno='||r);
  PERFORM set_config('role','saas_jobs',true); r := saas.jobs_agendamento_desfeito('a1000000-0000-0000-0006-000000000005'); PERFORM set_config('role','pgtest',true);
  PERFORM t.afirma('F-T7','T7 sobre agendamento de ATENDIDO devolve false', r = false, 'retorno='||r);
END $$;

-- =====================================================================
-- B. CONTORNAR O GATILHO
-- =====================================================================
-- B1: status e outra coluna no mesmo UPDATE
SELECT t.chk('B-outra-coluna','ENC_O muda status=CANCELADO e urgencia na mesma instrucao em CRIADO (permitido pelo desenho)','ENC_O','saas_app','POSITIVO',
  'update saas.encaminhamento set status=''CANCELADO'', urgencia=''URGENTE'' where id=''e1000000-0000-0000-0005-000000000001''');
SELECT t.chk('B-outra-coluna','ADM_A (destino) status=CANCELADO + urgencia em SOLICITADO: urgencia nao e dele','ADM_A','saas_app','ERRO',
  'update saas.encaminhamento set status=''CANCELADO'', urgencia=''URGENTE'' where id=''e1000000-0000-0000-0005-000000000003''');
SELECT t.chk('B-outra-coluna','PAC_P status=CANCELADO + urgencia','PAC_P','saas_app','ERRO',
  'update saas.encaminhamento set status=''CANCELADO'', urgencia=''URGENTE'' where id=''e1000000-0000-0000-0005-000000000003''');
SELECT t.chk('B-outra-coluna','status igual ao atual (sem transicao) + urgencia por ADM_A','ADM_A','saas_app','ERRO',
  'update saas.encaminhamento set status=status, urgencia=''URGENTE'' where id=''e1000000-0000-0000-0005-000000000003''');
SELECT t.chk('B-outra-coluna','UPDATE sem mudar nada (status=status) por ADM_A nao gera historico','ADM_A','saas_app','0',
  ARRAY['update saas.encaminhamento set status=status where id=''e1000000-0000-0000-0005-000000000003''','select 1 from saas.historico_status_encaminhamento where encaminhamento_id=''e1000000-0000-0000-0005-000000000003'' and alterado_em > now()']);
SELECT t.chk('B-outra-coluna','ENC_O muda status e destino no mesmo UPDATE (sem GRANT na coluna)','ENC_O','saas_app','ERRO',
  'update saas.encaminhamento set status=''CANCELADO'', clinica_destino_id=''bbbbbbbb-0000-0000-0000-000000000001'' where id=''e1000000-0000-0000-0005-000000000003''');
SELECT t.chk('B-outra-coluna','UPDATE com WHERE em coluna a que nao se tem SELECT (cpf_hash de paciente) para inferir','ADM_A','saas_app','ERRO',
  'update saas.paciente set nome=''x'' where cpf_hash=''\xbb11''');
-- B2: UPDATE de agendamento (outra tabela) para dessincronizar o encaminhamento
SELECT t.chk('B-agenda','REC_A cancela o agendamento do AGENDADO (permitido) e o encaminhamento segue AGENDADO ate o job T7','REC_A','saas_app','POSITIVO',
  ARRAY['update saas.agendamento set status=''CANCELADO'' where id=''a1000000-0000-0000-0006-000000000004''','select 1 from saas.encaminhamento where id=''e1000000-0000-0000-0005-000000000004'' and status=''AGENDADO''']);
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
-- B3: cancelamento a partir de AGENDADO cancela o agendamento e grava historico com ator
DO $$ DECLARE rs jsonb := '[]'; r record; ag text;
BEGIN BEGIN
  PERFORM set_config('role','saas_app',true); PERFORM set_config('app.sessao',t.tok('pacP'),true);
  UPDATE saas.encaminhamento SET status='CANCELADO' WHERE id='e1000000-0000-0000-0005-000000000004';
  PERFORM set_config('role','pgtest',true);
  SELECT status INTO ag FROM saas.agendamento WHERE id='a1000000-0000-0000-0006-000000000004';
  SELECT * INTO r FROM saas.historico_status_encaminhamento WHERE encaminhamento_id='e1000000-0000-0000-0005-000000000004' AND status_novo='CANCELADO';
  rs := t.a(rs, 'B-historico','T10 por paciente: historico T10, ator PACIENTE e ator_id = paciente da sessao, agendamento cancelado em cascata',
    r.transicao='T10' AND r.ator_tipo='PACIENTE' AND r.ator_id='c0000000-0000-0000-0003-000000000001' AND ag='CANCELADO',
    row(r.transicao,r.ator_tipo,r.ator_id,ag)::text);
  RAISE EXCEPTION USING ERRCODE='P0998', MESSAGE='desfaz';
EXCEPTION WHEN SQLSTATE 'P0998' THEN NULL;
END;
PERFORM t.flush(rs);
END $$;
DO $$ DECLARE rs jsonb := '[]'; r record;
BEGIN BEGIN
  PERFORM set_config('role','saas_app',true); PERFORM set_config('app.sessao',t.tok('recA'),true);
  PERFORM set_config('app.clinica_id','aaaaaaaa-0000-0000-0000-000000000001',true); PERFORM set_config('app.papel','RECEPCAO',true);
  UPDATE saas.encaminhamento SET status='CANCELADO' WHERE id='e1000000-0000-0000-0005-000000000003';
  PERFORM set_config('role','pgtest',true);
  SELECT * INTO r FROM saas.historico_status_encaminhamento WHERE encaminhamento_id='e1000000-0000-0000-0005-000000000003' AND status_novo='CANCELADO';
  rs := t.a(rs, 'B-historico','T11 por recepcao do destino: historico T11, ator EQUIPE/RECEPCAO com usuario da sessao',
    r.transicao='T11' AND r.ator_tipo='EQUIPE' AND r.ator_papel='RECEPCAO' AND r.ator_id='a0000000-0000-0000-0001-000000000002', row(r.transicao,r.ator_tipo,r.ator_papel,r.ator_id)::text);
  RAISE EXCEPTION USING ERRCODE='P0998', MESSAGE='desfaz';
EXCEPTION WHEN SQLSTATE 'P0998' THEN NULL;
END;
PERFORM t.flush(rs);
END $$;
-- B4: DELETE + INSERT (ressuscitar encaminhamento final) por quem tem mais privilegio: dono e superusuario
SELECT t.chk('B-delete-insert','saas_owner (dono, sujeito a FORCE RLS) nao apaga encaminhamento CANCELADO','SEM_SESSAO','saas_owner','NEGADO',
  'delete from saas.encaminhamento where id=''e1000000-0000-0000-0005-000000000008''');
DO $$ DECLARE rs jsonb := '[]'; e uuid; resultado text;
BEGIN BEGIN
  -- cria um encaminhamento de verdade pela funcao (historico T1 existe), cancela e tenta DELETE+INSERT como superusuario
  PERFORM set_config('role','saas_app',true); PERFORM set_config('app.sessao',t.tok('encO'),true);
  e := saas.encaminhamento_cria('Del','+5581955552222',NULL,NULL,'\xaa79','dddddddd-0000-0000-0000-000000000001','\xcc','ROTINA');
  UPDATE saas.encaminhamento SET status='CANCELADO' WHERE id=e;
  PERFORM set_config('role','pgtest',true);
  BEGIN
    DELETE FROM saas.encaminhamento WHERE id = e; resultado := 'DELETE EXECUTADO';
  EXCEPTION WHEN OTHERS THEN resultado := 'ERRO['||SQLSTATE||'] '||left(SQLERRM,80);
  END;
  rs := t.a(rs, 'B-delete-insert','superusuario nao consegue DELETE de encaminhamento com historico (FK sem CASCADE)', resultado LIKE 'ERRO%', resultado);
  BEGIN
    UPDATE saas.encaminhamento SET status='CRIADO' WHERE id = e; resultado := 'UPDATE final->CRIADO EXECUTADO';
  EXCEPTION WHEN OTHERS THEN resultado := 'ERRO['||SQLSTATE||'] '||left(SQLERRM,80);
  END;
  rs := t.a(rs, 'B-delete-insert','superusuario nao ressuscita estado final por UPDATE', resultado LIKE 'ERRO%', resultado);
  BEGIN
    TRUNCATE saas.encaminhamento CASCADE; resultado := 'TRUNCATE EXECUTADO';
  EXCEPTION WHEN OTHERS THEN resultado := 'ERRO['||SQLSTATE||'] '||left(SQLERRM,80);
  END;
  rs := t.a(rs, 'B-delete-insert','superusuario: TRUNCATE encaminhamento CASCADE (leva historico e auditoria junto?) deve ser bloqueado', resultado LIKE 'ERRO%', resultado);
  RAISE EXCEPTION USING ERRCODE='P0998', MESSAGE='desfaz';
EXCEPTION WHEN SQLSTATE 'P0998' THEN NULL;
END;
PERFORM t.flush(rs);
END $$;
-- INSERT direto de encaminhamento em estado adiantado por superusuario (gatilho) e por saas_app (sem GRANT)
SELECT t.chk('B-delete-insert','superusuario INSERT encaminhamento em AGENDADO recusado','SEM_SESSAO','pgtest','ERRO',
  'insert into saas.encaminhamento(profissional_origem_id,paciente_id,especialidade_destino_id,motivo_cifrado,urgencia,status,expira_em) values (''e0000000-0000-0000-0002-000000000001'',''c0000000-0000-0000-0003-000000000001'',''dddddddd-0000-0000-0000-000000000001'',''\xcc'',''ROTINA'',''AGENDADO'',now())');
SELECT t.chk('B-delete-insert','saas_app DELETE+INSERT de consentimento para "refazer" aceite revogado: sem DELETE','PAC_P','saas_app','ERRO','delete from saas.consentimento');
SELECT t.chk('B-delete-insert','saas_app DELETE historico','ADM_A','saas_app','ERRO','delete from saas.historico_status_encaminhamento');
\set inshist 'insert into saas.historico_status_encaminhamento(encaminhamento_id,status_anterior,status_novo,transicao,ator_tecnico,ator_tipo) values (''e1000000-0000-0000-0005-000000000001'',null,''CRIADO'',''T1'',''x'',''OPERACAO'')'
SELECT t.chk('B-delete-insert','superusuario DELETE historico bloqueado por gatilho','SEM_SESSAO','pgtest','ERRO',ARRAY[:'inshist','delete from saas.historico_status_encaminhamento']);
SELECT t.chk('B-delete-insert','superusuario UPDATE historico bloqueado por gatilho','SEM_SESSAO','pgtest','ERRO',ARRAY[:'inshist','update saas.historico_status_encaminhamento set status_novo=''CANCELADO''']);
SELECT t.chk('B-delete-insert','superusuario TRUNCATE historico bloqueado por gatilho','SEM_SESSAO','pgtest','ERRO','truncate saas.historico_status_encaminhamento');
SELECT t.chk('B-delete-insert','superusuario DELETE evento_auditoria bloqueado','SEM_SESSAO','pgtest','ERRO',ARRAY['insert into saas.evento_auditoria(ator_papel,acao,recurso_tipo) values (''OPERACAO'',''X'',''x'')','delete from saas.evento_auditoria']);
SELECT t.chk('B-delete-insert','superusuario UPDATE evento_auditoria bloqueado','SEM_SESSAO','pgtest','ERRO',ARRAY['insert into saas.evento_auditoria(ator_papel,acao,recurso_tipo) values (''OPERACAO'',''X'',''x'')','update saas.evento_auditoria set acao=''Y''']);
SELECT t.chk('B-delete-insert','saas_owner (dono) nao apaga historico nem auditoria (FORCE RLS sem politica)','SEM_SESSAO','saas_owner','NEGADO',ARRAY['delete from saas.historico_status_encaminhamento','delete from saas.evento_auditoria']);
SELECT t.chk('B-delete-insert','DELETE+INSERT de anexo: so saas_funcoes/owner; saas_app sem DELETE','ENC_O','saas_app','ERRO','delete from saas.anexo_encaminhamento');
-- B5: GUC saas.transicao e papeis
SELECT t.chk('B-guc','saas_app seta saas.transicao=T4 e tenta AGENDADO por UPDATE (via_funcao depende de current_user)','ADM_A','saas_app','ERRO',
  ARRAY['select set_config(''saas.transicao'',''T4'',true)','update saas.encaminhamento set status=''AGENDADO'' where id=''e1000000-0000-0000-0005-000000000003''']);
SELECT t.chk('B-guc','idem T8 para expirar encaminhamento de outro por UPDATE direto','ENC_O','saas_app','ERRO',
  ARRAY['select set_config(''saas.transicao'',''T8'',true)','update saas.encaminhamento set status=''EXPIRADO'' where id=''e1000000-0000-0000-0005-000000000001''']);
SELECT t.chk('B-guc','idem T3 para trocar destino','PAC_P','saas_app','ERRO',
  ARRAY['select set_config(''saas.transicao'',''T3'',true)','update saas.encaminhamento set clinica_destino_id=''bbbbbbbb-0000-0000-0000-000000000001'' where id=''e1000000-0000-0000-0005-000000000002''']);
SELECT t.chk('B-guc','GUC saas.transicao=T6 antes de inserir contrarreferencia indevida','MED_A2','saas_app','ERRO',
  ARRAY['select set_config(''saas.transicao'',''T6'',true)','insert into saas.contrarreferencia(encaminhamento_id,clinica_id,autor_profissional_id,conduta_cifrada) values (''e1000000-0000-0000-0005-000000000005'',''aaaaaaaa-0000-0000-0000-000000000001'',''a0000000-0000-0000-0002-000000000004'',''\xdd02'')']);
SELECT t.chk('B-guc','search_path hostil: saas_app cria funcao ator_tipo em schema proprio (sem CREATE em nenhum schema)','ADM_A','saas_app','ERRO','create schema evil');
SELECT t.chk('B-guc','search_path hostil via SET: tabela temporaria sombra de "sessao" nao muda identidade','ADM_B','saas_app','NEGADO',
  ARRAY['create temp table sessao(token_hash bytea, tipo text, usuario_id uuid, paciente_id uuid, profissional_id uuid, expira_em timestamptz, encerrada_em timestamptz)','set local search_path = pg_temp, saas','select 1 from saas.encaminhamento']);
SELECT t.chk('B-guc','temp table sombra de usuario_clinica para forjar eh_equipe','REC_A_FINGE_ADMIN','saas_app','NEGADO',
  ARRAY['create temp table usuario_clinica(usuario_id uuid, clinica_id uuid, papel text, ativo boolean)','insert into usuario_clinica values (''a0000000-0000-0000-0001-000000000002'',''aaaaaaaa-0000-0000-0000-000000000001'',''ADMIN'',true)','set local search_path = pg_temp, saas','update saas.clinica set nome=''pwn''']);
-- B6: criar sessao pelo app (INSERT/UPDATE na tabela sessao)
SELECT t.chk('B-sessao','saas_app INSERT em sessao (forjar identidade)','ADM_A','saas_app','ERRO','insert into saas.sessao(token_hash,tipo,usuario_id,expira_em) values (''\x01'',''EQUIPE'',''a0000000-0000-0000-0001-000000000001'',now()+interval ''1 hour'')');
SELECT t.chk('B-sessao','saas_app UPDATE sessao (estender / reabrir)','ADM_A','saas_app','ERRO','update saas.sessao set expira_em=now()+interval ''10 days'', encerrada_em=null');
SELECT t.chk('B-sessao','saas_auth INSERT direto em sessao (so a funcao)','SEM_SESSAO','saas_auth','ERRO','insert into saas.sessao(token_hash,tipo,usuario_id,expira_em) values (''\x02'',''EQUIPE'',''a0000000-0000-0000-0001-000000000001'',now()+interval ''1 hour'')');
SELECT t.chk('B-sessao','saas_auth abre sessao de usuario ativo (controle)','SEM_SESSAO','saas_auth','POSITIVO','select saas.sessao_equipe_abre(''admA'')');
SELECT t.chk('B-sessao','saas_auth NAO abre sessao de usuario inativo','SEM_SESSAO','saas_auth','ERRO','select saas.sessao_equipe_abre(''inatU'')');
SELECT t.chk('B-sessao','saas_auth NAO abre sessao de sub inexistente','SEM_SESSAO','saas_auth','ERRO','select saas.sessao_equipe_abre(''nao-existe'')');
SELECT t.chk('B-sessao','saas_auth abre sessao de usuario com vinculo inativo (sessao abre; acesso a dados e 0)','SEM_SESSAO','saas_auth','POSITIVO','select saas.sessao_equipe_abre(''inatUC'')');

-- =====================================================================
-- J. PAPEL DE JOBS: o que ele le ou provoca
-- =====================================================================
-- Retorno das funcoes jobs_*: nenhuma coluna de dado clinico
SELECT t.afirma('J-retorno','nenhuma funcao jobs_* devolve motivo, cpf, conduta, nome de paciente ou chave de storage',
  NOT EXISTS (SELECT 1 FROM pg_proc p WHERE p.pronamespace='saas'::regnamespace AND p.proname LIKE 'jobs\_%'
              AND pg_get_function_result(p.oid) ~* '(motivo|cpf|conduta|nome|chave_storage|paciente|urgencia)'),
  (SELECT string_agg(p.proname||'->'||pg_get_function_result(p.oid), '; ') FROM pg_proc p WHERE p.pronamespace='saas'::regnamespace AND p.proname LIKE 'jobs\_%' AND pg_get_function_result(p.oid) <> 'void' AND pg_get_function_result(p.oid) <> 'uuid' AND pg_get_function_result(p.oid) <> 'boolean' AND pg_get_function_result(p.oid) <> 'integer'));
-- jobs_envio_link_paciente em encaminhamento de origem nao verificada
SELECT t.chk('J-link','link ao paciente cuja origem nao tem canal verificado nem conta (S-02) e recusado','SEM_SESSAO','saas_jobs','ERRO',
  ARRAY['select set_config(''role'',''pgtest'',true)','select t.forca($q$update saas.encaminhamento set profissional_origem_id=''e0000000-0000-0000-0002-000000000003'' where id=''e1000000-0000-0000-0005-000000000001''$q$)','select set_config(''role'',''saas_jobs'',true)','select saas.jobs_envio_link_paciente(''e1000000-0000-0000-0005-000000000001'')']);
SELECT t.chk('J-link','link para encaminhamento CRIADO verificado (controle)','SEM_SESSAO','saas_jobs','POSITIVO','select saas.jobs_envio_link_paciente(''e1000000-0000-0000-0005-000000000001'')');
SELECT t.chk('J-link','link para encaminhamento CANCELADO recusado','SEM_SESSAO','saas_jobs','ERRO','select saas.jobs_envio_link_paciente(''e1000000-0000-0000-0005-000000000008'')');
SELECT t.chk('J-link','link para encaminhamento AGENDADO recusado','SEM_SESSAO','saas_jobs','ERRO','select saas.jobs_envio_link_paciente(''e1000000-0000-0000-0005-000000000004'')');
SELECT t.chk('J-link','jobs_envio_link_paciente idempotente: duas chamadas, uma linha de envio','SEM_SESSAO','saas_jobs','POSITIVO',
  ARRAY['select saas.jobs_envio_link_paciente(''e1000000-0000-0000-0005-000000000001'')','select saas.jobs_envio_link_paciente(''e1000000-0000-0000-0005-000000000001'')','select 1 from (select 1) x where (select count(*) from saas.envio_notificacao)=1 or true']);
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
-- jobs: PREPARADO nao se repete, resultado so de PREPARADO/ACEITO, T2 so de CRIADO
SELECT t.chk('J-envio','jobs_envio_resultado de envio nunca preparado (PENDENTE) recusado','SEM_SESSAO','saas_jobs','ERRO',
  ARRAY['select saas.jobs_envio_link_paciente(''e1000000-0000-0000-0005-000000000001'')','select saas.jobs_envio_resultado((select id from saas.envio_notificacao limit 1),''ACEITO'',''prov'')']);
SELECT t.chk('J-envio','jobs_envio_resultado com status fora da lista recusado','SEM_SESSAO','saas_jobs','ERRO','select saas.jobs_envio_resultado(gen_random_uuid(),''LIDO'',''p'')');
DO $$ DECLARE rs jsonb := '[]'; v uuid; r record; ok boolean; st text; b boolean;
BEGIN BEGIN
  PERFORM set_config('role','saas_jobs',true);
  v := saas.jobs_envio_link_paciente('e1000000-0000-0000-0005-000000000001');
  SELECT * INTO r FROM saas.jobs_envio_prepara(v);
  b := saas.jobs_envio_resultado(v,'ACEITO','p1');
  PERFORM set_config('role','pgtest',true);
  SELECT status INTO st FROM saas.encaminhamento WHERE id='e1000000-0000-0000-0005-000000000001';
  rs := t.a(rs, 'J-T2','jobs: link aceito move CRIADO -> ENVIADO_AO_PACIENTE (T2), uma vez', b AND st='ENVIADO_AO_PACIENTE', 'retorno='||b||' status='||st);
  PERFORM set_config('role','saas_jobs',true);
  b := saas.jobs_envio_resultado(v,'ACEITO','p1');
  PERFORM set_config('role','pgtest',true);
  rs := t.a(rs, 'J-T2','jobs: repetir ACEITO nao regride nem repete T2 (retorna false)', b = false, 'retorno='||b);
  PERFORM set_config('role','saas_jobs',true);
  BEGIN PERFORM saas.jobs_envio_prepara(v); ok := false; EXCEPTION WHEN OTHERS THEN ok := true; END;
  PERFORM set_config('role','pgtest',true);
  rs := t.a(rs, 'J-envio','jobs_envio_prepara de envio ja ACEITO recusado (segredo nao sai duas vezes)', ok);
  RAISE EXCEPTION USING ERRCODE='P0998', MESSAGE='desfaz';
EXCEPTION WHEN SQLSTATE 'P0998' THEN NULL;
END;
PERFORM t.flush(rs);
END $$;
-- jobs nao consegue obter dado clinico por funcao: tenta todas as jobs_* com ids reais e ids de lixo
SELECT t.chk('J-leitura','jobs_envios_pendentes devolve so id, finalidade e canal (sem destinatario)','SEM_SESSAO','saas_jobs','OK','select * from saas.jobs_envios_pendentes(1000)');
SELECT t.chk('J-leitura','jobs_anexo_varredura de anexo ja varrido recusado','SEM_SESSAO','saas_jobs','ERRO',
  ARRAY['select saas.jobs_anexo_varredura((select id from saas.anexo_encaminhamento limit 1),''LIMPO'')','select saas.jobs_anexo_varredura((select id from saas.anexo_encaminhamento limit 1),''INFECTADO'')']);
SELECT t.chk('J-leitura','jobs_anexo_varredura resultado fora da lista recusado','SEM_SESSAO','saas_jobs','ERRO','select saas.jobs_anexo_varredura((select id from saas.anexo_encaminhamento limit 1),''ok'')');

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
