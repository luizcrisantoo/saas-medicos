-- =====================================================================
-- teste-rls.sql : prova de isolamento por RLS do modelo-v2.sql
-- Tarefa t-fase1-arquitetura, criterio 9. Executado por teste-rls.sh
-- (cluster PostgreSQL 16 descartavel; modelo-v2.sql ja aplicado).
-- Parte 1: semeia dados como superusuario do cluster (fixture de teste,
--          nao altera o modelo). Parte 2: roda tudo como saas_app
--          (NOSUPERUSER, NOBYPASSRLS, nao dono). Parte 3: confere
--          integridade e gatilhos de auditoria como dono/superusuario.
-- Convencao de esperado em cada sonda:
--   ERRO     deve falhar com erro      | 0       deve afetar/ver 0 linhas
--   NEGADO   erro ou 0 linhas          | POSITIVO deve ver/afetar >0 (controle)
--   OK       deve executar sem erro    | INFO    so registra (nao conta como falha)
-- Cada sonda roda em subtransacao e e desfeita (nada persiste entre sondas).
-- =====================================================================
\set ON_ERROR_STOP on
\set QUIET on
\pset pager off
\pset format aligned

-- ids fixos (hex valido) ------------------------------------------------
\set cA   'aaaaaaaa-0000-0000-0000-000000000001'
\set cB   'bbbbbbbb-0000-0000-0000-000000000001'
\set uA   'aaaaaaaa-0000-0000-0001-000000000001'
\set uRecA 'aaaaaaaa-0000-0000-0001-000000000002'
\set uMedA 'aaaaaaaa-0000-0000-0001-000000000003'
\set uInatA 'aaaaaaaa-0000-0000-0001-000000000004'
\set uB   'bbbbbbbb-0000-0000-0001-000000000001'
\set uMedB 'bbbbbbbb-0000-0000-0001-000000000002'
\set pA   'aaaaaaaa-0000-0000-0002-000000000001'
\set pB   'bbbbbbbb-0000-0000-0002-000000000001'
\set pE   'eeeeeeee-0000-0000-0002-000000000001'
\set pE2  'eeeeeeee-0000-0000-0002-000000000002'
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
\set tokE1 '0101010101010101'
\set tokE2 '0202020202020202'

-- =====================================================================
-- PARTE 1: semente (superusuario do cluster descartavel)
-- =====================================================================
\connect - pgtest
SET search_path = saas, public;

INSERT INTO especialidade(id,nome) VALUES (:'eC','Cardiologia'),(:'eD','Dermatologia');
INSERT INTO usuario(id,sub_oidc,nome,email) VALUES
 (:'uA','sub-uA','Admin A','a@a.test'),(:'uRecA','sub-uRecA','Recepcao A','r@a.test'),
 (:'uMedA','sub-uMedA','Medico A','m@a.test'),(:'uInatA','sub-uInatA','Admin Inativo A','i@a.test'),
 (:'uB','sub-uB','Admin B','a@b.test'),(:'uMedB','sub-uMedB','Medico B','m@b.test');
INSERT INTO clinica(id,nome,modo_recebimento) VALUES (:'cA','Clinica A','VAGAS'),(:'cB','Clinica B','VAGAS');
INSERT INTO clinica_especialidade VALUES (:'cA',:'eC'),(:'cB',:'eC');
INSERT INTO usuario_clinica(usuario_id,clinica_id,papel,ativo) VALUES
 (:'uA',:'cA','ADMIN',true),(:'uRecA',:'cA','RECEPCAO',true),(:'uMedA',:'cA','MEDICO',true),
 (:'uInatA',:'cA','ADMIN',false),(:'uB',:'cB','ADMIN',true),(:'uMedB',:'cB','MEDICO',true);
INSERT INTO flag_clinica(clinica_id,chave,ligada) VALUES (:'cA','f1',true),(:'cB','f1',true);
INSERT INTO profissional(id,crm,crm_uf,nome,telefone,email,usuario_id) VALUES
 (:'pA','1001','SP','Dr A','11900000001','pa@a.test',:'uMedA'),
 (:'pB','2001','RJ','Dr B','21900000001','pb@b.test',:'uMedB'),
 (:'pE','3001','MG','Dr Encaminhador','31900000001','pe@x.test',NULL),
 (:'pE2','3002','MG','Dr Encaminhador 2','31900000002','pe2@x.test',NULL);
INSERT INTO profissional_especialidade VALUES (:'pA',:'eC'),(:'pB',:'eC');
INSERT INTO profissional_clinica(id,profissional_id,clinica_id,recebe_encaminhamento) VALUES
 (:'pcA',:'pA',:'cA',true),(:'pcB',:'pB',:'cB',true);
INSERT INTO horario_atendimento(clinica_id,profissional_clinica_id,dia_semana,hora_inicio,hora_fim) VALUES
 (:'cA',:'pcA',1,'08:00','12:00'),(:'cB',:'pcB',1,'08:00','12:00');
INSERT INTO paciente(id,nome,telefone,data_nascimento,cpf_cifrado,cpf_hash) VALUES
 (:'pacA','Paciente A','11911110001','1980-01-01','\xaa01','\xbb01'),
 (:'pacB','Paciente B','21911110002','1981-02-02','\xaa02','\xbb02'),
 (:'pacX','Paciente X','31911110003','1982-03-03','\xaa03','\xbb03');
INSERT INTO paciente_clinica(paciente_id,clinica_id) VALUES (:'pacA',:'cA'),(:'pacB',:'cB');
INSERT INTO encaminhamento(id,profissional_origem_id,paciente_id,especialidade_destino_id,clinica_destino_id,motivo_cifrado,urgencia,expira_em) VALUES
 (:'E1',:'pE',:'pacA',:'eC',:'cA','\xdead01','ROTINA',now()+interval '30 days'),
 (:'E2',:'pE',:'pacB',:'eC',:'cB','\xdead02','ROTINA',now()+interval '30 days'),
 (:'E3',:'pE',:'pacX',:'eC',:'cA','\xdead03','ROTINA',now()+interval '30 days'),
 (:'E5',:'pE',:'pacA',:'eC',:'cA','\xdead05','ROTINA',now()+interval '30 days'),
 (:'E6',:'pE',:'pacX',:'eC',NULL,'\xdead06','ROTINA',now()+interval '30 days'),
 (:'E7',:'pE',:'pacX',:'eC',NULL,'\xdead07','ROTINA',now()-interval '1 day');
UPDATE encaminhamento SET status='CANCELADO' WHERE id=:'E6';   -- estado final para sonda de maquina de estados
INSERT INTO consentimento(paciente_id,finalidade,encaminhamento_id,clinica_id,texto_aceito,versao_texto,canal) VALUES
 (:'pacA','COMPARTILHAR_CASO',:'E1',:'cA','texto','v1','SITE'),
 (:'pacB','COMPARTILHAR_CASO',:'E2',:'cB','texto','v1','SITE'),
 (:'pacA','COMPARTILHAR_CASO',:'E5',:'cA','texto','v1','SITE'),
 (:'pacA','AGENDAMENTO',NULL,:'cA','texto','v1','RECEPCAO'),
 (:'pacB','AGENDAMENTO',NULL,:'cB','texto','v1','RECEPCAO');
INSERT INTO link_paciente(encaminhamento_id,paciente_id,token_hash,expira_em) VALUES
 (:'E1',:'pacA',decode(:'tokE1','hex'),now()+interval '3 days'),
 (:'E2',:'pacB',decode(:'tokE2','hex'),now()+interval '3 days');
INSERT INTO vaga_encaminhamento(clinica_id,profissional_clinica_id,inicio,fim) VALUES
 (:'cA',:'pcA',now()+interval '10 days',now()+interval '10 days 30 min'),
 (:'cB',:'pcB',now()+interval '10 days',now()+interval '10 days 30 min');
INSERT INTO agendamento(clinica_id,profissional_clinica_id,paciente_id,inicio,fim,origem,chave_idempotencia) VALUES
 (:'cA',:'pcA',:'pacA',now()+interval '5 days',now()+interval '5 days 30 min','RECEPCAO','kA1'),
 (:'cB',:'pcB',:'pacB',now()+interval '5 days',now()+interval '5 days 30 min','RECEPCAO','kB1');
INSERT INTO contrarreferencia(encaminhamento_id,clinica_id,autor_profissional_id,conduta_cifrada) VALUES
 (:'E1',:'cA',:'pA','\xc0de01'),(:'E2',:'cB',:'pB','\xc0de02');
INSERT INTO anexo_encaminhamento(encaminhamento_id,chave_storage,tipo_mime,tamanho_bytes,sha256,enviado_por_tipo,enviado_por_id) VALUES
 (:'E1','obj-E1','application/pdf',100,'\x01','PROFISSIONAL',:'pE'),
 (:'E2','obj-E2','application/pdf',100,'\x02','PROFISSIONAL',:'pE');
INSERT INTO evento_auditoria(ator_papel,ator_id,clinica_id,acao,recurso_tipo) VALUES
 ('ADMIN',:'uA',:'cA','LER','X'),('ADMIN',:'uB',:'cB','LER','X'),('SISTEMA',NULL,NULL,'LER','X');

-- Auxiliar de teste (fora do schema do modelo): dono de cada linha e fotografia de integridade
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
INSERT INTO teste_aux.alvos SELECT 'encaminhamento', CASE WHEN id=:'E2' THEN 'B' WHEN id IN (:'E1',:'E5') THEN 'A' ELSE 'N' END, id FROM encaminhamento;
INSERT INTO teste_aux.alvos SELECT 'historico_status_encaminhamento', CASE WHEN encaminhamento_id=:'E2' THEN 'B' WHEN encaminhamento_id IN (:'E1',:'E5') THEN 'A' ELSE 'N' END, id FROM historico_status_encaminhamento;
INSERT INTO teste_aux.alvos SELECT 'link_paciente', CASE WHEN encaminhamento_id=:'E2' THEN 'B' ELSE 'A' END, id FROM link_paciente;
INSERT INTO teste_aux.alvos SELECT 'anexo_encaminhamento', CASE WHEN encaminhamento_id=:'E2' THEN 'B' ELSE 'A' END, id FROM anexo_encaminhamento;
-- linhas de B que a clinica A nunca pode ver (E2 e filhos: contrarreferencia e consentimento ja marcados por clinica_id)
DO $$
DECLARE t text;
BEGIN
  FOR t IN SELECT tablename FROM pg_tables WHERE schemaname='saas' LOOP
    EXECUTE format('INSERT INTO teste_aux.snap SELECT %L, md5(coalesce(string_agg(x::text, ''|'' ORDER BY x::text),'''')) FROM saas.%I x', t, t);
  END LOOP;
END $$;
GRANT USAGE ON SCHEMA teste_aux TO saas_app;
GRANT SELECT ON teste_aux.alvos TO saas_app;

\echo
\echo '===== PARTE 2: testes como saas_app ====='
\connect - saas_app
SET search_path = saas, public;

SELECT current_user AS papel_de_conexao, rolsuper, rolbypassrls,
       (SELECT count(*) FROM pg_tables WHERE tableowner = current_user) AS tabelas_de_propriedade_do_app
  FROM pg_roles WHERE rolname = current_user;

CREATE TEMP TABLE k(nome text PRIMARY KEY, id text);
INSERT INTO k VALUES
 ('cA',:'cA'),('cB',:'cB'),('uA',:'uA'),('uRecA',:'uRecA'),('uMedA',:'uMedA'),('uInatA',:'uInatA'),('uB',:'uB'),('uMedB',:'uMedB'),
 ('pA',:'pA'),('pB',:'pB'),('pE',:'pE'),('pE2',:'pE2'),('pacA',:'pacA'),('pacB',:'pacB'),('pacX',:'pacX'),
 ('pcA',:'pcA'),('pcB',:'pcB'),('eC',:'eC'),('eD',:'eD'),('E1',:'E1'),('E2',:'E2'),('E3',:'E3'),('E5',:'E5'),('E6',:'E6'),('E7',:'E7'),
 ('tokE1',:'tokE1'),('tokE2',:'tokE2'),('morta','dddddddd-0000-0000-0000-00000000dead');
CREATE TEMP TABLE res(n serial, secao text, nome text, ctx text, esperado text, obtido text, ok boolean);

-- ctx(nome): define as 6 variaveis de sessao do modelo com is_local = true
CREATE FUNCTION pg_temp.kid(n text) RETURNS text LANGUAGE sql AS $$ SELECT id FROM pg_temp.k WHERE nome = n $$;
CREATE FUNCTION pg_temp.ctx(c text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE v text[];  -- clinica, usuario, papel, profissional, paciente, token_hash_hex
BEGIN
  v := CASE c
    WHEN 'ADM_A'  THEN ARRAY[pg_temp.kid('cA'), pg_temp.kid('uA'),    'ADMIN',     '', '', '']
    WHEN 'REC_A'  THEN ARRAY[pg_temp.kid('cA'), pg_temp.kid('uRecA'), 'RECEPCAO',  '', '', '']
    WHEN 'MED_A'  THEN ARRAY[pg_temp.kid('cA'), pg_temp.kid('uMedA'), 'MEDICO',    pg_temp.kid('pA'), '', '']
    WHEN 'ADM_B'  THEN ARRAY[pg_temp.kid('cB'), pg_temp.kid('uB'),    'ADMIN',     '', '', '']
    WHEN 'MED_B'  THEN ARRAY[pg_temp.kid('cB'), pg_temp.kid('uMedB'), 'MEDICO',    pg_temp.kid('pB'), '', '']
    WHEN 'ENC_E'  THEN ARRAY['', '', 'ENCAMINHADOR', pg_temp.kid('pE'),  '', '']
    WHEN 'ENC_E2' THEN ARRAY['', '', 'ENCAMINHADOR', pg_temp.kid('pE2'), '', '']
    WHEN 'ENC_E2_CLIN_A' THEN ARRAY[pg_temp.kid('cA'), '', 'ENCAMINHADOR', pg_temp.kid('pE2'), '', '']
    WHEN 'PAC_A'  THEN ARRAY['', '', 'PACIENTE', '', pg_temp.kid('pacA'), '']
    WHEN 'PAC_B'  THEN ARRAY['', '', 'PACIENTE', '', pg_temp.kid('pacB'), '']
    WHEN 'PAC_X'  THEN ARRAY['', '', 'PACIENTE', '', pg_temp.kid('pacX'), '']
    WHEN 'LINK_E1' THEN ARRAY['', '', 'PUBLICO_LINK', '', '', pg_temp.kid('tokE1')]
    WHEN 'SISTEMA' THEN ARRAY['', '', 'SISTEMA', '', '', '']
    WHEN 'VAZIO'  THEN ARRAY['', '', '', '', '', '']
    WHEN 'SO_CLINICA_A' THEN ARRAY[pg_temp.kid('cA'), '', '', '', '', '']
    WHEN 'SO_PAPEL_ADMIN' THEN ARRAY['', '', 'ADMIN', '', '', '']
    WHEN 'USU_SEM_CLINICA' THEN ARRAY['', pg_temp.kid('uA'), 'ADMIN', '', '', '']
    WHEN 'CLIN_INEXISTENTE' THEN ARRAY[pg_temp.kid('morta'), pg_temp.kid('uA'), 'ADMIN', '', '', '']
    WHEN 'ADM_A_NA_CLIN_B' THEN ARRAY[pg_temp.kid('cB'), pg_temp.kid('uA'), 'ADMIN', '', '', '']   -- ctx forjado: usuario de A com clinica de B
    WHEN 'REC_A_FINGE_ADMIN' THEN ARRAY[pg_temp.kid('cA'), pg_temp.kid('uRecA'), 'ADMIN', '', '', '']
    WHEN 'ADM_A_INATIVO' THEN ARRAY[pg_temp.kid('cA'), pg_temp.kid('uInatA'), 'ADMIN', '', '', '']
    WHEN 'GUC_LIXO' THEN ARRAY['abc', pg_temp.kid('uA'), 'ADMIN', '', '', '']
    ELSE NULL END;
  IF v IS NULL THEN RAISE EXCEPTION 'ctx desconhecido %', c; END IF;
  PERFORM set_config('app.clinica_id', v[1], true), set_config('app.usuario', v[2], true),
          set_config('app.papel', v[3], true), set_config('app.profissional_id', v[4], true),
          set_config('app.paciente_id', v[5], true), set_config('app.link_token_hash', v[6], true);
END $$;

-- sonda: aplica ctx, executa passos, mede, desfaz tudo (subtransacao) e registra
CREATE FUNCTION pg_temp.sonda(secao text, nome text, c text, esperado text, passos text[], verif text DEFAULT NULL, ctx_verif text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE s text; r text := NULL; n bigint; ok boolean; kk record;
BEGIN
  BEGIN
    IF c <> 'NUNCA' THEN PERFORM pg_temp.ctx(c); END IF;
    FOREACH s IN ARRAY passos LOOP
      FOR kk IN SELECT * FROM pg_temp.k LOOP s := replace(s, '{'||kk.nome||'}', kk.id); END LOOP;
      IF s LIKE 'ctx:%' THEN PERFORM pg_temp.ctx(substr(s,5));
      ELSE EXECUTE s; GET DIAGNOSTICS n = ROW_COUNT; r := n::text; END IF;
    END LOOP;
    IF verif IS NOT NULL THEN
      IF ctx_verif IS NOT NULL THEN PERFORM pg_temp.ctx(ctx_verif); END IF;
      FOR kk IN SELECT * FROM pg_temp.k LOOP verif := replace(verif, '{'||kk.nome||'}', kk.id); END LOOP;
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
  INSERT INTO pg_temp.res(secao, nome, ctx, esperado, obtido, ok) VALUES (secao, nome, c, esperado, r, ok);
END $$;

-- lista das 20 tabelas com RLS e das 17 com coluna id
CREATE TEMP TABLE tabs_rls AS SELECT relname::text AS t FROM pg_class
  WHERE relnamespace='saas'::regnamespace AND relkind='r' AND relrowsecurity ORDER BY 1;
SELECT count(*) AS tabelas_com_rls, bool_and(relforcerowsecurity) AS todas_com_force
  FROM pg_class WHERE relnamespace='saas'::regnamespace AND relkind='r' AND relrowsecurity;

\o /dev/null
-- ---------------------------------------------------------------------
-- (c) nega por padrao. Primeiro: GUC nunca definida nesta conexao
-- ---------------------------------------------------------------------
DO $$ DECLARE t text; c text; BEGIN
  FOREACH c IN ARRAY ARRAY['NUNCA','VAZIO','SO_CLINICA_A','SO_PAPEL_ADMIN','USU_SEM_CLINICA','CLIN_INEXISTENTE'] LOOP
    FOR t IN SELECT tabs_rls.t FROM pg_temp.tabs_rls LOOP
      -- por desenho: profissional/profissional_especialidade sao globais para qualquer papel logado; usuario e usuario_clinica
      -- mostram so a propria identidade (usuario_proprio, usuario_clinica_ver). Sao INFO, nao falha, nos contextos que trazem papel/usuario.
      IF (c IN ('SO_PAPEL_ADMIN','USU_SEM_CLINICA','CLIN_INEXISTENTE') AND t IN ('profissional','profissional_especialidade'))
         OR (c IN ('USU_SEM_CLINICA','CLIN_INEXISTENTE') AND t IN ('usuario','usuario_clinica')) THEN
        PERFORM pg_temp.sonda('c','ver '||t||' (global/proprio por desenho)',c,'INFO',ARRAY[format('select 1 from saas.%I',t)]);
      ELSE
        PERFORM pg_temp.sonda('c','ver '||t,c,'0',ARRAY[format('select 1 from saas.%I',t)]);
      END IF;
    END LOOP;
    PERFORM pg_temp.sonda('c','inserir agendamento',c,'ERRO',ARRAY[
      'insert into saas.agendamento(clinica_id,profissional_clinica_id,paciente_id,inicio,fim,origem,chave_idempotencia) values (''{cA}'',''{pcA}'',''{pacA}'',now()+interval ''40 days'',now()+interval ''40 days 30 min'',''RECEPCAO'',''c-x'')']);
    PERFORM pg_temp.sonda('c','atualizar agendamento',c,'NEGADO',ARRAY['update saas.agendamento set id=id']);
    PERFORM pg_temp.sonda('c','atualizar encaminhamento',c,'NEGADO',ARRAY['update saas.encaminhamento set urgencia=urgencia']);
  END LOOP;
END $$;
-- GUC com lixo nao uuid: deve falhar fechado (erro), nunca liberar
DO $$ DECLARE t text; BEGIN
  FOR t IN SELECT tabs_rls.t FROM pg_temp.tabs_rls LOOP
    PERFORM pg_temp.sonda('c','GUC clinica_id=abc em '||t||CASE WHEN t IN ('profissional','profissional_especialidade') THEN ' (global por desenho)' ELSE '' END,'GUC_LIXO',
      CASE WHEN t IN ('profissional','profissional_especialidade') THEN 'INFO' ELSE 'NEGADO' END,ARRAY[format('select 1 from saas.%I',t)]);
  END LOOP;
END $$;
-- controle: especialidade nao tem RLS (catalogo), segue visivel sem contexto
SELECT pg_temp.sonda('c','especialidade sem RLS e visivel sem contexto (catalogo global)','VAZIO','POSITIVO',ARRAY['select 1 from saas.especialidade']);

-- ---------------------------------------------------------------------
-- controles positivos: os testes nao sao vacuos (A enxerga o que e de A)
-- ---------------------------------------------------------------------
DO $$ DECLARE t text; BEGIN
  FOREACH t IN ARRAY ARRAY['usuario','clinica','usuario_clinica','flag_clinica','profissional_clinica','horario_atendimento',
                           'paciente','paciente_clinica','encaminhamento','historico_status_encaminhamento','consentimento',
                           'vaga_encaminhamento','agendamento','contrarreferencia','anexo_encaminhamento','evento_auditoria','clinica_especialidade'] LOOP
    PERFORM pg_temp.sonda('controle','ADM_A ve linhas de A em '||t,'ADM_A','POSITIVO',ARRAY[format('select 1 from saas.%I',t)]);
  END LOOP;
END $$;
SELECT pg_temp.sonda('controle','REC_A ve agendamento da propria clinica','REC_A','POSITIVO',ARRAY['select 1 from saas.agendamento where clinica_id=''{cA}''']);
SELECT pg_temp.sonda('controle','ADM_A insere agendamento na clinica A','ADM_A','POSITIVO',ARRAY[
  'insert into saas.agendamento(clinica_id,profissional_clinica_id,paciente_id,inicio,fim,origem,chave_idempotencia) values (''{cA}'',''{pcA}'',''{pacA}'',now()+interval ''40 days'',now()+interval ''40 days 30 min'',''RECEPCAO'',''ok-1'')']);
SELECT pg_temp.sonda('controle','ADM_A atualiza agendamento da clinica A','ADM_A','POSITIVO',ARRAY['update saas.agendamento set status=''CONFIRMADO'' where clinica_id=''{cA}''']);
SELECT pg_temp.sonda('controle','ADM_B ve a propria clinica B','ADM_B','POSITIVO',ARRAY['select 1 from saas.agendamento where clinica_id=''{cB}''']);

-- ---------------------------------------------------------------------
-- (a) clinica A nao le, lista, atualiza, apaga nem insere em B (todas as tabelas RLS)
-- ---------------------------------------------------------------------
DO $$ DECLARE t text; c text; ids text; BEGIN
  FOREACH c IN ARRAY ARRAY['ADM_A','REC_A','MED_A'] LOOP
    FOR t IN SELECT x FROM unnest(ARRAY['usuario','clinica','usuario_clinica','flag_clinica','profissional_clinica','horario_atendimento',
         'paciente','paciente_clinica','encaminhamento','historico_status_encaminhamento','consentimento','link_paciente',
         'vaga_encaminhamento','agendamento','contrarreferencia','anexo_encaminhamento','evento_auditoria']) x LOOP
      ids := format('select id from teste_aux.alvos where tab=%L and dono=''B''', t);
      PERFORM pg_temp.sonda('a','ler por id (B) em '||t,c,'0',ARRAY[format('select 1 from saas.%I where id in (%s)',t,ids)]);
      PERFORM pg_temp.sonda('a','listar tudo e cruzar com B em '||t,c,'0',ARRAY['select 1'],
        format('select count(*) from (select id from saas.%I) s join teste_aux.alvos a on a.id=s.id and a.tab=%L and a.dono=''B''',t,t));
      PERFORM pg_temp.sonda('a','atualizar (B) em '||t,c,'NEGADO',ARRAY[
        format('update saas.%I set %s where id in (%s)',t, CASE WHEN t='consentimento' THEN 'revogado_em=revogado_em' ELSE 'id=id' END, ids)]);
      PERFORM pg_temp.sonda('a','apagar (B) em '||t,c,'NEGADO',ARRAY[format('delete from saas.%I where id in (%s)',t,ids)]);
    END LOOP;
    -- tabelas sem coluna id
    PERFORM pg_temp.sonda('a','ler clinica_especialidade de B',c,'0',ARRAY['select 1 from saas.clinica_especialidade where clinica_id=''{cB}''']);
    PERFORM pg_temp.sonda('a','atualizar clinica_especialidade de B',c,'NEGADO',ARRAY['update saas.clinica_especialidade set clinica_id=clinica_id where clinica_id=''{cB}''']);
    PERFORM pg_temp.sonda('a','apagar clinica_especialidade de B',c,'NEGADO',ARRAY['delete from saas.clinica_especialidade where clinica_id=''{cB}''']);
  END LOOP;
END $$;

-- inserts com clinica_id de B (e controle: o mesmo com A passa onde ha politica de insert)
DO $$ DECLARE c text; BEGIN
  FOREACH c IN ARRAY ARRAY['ADM_A','REC_A','MED_A'] LOOP
    PERFORM pg_temp.sonda('a','inserir clinica_especialidade(B)',c,'ERRO',ARRAY['insert into saas.clinica_especialidade values (''{cB}'',''{eD}'')']);
    PERFORM pg_temp.sonda('a','inserir usuario_clinica(B) (auto-promocao)',c,'ERRO',ARRAY['insert into saas.usuario_clinica(usuario_id,clinica_id,papel) values (''{uA}'',''{cB}'',''ADMIN'')']);
    PERFORM pg_temp.sonda('a','inserir flag_clinica(B)',c,'ERRO',ARRAY['insert into saas.flag_clinica(clinica_id,chave,ligada) values (''{cB}'',''novo'',true)']);
    PERFORM pg_temp.sonda('a','inserir profissional_clinica(B)',c,'ERRO',ARRAY['insert into saas.profissional_clinica(profissional_id,clinica_id) values (''{pA}'',''{cB}'')']);
    PERFORM pg_temp.sonda('a','inserir horario_atendimento(B)',c,'ERRO',ARRAY['insert into saas.horario_atendimento(clinica_id,profissional_clinica_id,dia_semana,hora_inicio,hora_fim) values (''{cB}'',''{pcB}'',2,''08:00'',''09:00'')']);
    PERFORM pg_temp.sonda('a','inserir paciente_clinica(B)',c,'ERRO',ARRAY['insert into saas.paciente_clinica(paciente_id,clinica_id) values (''{pacA}'',''{cB}'')']);
    PERFORM pg_temp.sonda('a','inserir vaga_encaminhamento(B)',c,'ERRO',ARRAY['insert into saas.vaga_encaminhamento(clinica_id,profissional_clinica_id,inicio,fim) values (''{cB}'',''{pcB}'',now()+interval ''50 days'',now()+interval ''50 days 30 min'')']);
    PERFORM pg_temp.sonda('a','inserir agendamento(B)',c,'ERRO',ARRAY['insert into saas.agendamento(clinica_id,profissional_clinica_id,paciente_id,inicio,fim,origem,chave_idempotencia) values (''{cB}'',''{pcB}'',''{pacB}'',now()+interval ''50 days'',now()+interval ''50 days 30 min'',''RECEPCAO'',''x-b'')']);
    PERFORM pg_temp.sonda('a','inserir consentimento(B, RECEPCAO)',c,'ERRO',ARRAY['insert into saas.consentimento(paciente_id,finalidade,clinica_id,texto_aceito,versao_texto,canal) values (''{pacB}'',''AGENDAMENTO'',''{cB}'',''t'',''v1'',''RECEPCAO'')']);
    PERFORM pg_temp.sonda('a','inserir contrarreferencia(B)',c,'ERRO',ARRAY['insert into saas.contrarreferencia(encaminhamento_id,clinica_id,autor_profissional_id,conduta_cifrada) values (''{E2}'',''{cB}'',''{pA}'',''\xff'')']);
    PERFORM pg_temp.sonda('a','inserir evento_auditoria(clinica B)',c,'ERRO',ARRAY['insert into saas.evento_auditoria(ator_papel,clinica_id,acao,recurso_tipo) values (''ADMIN'',''{cB}'',''X'',''X'')']);
    PERFORM pg_temp.sonda('a','inserir link_paciente para encaminhamento de B',c,'ERRO',ARRAY['insert into saas.link_paciente(encaminhamento_id,paciente_id,token_hash,expira_em) values (''{E2}'',''{pacB}'',''\x99'',now()+interval ''1 day'')']);
    PERFORM pg_temp.sonda('a','inserir anexo em encaminhamento de B',c,'ERRO',ARRAY['insert into saas.anexo_encaminhamento(encaminhamento_id,chave_storage,tipo_mime,tamanho_bytes,sha256,enviado_por_tipo,enviado_por_id) values (''{E2}'',''obj-x'',''application/pdf'',1,''\x01'',''PROFISSIONAL'',''{pA}'')']);
    PERFORM pg_temp.sonda('a','inserir historico em encaminhamento de B',c,'ERRO',ARRAY['insert into saas.historico_status_encaminhamento(encaminhamento_id,status_anterior,status_novo,autor_papel) values (''{E2}'',''CRIADO'',''ATENDIDO'',''ADMIN'')']);
  END LOOP;
END $$;
-- controle: mesmo insert com A passa (profissional_clinica exige ADMIN)
SELECT pg_temp.sonda('controle','ADM_A insere paciente_clinica(A)','ADM_A','POSITIVO',ARRAY['insert into saas.paciente_clinica(paciente_id,clinica_id) values (''{pacX}'',''{cA}'')']);
SELECT pg_temp.sonda('controle','ADM_A insere evento_auditoria(clinica A)','ADM_A','POSITIVO',ARRAY['insert into saas.evento_auditoria(ator_papel,clinica_id,acao,recurso_tipo) values (''ADMIN'',''{cA}'',''X'',''X'')']);
SELECT pg_temp.sonda('controle','ADM_A insere clinica_especialidade(A)','ADM_A','POSITIVO',ARRAY['insert into saas.clinica_especialidade values (''{cA}'',''{eD}'')']);
-- papel de aplicacao nao pode desligar RLS nem virar dono
SELECT pg_temp.sonda('a','saas_app: SET ROLE saas_owner','NUNCA','ERRO',ARRAY['set local role saas_owner']);
SELECT pg_temp.sonda('a','saas_app: DISABLE ROW LEVEL SECURITY','NUNCA','ERRO',ARRAY['alter table saas.agendamento disable row level security']);
SELECT pg_temp.sonda('a','saas_app: NO FORCE ROW LEVEL SECURITY','NUNCA','ERRO',ARRAY['alter table saas.agendamento no force row level security']);
SELECT pg_temp.sonda('a','saas_app: criar politica permissiva','NUNCA','ERRO',ARRAY['create policy p_vaza on saas.agendamento for select using (true)']);
SELECT pg_temp.sonda('a','saas_app: session_replication_role=replica (pula gatilhos)','NUNCA','ERRO',ARRAY['set local session_replication_role = replica']);
SELECT pg_temp.sonda('a','saas_app: TRUNCATE agendamento','ADM_A','ERRO',ARRAY['truncate saas.agendamento']);

-- ---------------------------------------------------------------------
-- (b) visibilidade do encaminhamento: origem, clinica destino (com consentimento), paciente
-- ---------------------------------------------------------------------
DO $$ DECLARE c text; vis boolean; q text; tab text; BEGIN
  -- E1: origem pE, destino clinica A com consentimento, paciente pacA
  FOREACH c IN ARRAY ARRAY['ENC_E','ADM_A','REC_A','MED_A','PAC_A','ADM_B','MED_B','ENC_E2','ENC_E2_CLIN_A','PAC_B','PAC_X','LINK_E1','SISTEMA','ADM_A_NA_CLIN_B','REC_A_FINGE_ADMIN','ADM_A_INATIVO','CLIN_INEXISTENTE','VAZIO'] LOOP
    vis := c IN ('ENC_E','ADM_A','REC_A','MED_A','PAC_A');
    PERFORM pg_temp.sonda('b','E1 '||CASE WHEN vis THEN 'visivel' ELSE 'invisivel' END,c,CASE WHEN vis THEN 'POSITIVO' ELSE '0' END,
      ARRAY['select 1 from saas.encaminhamento where id=''{E1}''']);
    PERFORM pg_temp.sonda('b','historico de E1 '||CASE WHEN vis THEN 'visivel' ELSE 'invisivel' END,c,CASE WHEN vis THEN 'POSITIVO' ELSE '0' END,
      ARRAY['select 1 from saas.historico_status_encaminhamento where encaminhamento_id=''{E1}''']);
    PERFORM pg_temp.sonda('b','anexo de E1 '||CASE WHEN vis THEN 'visivel' ELSE 'invisivel' END||CASE WHEN c='SISTEMA' THEN ' (SISTEMA ve anexo PENDENTE de varredura em qualquer tenant, por desenho)' ELSE '' END,c,CASE WHEN vis THEN 'POSITIVO' WHEN c='SISTEMA' THEN 'INFO' ELSE '0' END,
      ARRAY['select 1 from saas.anexo_encaminhamento where encaminhamento_id=''{E1}''']);
    PERFORM pg_temp.sonda('b','contrarreferencia de E1 '||CASE WHEN vis THEN 'visivel' ELSE 'invisivel' END,c,CASE WHEN vis THEN 'POSITIVO' ELSE '0' END,
      ARRAY['select 1 from saas.contrarreferencia where encaminhamento_id=''{E1}''']);
    PERFORM pg_temp.sonda('b','motivo_cifrado de E1 '||CASE WHEN vis THEN 'legivel' ELSE 'ilegivel' END,c,CASE WHEN vis THEN 'POSITIVO' ELSE '0' END,
      ARRAY['select motivo_cifrado from saas.encaminhamento where id=''{E1}''']);
    PERFORM pg_temp.sonda('b','atualizar E1 '||CASE WHEN vis AND c<>'MED_A' AND c<>'REC_A' THEN '' ELSE '' END,c,
      CASE WHEN vis THEN 'INFO' ELSE 'NEGADO' END, ARRAY['update saas.encaminhamento set urgencia=''URGENTE'' where id=''{E1}''']);
  END LOOP;
  -- E3: destino A SEM consentimento: so origem e paciente; nem a propria clinica destino
  FOREACH c IN ARRAY ARRAY['ENC_E','PAC_X','ADM_A','REC_A','MED_A','ADM_B','PAC_A','PAC_B','ENC_E2','SISTEMA'] LOOP
    vis := c IN ('ENC_E','PAC_X');
    PERFORM pg_temp.sonda('b','E3 (destino A sem consentimento) '||CASE WHEN vis THEN 'visivel' ELSE 'invisivel' END,c,CASE WHEN vis THEN 'POSITIVO' ELSE '0' END,
      ARRAY['select 1 from saas.encaminhamento where id=''{E3}''']);
  END LOOP;
  -- E2: espelho (destino B)
  FOREACH c IN ARRAY ARRAY['ENC_E','ADM_B','MED_B','PAC_B','ADM_A','REC_A','MED_A','PAC_A','PAC_X','ENC_E2'] LOOP
    vis := c IN ('ENC_E','ADM_B','MED_B','PAC_B');
    PERFORM pg_temp.sonda('b','E2 '||CASE WHEN vis THEN 'visivel' ELSE 'invisivel' END,c,CASE WHEN vis THEN 'POSITIVO' ELSE '0' END,
      ARRAY['select 1 from saas.encaminhamento where id=''{E2}''']);
  END LOOP;
  -- paciente visivel so por vinculo ou por encaminhamento visivel
  PERFORM pg_temp.sonda('b','paciente pacA visivel a A (vinculo)','ADM_A','POSITIVO',ARRAY['select 1 from saas.paciente where id=''{pacA}''']);
  PERFORM pg_temp.sonda('b','paciente pacB invisivel a A','ADM_A','0',ARRAY['select 1 from saas.paciente where id=''{pacB}''']);
  PERFORM pg_temp.sonda('b','paciente pacA invisivel a B','ADM_B','0',ARRAY['select 1 from saas.paciente where id=''{pacA}''']);
  PERFORM pg_temp.sonda('b','paciente pacX invisivel a A (E3 sem consentimento)','ADM_A','0',ARRAY['select 1 from saas.paciente where id=''{pacX}''']);
  PERFORM pg_temp.sonda('b','paciente pacA invisivel a PAC_B','PAC_B','0',ARRAY['select 1 from saas.paciente where id=''{pacA}''']);
  PERFORM pg_temp.sonda('b','pacA visivel ao encaminhador origem (via E1)','ENC_E','POSITIVO',ARRAY['select 1 from saas.paciente where id=''{pacA}''']);
  PERFORM pg_temp.sonda('b','pacA invisivel a outro encaminhador','ENC_E2','0',ARRAY['select 1 from saas.paciente where id=''{pacA}''']);
  -- link publico: so a linha do proprio token
  PERFORM pg_temp.sonda('b','link publico ve so o proprio link','LINK_E1','POSITIVO',ARRAY['select 1 from saas.link_paciente']);
  PERFORM pg_temp.sonda('b','link publico nao ve link de E2','LINK_E1','0',ARRAY['select 1 from saas.link_paciente where encaminhamento_id=''{E2}''']);
  PERFORM pg_temp.sonda('b','link publico nao ve encaminhamento','LINK_E1','0',ARRAY['select 1 from saas.encaminhamento']);
  -- SISTEMA: so expirados
  PERFORM pg_temp.sonda('b','SISTEMA ve so expirados (E7)','SISTEMA','POSITIVO',ARRAY['select 1 from saas.encaminhamento where id=''{E7}''']);
  PERFORM pg_temp.sonda('b','SISTEMA nao ve nao-expirados (E1)','SISTEMA','0',ARRAY['select 1 from saas.encaminhamento where id in (''{E1}'',''{E2}'',''{E3}'',''{E5}'')']);
END $$;
-- revogar consentimento retira o acesso da clinica destino (E5)
SELECT pg_temp.sonda('b','antes de revogar: A ve E5','ADM_A','POSITIVO',ARRAY['select 1 from saas.encaminhamento where id=''{E5}''']);
SELECT pg_temp.sonda('b','paciente revoga consentimento de E5; A deixa de ver E5','PAC_A','0',
  ARRAY['update saas.consentimento set revogado_em=now() where encaminhamento_id=''{E5}'' and finalidade=''COMPARTILHAR_CASO''','ctx:ADM_A'],
  'select count(*) from saas.encaminhamento where id=''{E5}''');
-- terceiros nao agem sobre E1
SELECT pg_temp.sonda('b','outro encaminhador nao emite link para E1','ENC_E2','ERRO',ARRAY['insert into saas.link_paciente(encaminhamento_id,paciente_id,token_hash,expira_em) values (''{E1}'',''{pacA}'',''\x77'',now()+interval ''1 day'')']);
SELECT pg_temp.sonda('b','outro encaminhador nao anexa em E1','ENC_E2','ERRO',ARRAY['insert into saas.anexo_encaminhamento(encaminhamento_id,chave_storage,tipo_mime,tamanho_bytes,sha256,enviado_por_tipo,enviado_por_id) values (''{E1}'',''obj-y'',''application/pdf'',1,''\x01'',''PROFISSIONAL'',''{pE2}'')']);
SELECT pg_temp.sonda('b','PAC_B nao anexa em E1','PAC_B','ERRO',ARRAY['insert into saas.anexo_encaminhamento(encaminhamento_id,chave_storage,tipo_mime,tamanho_bytes,sha256,enviado_por_tipo,enviado_por_id) values (''{E1}'',''obj-z'',''application/pdf'',1,''\x01'',''PACIENTE'',''{pacB}'')']);
SELECT pg_temp.sonda('b','MED_B nao grava contrarreferencia de E1','MED_B','ERRO',ARRAY['insert into saas.contrarreferencia(encaminhamento_id,clinica_id,autor_profissional_id,conduta_cifrada) values (''{E1}'',''{cB}'',''{pB}'',''\xff'')']);
SELECT pg_temp.sonda('b','MED_A nao grava contrarreferencia de E2 (destino B)','MED_A','ERRO',ARRAY['insert into saas.contrarreferencia(encaminhamento_id,clinica_id,autor_profissional_id,conduta_cifrada) values (''{E2}'',''{cA}'',''{pA}'',''\xff'')']);
SELECT pg_temp.sonda('b','controle: MED_A grava contrarreferencia de E1 (destino A)','MED_A','POSITIVO',ARRAY['insert into saas.contrarreferencia(encaminhamento_id,clinica_id,autor_profissional_id,conduta_cifrada) values (''{E1}'',''{cA}'',''{pA}'',''\xff'')']);
SELECT pg_temp.sonda('b','terceiro nao atualiza E1 (PAC_B)','PAC_B','NEGADO',ARRAY['update saas.encaminhamento set urgencia=''URGENTE'' where id=''{E1}''']);
SELECT pg_temp.sonda('b','terceiro nao atualiza E1 (ADM_B)','ADM_B','NEGADO',ARRAY['update saas.encaminhamento set urgencia=''URGENTE'' where id=''{E1}''']);
SELECT pg_temp.sonda('b','terceiro nao atualiza E1 (ENC_E2)','ENC_E2','NEGADO',ARRAY['update saas.encaminhamento set urgencia=''URGENTE'' where id=''{E1}''']);
SELECT pg_temp.sonda('b','terceiro nao apaga E1 (todos os papeis)','ADM_A','NEGADO',ARRAY['delete from saas.encaminhamento where id=''{E1}''']);

-- ---------------------------------------------------------------------
-- (e) auditoria e historico so de inclusao
-- ---------------------------------------------------------------------
DO $$ DECLARE c text; t text; BEGIN
  FOREACH c IN ARRAY ARRAY['ADM_A','ADM_B','SISTEMA','ENC_E','PAC_A'] LOOP
    FOREACH t IN ARRAY ARRAY['evento_auditoria','historico_status_encaminhamento'] LOOP
      PERFORM pg_temp.sonda('e','UPDATE em '||t,c,'NEGADO',ARRAY[format('update saas.%I set id=id',t)]);
      PERFORM pg_temp.sonda('e','DELETE em '||t,c,'NEGADO',ARRAY[format('delete from saas.%I',t)]);
      PERFORM pg_temp.sonda('e','TRUNCATE em '||t,c,'ERRO',ARRAY[format('truncate saas.%I',t)]);
    END LOOP;
  END LOOP;
  -- erro especifico: permissao negada (privilegio) e nao apenas RLS
  PERFORM pg_temp.sonda('e','UPDATE auditoria da propria clinica: permission denied','ADM_A','ERRO',ARRAY['update saas.evento_auditoria set acao=''APAGADO'' where clinica_id=''{cA}''']);
  PERFORM pg_temp.sonda('e','DELETE auditoria da propria clinica: permission denied','ADM_A','ERRO',ARRAY['delete from saas.evento_auditoria where clinica_id=''{cA}''']);
  PERFORM pg_temp.sonda('e','controle: INSERT em auditoria funciona','ADM_A','POSITIVO',ARRAY['insert into saas.evento_auditoria(ator_papel,clinica_id,acao,recurso_tipo) values (''ADMIN'',''{cA}'',''X'',''X'')']);
END $$;

-- ---------------------------------------------------------------------
-- (f) bordas
-- ---------------------------------------------------------------------
SELECT pg_temp.sonda('f','clinica_id NULL em agendamento','ADM_A','ERRO',ARRAY['insert into saas.agendamento(clinica_id,profissional_clinica_id,paciente_id,inicio,fim,origem,chave_idempotencia) values (NULL,''{pcA}'',''{pacA}'',now()+interval ''60 days'',now()+interval ''60 days 30 min'',''RECEPCAO'',''n1'')']);
SELECT pg_temp.sonda('f','clinica_id NULL em horario_atendimento','ADM_A','ERRO',ARRAY['insert into saas.horario_atendimento(clinica_id,profissional_clinica_id,dia_semana,hora_inicio,hora_fim) values (NULL,''{pcA}'',2,''08:00'',''09:00'')']);
SELECT pg_temp.sonda('f','clinica_id NULL em paciente_clinica','ADM_A','ERRO',ARRAY['insert into saas.paciente_clinica(paciente_id,clinica_id) values (''{pacX}'',NULL)']);
SELECT pg_temp.sonda('f','clinica_id NULL em vaga_encaminhamento','ADM_A','ERRO',ARRAY['insert into saas.vaga_encaminhamento(clinica_id,profissional_clinica_id,inicio,fim) values (NULL,''{pcA}'',now()+interval ''60 days'',now()+interval ''61 days'')']);
SELECT pg_temp.sonda('f','clinica_id NULL em profissional_clinica','ADM_A','ERRO',ARRAY['insert into saas.profissional_clinica(profissional_id,clinica_id) values (''{pE}'',NULL)']);
SELECT pg_temp.sonda('f','clinica_id NULL em consentimento (COMPARTILHAR_CASO exige)','PAC_A','ERRO',ARRAY['insert into saas.consentimento(paciente_id,finalidade,encaminhamento_id,clinica_id,texto_aceito,versao_texto,canal) values (''{pacA}'',''COMPARTILHAR_CASO'',''{E1}'',NULL,''t'',''v1'',''SITE'')']);
-- clinica_id NULL em evento_auditoria e permitido pelo desenho (evento sem tenant): INFO
SELECT pg_temp.sonda('f','clinica_id NULL em evento_auditoria (permitido por desenho)','ADM_A','INFO',ARRAY['insert into saas.evento_auditoria(ator_papel,clinica_id,acao,recurso_tipo) values (''ADMIN'',NULL,''X'',''X'')']);
SELECT pg_temp.sonda('f','UUID inexistente como clinica_id: nada visivel','CLIN_INEXISTENTE','0',ARRAY['select 1 from saas.agendamento']);
SELECT pg_temp.sonda('f','UUID inexistente: insert em agendamento (clinica_id inexistente)','CLIN_INEXISTENTE','ERRO',ARRAY['insert into saas.agendamento(clinica_id,profissional_clinica_id,paciente_id,inicio,fim,origem,chave_idempotencia) values (''{morta}'',''{pcA}'',''{pacA}'',now()+interval ''60 days'',now()+interval ''60 days 30 min'',''RECEPCAO'',''m1'')']);
SELECT pg_temp.sonda('f','UUID inexistente no contexto, insert com clinica A','CLIN_INEXISTENTE','ERRO',ARRAY['insert into saas.agendamento(clinica_id,profissional_clinica_id,paciente_id,inicio,fim,origem,chave_idempotencia) values (''{cA}'',''{pcA}'',''{pacA}'',now()+interval ''60 days'',now()+interval ''60 days 30 min'',''RECEPCAO'',''m2'')']);
SELECT pg_temp.sonda('f','ctx forjado: usuario de A com clinica_id de B nao ve B','ADM_A_NA_CLIN_B','0',ARRAY['select 1 from saas.agendamento']);
SELECT pg_temp.sonda('f','ctx forjado: usuario de A com clinica_id de B nao insere em B','ADM_A_NA_CLIN_B','ERRO',ARRAY['insert into saas.agendamento(clinica_id,profissional_clinica_id,paciente_id,inicio,fim,origem,chave_idempotencia) values (''{cB}'',''{pcB}'',''{pacB}'',now()+interval ''60 days'',now()+interval ''60 days 30 min'',''RECEPCAO'',''f1'')']);
SELECT pg_temp.sonda('f','recepcao fingindo papel ADMIN (usuario_clinica manda no papel)','REC_A_FINGE_ADMIN','0',ARRAY['select 1 from saas.agendamento']);
SELECT pg_temp.sonda('f','usuario inativo na clinica nao ve nada','ADM_A_INATIVO','0',ARRAY['select 1 from saas.agendamento']);
-- mover linha de clinica via UPDATE
DO $$ DECLARE c text; BEGIN
  FOREACH c IN ARRAY ARRAY['ADM_A','REC_A','MED_A'] LOOP
    PERFORM pg_temp.sonda('f','UPDATE agendamento SET clinica_id=B (mover linha)',c,'NEGADO',ARRAY['update saas.agendamento set clinica_id=''{cB}'' where clinica_id=''{cA}''']);
    PERFORM pg_temp.sonda('f','UPDATE profissional_clinica SET clinica_id=B',c,'NEGADO',ARRAY['update saas.profissional_clinica set clinica_id=''{cB}'' where clinica_id=''{cA}''']);
    PERFORM pg_temp.sonda('f','UPDATE horario_atendimento SET clinica_id=B',c,'NEGADO',ARRAY['update saas.horario_atendimento set clinica_id=''{cB}'' where clinica_id=''{cA}''']);
    PERFORM pg_temp.sonda('f','UPDATE paciente_clinica SET clinica_id=B',c,'NEGADO',ARRAY['update saas.paciente_clinica set clinica_id=''{cB}'' where clinica_id=''{cA}''']);
    PERFORM pg_temp.sonda('f','UPDATE vaga_encaminhamento SET clinica_id=B',c,'NEGADO',ARRAY['update saas.vaga_encaminhamento set clinica_id=''{cB}'' where clinica_id=''{cA}''']);
    PERFORM pg_temp.sonda('f','UPDATE usuario_clinica SET clinica_id=B',c,'NEGADO',ARRAY['update saas.usuario_clinica set clinica_id=''{cB}'' where clinica_id=''{cA}''']);
    PERFORM pg_temp.sonda('f','UPDATE flag_clinica SET clinica_id=B',c,'NEGADO',ARRAY['update saas.flag_clinica set clinica_id=''{cB}'' where clinica_id=''{cA}''']);
    PERFORM pg_temp.sonda('f','UPDATE clinica SET id=B',c,'NEGADO',ARRAY['update saas.clinica set id=''{cB}'' where id=''{cA}''']);
    PERFORM pg_temp.sonda('f','UPDATE clinica B (nome)',c,'NEGADO',ARRAY['update saas.clinica set nome=''pwn'' where id=''{cB}''']);
  END LOOP;
  PERFORM pg_temp.sonda('f','UPDATE consentimento SET clinica_id (sem privilegio de coluna)','PAC_A','ERRO',ARRAY['update saas.consentimento set clinica_id=''{cB}'' where paciente_id=''{pacA}''']);
END $$;
-- FK composta: referencia entre tenants para profissional_clinica
SELECT pg_temp.sonda('f','FK composta: agendamento(clinica A) -> profissional_clinica de B','ADM_A','ERRO',ARRAY['insert into saas.agendamento(clinica_id,profissional_clinica_id,paciente_id,inicio,fim,origem,chave_idempotencia) values (''{cA}'',''{pcB}'',''{pacA}'',now()+interval ''60 days'',now()+interval ''60 days 30 min'',''RECEPCAO'',''fk1'')']);
SELECT pg_temp.sonda('f','FK composta: horario(clinica A) -> profissional_clinica de B','ADM_A','ERRO',ARRAY['insert into saas.horario_atendimento(clinica_id,profissional_clinica_id,dia_semana,hora_inicio,hora_fim) values (''{cA}'',''{pcB}'',2,''08:00'',''09:00'')']);
SELECT pg_temp.sonda('f','FK composta: vaga(clinica A) -> profissional_clinica de B','ADM_A','ERRO',ARRAY['insert into saas.vaga_encaminhamento(clinica_id,profissional_clinica_id,inicio,fim) values (''{cA}'',''{pcB}'',now()+interval ''60 days'',now()+interval ''61 days'')']);
SELECT pg_temp.sonda('f','FK composta: UPDATE agendamento aponta profissional_clinica de B','ADM_A','NEGADO',ARRAY['update saas.agendamento set profissional_clinica_id=''{pcB}'' where clinica_id=''{cA}''']);
-- FK simples ignora RLS: o que um tenant consegue fazer com UUID de outro tenant
SELECT pg_temp.sonda('f','FK simples: agendamento(A) -> paciente_id de paciente so de B','ADM_A','ERRO',ARRAY['insert into saas.agendamento(clinica_id,profissional_clinica_id,paciente_id,inicio,fim,origem,chave_idempotencia) values (''{cA}'',''{pcA}'',''{pacB}'',now()+interval ''60 days'',now()+interval ''60 days 30 min'',''RECEPCAO'',''fk2'')']);
SELECT pg_temp.sonda('f','FK simples: oraculo de existencia (UUID inexistente x existente em outro tenant)','ADM_A','INFO',ARRAY['insert into saas.agendamento(clinica_id,profissional_clinica_id,paciente_id,inicio,fim,origem,chave_idempotencia) values (''{cA}'',''{pcA}'',''{morta}'',now()+interval ''60 days'',now()+interval ''60 days 30 min'',''RECEPCAO'',''fk3'')']);
SELECT pg_temp.sonda('f','FK simples: agendamento(A) origem ENCAMINHAMENTO apontando E2 (de B)','ADM_A','ERRO',ARRAY['insert into saas.agendamento(clinica_id,profissional_clinica_id,paciente_id,inicio,fim,origem,encaminhamento_id,chave_idempotencia) values (''{cA}'',''{pcA}'',''{pacA}'',now()+interval ''60 days'',now()+interval ''60 days 30 min'',''ENCAMINHAMENTO'',''{E2}'',''fk4'')']);
-- vazamento via vinculo forjado: depois de vincular paciente alheio por UUID, a clinica passa a ler a pessoa
SELECT pg_temp.sonda('f','paciente_clinica(A, pacB) por UUID: A passa a ler dados de pacB?','REC_A','0',
  ARRAY['insert into saas.paciente_clinica(paciente_id,clinica_id) values (''{pacB}'',''{cA}'')'],
  'select count(*) from saas.paciente where id=''{pacB}''');
SELECT pg_temp.sonda('f','encaminhamento criado com paciente_id de B por UUID: origem passa a ler pacB?','ENC_E','0',
  ARRAY['insert into saas.encaminhamento(profissional_origem_id,paciente_id,especialidade_destino_id,motivo_cifrado,urgencia,expira_em) values (''{pE}'',''{pacB}'',''{eC}'',''\x00'',''ROTINA'',now()+interval ''1 day'')'],
  'select count(*) from saas.paciente where id=''{pacB}''');
SELECT pg_temp.sonda('f','mesmo vazamento por MEDICO da clinica A (papel MEDICO + profissional proprio)','MED_A','0',
  ARRAY['insert into saas.encaminhamento(profissional_origem_id,paciente_id,especialidade_destino_id,motivo_cifrado,urgencia,expira_em) values (''{pA}'',''{pacB}'',''{eC}'',''\x00'',''ROTINA'',now()+interval ''1 day'')'],
  'select count(*) from saas.paciente where id=''{pacB}''');
SELECT pg_temp.sonda('f','UPDATE E1.paciente_id := pacB pela origem: origem passa a ler pacB?','ENC_E','0',
  ARRAY['update saas.encaminhamento set paciente_id=''{pacB}'' where id=''{E1}'''],
  'select count(*) from saas.paciente where id=''{pacB}''');
SELECT pg_temp.sonda('f','consentimento forjado por PAC_A para E3 (de pacX): A passa a ver E3?','PAC_A','0',
  ARRAY['insert into saas.consentimento(paciente_id,finalidade,encaminhamento_id,clinica_id,texto_aceito,versao_texto,canal) values (''{pacA}'',''COMPARTILHAR_CASO'',''{E3}'',''{cA}'',''t'',''v1'',''SITE'')','ctx:ADM_A'],
  'select count(*) from saas.encaminhamento where id=''{E3}''');
SELECT pg_temp.sonda('f','consentimento forjado por PAC_B para E1 (de pacA) em nome da clinica B: B passa a ver E1?','PAC_B','0',
  ARRAY['insert into saas.consentimento(paciente_id,finalidade,encaminhamento_id,clinica_id,texto_aceito,versao_texto,canal) values (''{pacB}'',''COMPARTILHAR_CASO'',''{E1}'',''{cB}'',''t'',''v1'',''SITE'')','ctx:ADM_B'],
  'select count(*) from saas.encaminhamento where id=''{E1}''');
SELECT pg_temp.sonda('f','historico forjado: PAC_A insere linha de historico em E1 (autor/papel livres)','PAC_A','ERRO',
  ARRAY['insert into saas.historico_status_encaminhamento(encaminhamento_id,status_anterior,status_novo,autor_papel,autor_id) values (''{E1}'',''AGENDADO'',''ATENDIDO'',''MEDICO'',''{pA}'')']);
SELECT pg_temp.sonda('f','historico forjado: ENC_E insere linha de historico em E1','ENC_E','ERRO',
  ARRAY['insert into saas.historico_status_encaminhamento(encaminhamento_id,status_anterior,status_novo,autor_papel,autor_id) values (''{E1}'',''AGENDADO'',''ATENDIDO'',''MEDICO'',''{pA}'')']);
SELECT pg_temp.sonda('f','PAC_A altera motivo_cifrado de E1 (dado clinico do medico)','PAC_A','NEGADO',ARRAY['update saas.encaminhamento set motivo_cifrado=''\x00'' where id=''{E1}''']);
SELECT pg_temp.sonda('f','destino (ADM_A) altera motivo_cifrado de E1','ADM_A','NEGADO',ARRAY['update saas.encaminhamento set motivo_cifrado=''\x00'' where id=''{E1}''']);
SELECT pg_temp.sonda('f','PAC_A troca profissional_origem_id de E1 por si/outro','PAC_A','NEGADO',ARRAY['update saas.encaminhamento set profissional_origem_id=''{pE2}'' where id=''{E1}''']);
SELECT pg_temp.sonda('f','profissional global: A le telefone/e-mail de profissional so de B (INFO, global por desenho)','ADM_A','INFO',ARRAY['select 1 from saas.profissional where id=''{pB}''']);

-- ---------------------------------------------------------------------
-- (d) set_config(is_local=true) nao vaza entre transacoes
-- ---------------------------------------------------------------------
DO $$
DECLARE r text; n bigint; k_a text := (SELECT id FROM pg_temp.k WHERE nome='cA'); k_u text := (SELECT id FROM pg_temp.k WHERE nome='uA');
BEGIN
  COMMIT;
  PERFORM set_config('app.clinica_id', k_a, true); PERFORM set_config('app.usuario', k_u, true); PERFORM set_config('app.papel','ADMIN',true);
  SELECT count(*) INTO n FROM saas.agendamento;
  INSERT INTO pg_temp.res(secao,nome,ctx,esperado,obtido,ok) VALUES ('d','transacao 1 com contexto A enxerga linhas','local','POSITIVO',n::text,n>0);
  COMMIT;   -- fim da transacao: is_local=true deve expirar
  SELECT count(*) INTO n FROM saas.agendamento;
  INSERT INTO pg_temp.res(secao,nome,ctx,esperado,obtido,ok) VALUES ('d','transacao 2 (apos COMMIT) nao enxerga nada','local','0',n::text,n=0);
  r := current_setting('app.clinica_id', true);
  INSERT INTO pg_temp.res(secao,nome,ctx,esperado,obtido,ok) VALUES ('d','app.clinica_id apos COMMIT e vazio/nulo','local','vazio',coalesce('"'||r||'"','NULL'),coalesce(r,'')='');
  COMMIT;
  PERFORM set_config('app.clinica_id', k_a, true); PERFORM set_config('app.usuario', k_u, true); PERFORM set_config('app.papel','ADMIN',true);
  ROLLBACK;
  SELECT count(*) INTO n FROM saas.agendamento;
  INSERT INTO pg_temp.res(secao,nome,ctx,esperado,obtido,ok) VALUES ('d','apos ROLLBACK o contexto some','local','0',n::text,n=0);
  COMMIT;
  -- controle negativo (nao e falha do modelo): is_local=false vaza para as proximas transacoes da mesma conexao
  PERFORM set_config('app.clinica_id', k_a, false); PERFORM set_config('app.usuario', k_u, false); PERFORM set_config('app.papel','ADMIN',false);
  COMMIT;
  SELECT count(*) INTO n FROM saas.agendamento;
  INSERT INTO pg_temp.res(secao,nome,ctx,esperado,obtido,ok) VALUES ('d','CONTROLE NEGATIVO: set_config(...,false) vaza entre transacoes (pool!)','sessao','INFO',n::text,NULL);
  PERFORM set_config('app.clinica_id','',false); PERFORM set_config('app.usuario','',false); PERFORM set_config('app.papel','',false);
  COMMIT;
  SELECT count(*) INTO n FROM saas.agendamento;
  INSERT INTO pg_temp.res(secao,nome,ctx,esperado,obtido,ok) VALUES ('d','limpeza do controle: contexto vazio nega de novo','sessao','0',n::text,n=0);
  COMMIT;
END $$;

-- ---------------------------------------------------------------------
-- maquina de estados: so reporte (o banco impoe o par de/para?)
-- ---------------------------------------------------------------------
SELECT pg_temp.sonda('estados','ENC_E: CRIADO -> ATENDIDO (pulo T4/T5, ator sem permissao)','ENC_E','INFO',ARRAY['update saas.encaminhamento set status=''ATENDIDO'' where id=''{E1}''']);
SELECT pg_temp.sonda('estados','ENC_E: CRIADO -> CONTRARREFERIDO (origem finge contrarreferencia)','ENC_E','INFO',ARRAY['update saas.encaminhamento set status=''CONTRARREFERIDO'' where id=''{E1}''']);
SELECT pg_temp.sonda('estados','PAC_A: CRIADO -> ATENDIDO','PAC_A','INFO',ARRAY['update saas.encaminhamento set status=''ATENDIDO'' where id=''{E1}''']);
SELECT pg_temp.sonda('estados','PAC_A: CRIADO -> SOLICITADO sem passar por link/consentimento (T3 pulado)','PAC_A','INFO',ARRAY['update saas.encaminhamento set status=''SOLICITADO'' where id=''{E1}''']);
SELECT pg_temp.sonda('estados','ADM_A (destino): CRIADO -> AGENDADO sem agendamento','ADM_A','INFO',ARRAY['update saas.encaminhamento set status=''AGENDADO'' where id=''{E1}''']);
SELECT pg_temp.sonda('estados','ENC_E: estado final CANCELADO -> CRIADO (ressuscitar E6)','ENC_E','INFO',ARRAY['update saas.encaminhamento set status=''CRIADO'' where id=''{E6}''']);
SELECT pg_temp.sonda('estados','ENC_E: estado final CANCELADO -> AGENDADO','ENC_E','INFO',ARRAY['update saas.encaminhamento set status=''AGENDADO'' where id=''{E6}''']);
SELECT pg_temp.sonda('estados','SISTEMA: expirado E7 -> ATENDIDO (so EXPIRADO permitido pela politica)','SISTEMA','NEGADO',ARRAY['update saas.encaminhamento set status=''ATENDIDO'' where id=''{E7}''']);
SELECT pg_temp.sonda('estados','SISTEMA: expirado E7 -> EXPIRADO (T8, legitimo)','SISTEMA','POSITIVO',ARRAY['update saas.encaminhamento set status=''EXPIRADO'' where id=''{E7}''']);
SELECT pg_temp.sonda('estados','SISTEMA: T8 sem WHERE na coluna lida (UPDATE ... SET status=EXPIRADO)','SISTEMA','POSITIVO',ARRAY['update saas.encaminhamento set status=''EXPIRADO''']);
SELECT pg_temp.sonda('estados','SISTEMA: T8 por criterio expira_em < now()','SISTEMA','POSITIVO',ARRAY['update saas.encaminhamento set status=''EXPIRADO'' where expira_em < now() and status in (''CRIADO'',''ENVIADO_AO_PACIENTE'',''SOLICITADO'')']);
SELECT pg_temp.sonda('estados','status fora dos 8 valores (CHECK)','ENC_E','ERRO',ARRAY['update saas.encaminhamento set status=''INVENTADO'' where id=''{E1}''']);
SELECT pg_temp.sonda('estados','INSERT direto em status AGENDADO (policy exige CRIADO)','ENC_E','ERRO',ARRAY['insert into saas.encaminhamento(profissional_origem_id,paciente_id,especialidade_destino_id,motivo_cifrado,urgencia,status,expira_em) values (''{pE}'',''{pacA}'',''{eC}'',''\x00'',''ROTINA'',''AGENDADO'',now()+interval ''1 day'')']);
SELECT pg_temp.sonda('estados','transicao ilegal deixa rastro no historico (gatilho registra de/para)','ENC_E','INFO',
  ARRAY['update saas.encaminhamento set status=''CONTRARREFERIDO'' where id=''{E1}'''],
  'select count(*) from saas.historico_status_encaminhamento where encaminhamento_id=''{E1}'' and status_novo=''CONTRARREFERIDO''');
\o
SELECT t.tgname AS gatilho_em_encaminhamento, pg_get_triggerdef(t.oid) AS definicao
  FROM pg_trigger t WHERE t.tgrelid='saas.encaminhamento'::regclass AND NOT t.tgisinternal ORDER BY 1;
SELECT conname AS constraint_em_encaminhamento, pg_get_constraintdef(oid) AS definicao
  FROM pg_constraint WHERE conrelid='saas.encaminhamento'::regclass AND contype='c' ORDER BY 1;

-- ---------------------------------------------------------------------
-- relatorio
-- ---------------------------------------------------------------------
\echo
\echo '===== RESUMO POR SECAO ====='
SELECT secao, count(*) AS total, count(*) FILTER (WHERE ok) AS passou, count(*) FILTER (WHERE ok = false) AS falhou, count(*) FILTER (WHERE ok IS NULL) AS info
  FROM res GROUP BY secao ORDER BY secao;
\echo
\echo '===== FALHAS (esperado x obtido) ====='
\pset format wrapped
\pset columns 200
SELECT n, secao, nome, ctx, esperado, obtido FROM res WHERE ok = false ORDER BY n;
\echo
\echo '===== INFO (so registro; maquina de estados, catalogo global, controles) ====='
SELECT n, secao, nome, ctx, obtido FROM res WHERE ok IS NULL ORDER BY n;
\echo
\echo '===== TODAS AS SONDAS ====='
SELECT n, secao, CASE WHEN ok THEN 'PASSOU' WHEN ok = false THEN 'FALHOU' ELSE 'INFO' END AS resultado, nome, ctx, esperado, obtido FROM res ORDER BY n;
\pset format aligned

-- =====================================================================
-- PARTE 3: dono/superusuario. Gatilhos de auditoria e integridade final
-- =====================================================================
\echo
\echo '===== PARTE 3: gatilhos de inclusao-so (como dono saas_owner e como superusuario) ====='
\connect - pgtest
SET search_path = saas, public;
-- o dono tambem esta sujeito a FORCE RLS: sem politica de UPDATE/DELETE nenhuma linha e alcancada (0 linhas = negado pela RLS)
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
  BEGIN DELETE FROM historico_status_encaminhamento; GET DIAGNOSTICS n = ROW_COUNT; r := CASE WHEN n=0 THEN '0 linhas (FORCE RLS do dono)' ELSE 'APAGOU '||n||' (FALHA)' END; EXCEPTION WHEN OTHERS THEN r := 'bloqueado: '||SQLERRM; END;
  RAISE NOTICE 'owner DELETE historico -> %', r;
END $$;
RESET ROLE;
-- superusuario ignora RLS: aqui quem barra e o gatilho bloqueia_alteracao
DO $$
DECLARE r text;
BEGIN
  BEGIN UPDATE evento_auditoria SET acao='X'; r := 'EXECUTOU (FALHA)'; EXCEPTION WHEN OTHERS THEN r := 'bloqueado: '||SQLERRM; END;
  RAISE NOTICE 'superusuario UPDATE evento_auditoria -> %', r;
  BEGIN DELETE FROM evento_auditoria; r := 'EXECUTOU (FALHA)'; EXCEPTION WHEN OTHERS THEN r := 'bloqueado: '||SQLERRM; END;
  RAISE NOTICE 'superusuario DELETE evento_auditoria -> %', r;
END $$;

\echo
\echo '===== INTEGRIDADE: fotografia antes x depois (nenhuma sonda persistiu mudanca, exceto auditoria de inclusao) ====='
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
