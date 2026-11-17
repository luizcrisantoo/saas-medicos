-- =====================================================================
-- F3 (gates de identidade da Fase 2): T-20 (ADR-0036 2a corrigido, ADR-0037), I-22, I-23.
-- Sondas NOVAS do Arquiteto. Dados diferentes das baterias da Fase 1 de proposito.
-- Alvo: banco migrado pelo Flyway (bootstrap + db/migration). Executado como superusuario do
-- cluster efemero; cada passo conecta com o papel REAL (\c), fluxos de link e codigo pelo caminho
-- real (jobs_* com saas_jobs, paciente_* com saas_app).
-- Resultado: tabela aceite.res (crit, ok). O runner imprime VERDE/VERMELHO por criterio.
-- Legenda de esperado: NEGADO (erro, 0 linhas, NULL, false) | POSITIVO | IGUAL:x | DIFERENTE:x
-- =====================================================================
\set ON_ERROR_STOP on
\set QUIET on
\pset pager off
SET search_path = saas, public;
CREATE SCHEMA aceite;
CREATE TABLE aceite.res(n serial, crit text, descricao text, papel text, esperado text, obtido text, ok boolean);
GRANT USAGE ON SCHEMA aceite TO PUBLIC;
GRANT INSERT, SELECT ON aceite.res TO PUBLIC;
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

-- ---------------------------------------------------------------------
-- Semente (superusuario)
-- ---------------------------------------------------------------------
\set cA 'a3000000-0000-0000-0000-000000000001'
\set cB 'b3000000-0000-0000-0000-000000000001'
\set esp 'd3000000-0000-0000-0000-000000000001'
\set pfB 'e3000000-0000-0000-0002-0000000000b1'
\set pcB 'b3000000-0000-0000-0004-000000000001'
INSERT INTO clinica(id,nome) VALUES (:'cA','Clinica Aceite A'),(:'cB','Clinica Aceite B');
INSERT INTO flag_clinica(clinica_id,chave,ligada) VALUES (:'cA','REDE_ENCAMINHAMENTO',true),(:'cB','REDE_ENCAMINHAMENTO',true);
INSERT INTO especialidade(id,nome) VALUES (:'esp','Ortopedia aceite');
INSERT INTO clinica_especialidade VALUES (:'cA',:'esp'),(:'cB',:'esp');
INSERT INTO usuario(id,sub_oidc,nome,email) VALUES
 ('a3000000-0000-0000-0001-000000000002','f3-recA','Rec A','reca@exemplo.invalid'),
 ('b3000000-0000-0000-0001-000000000002','f3-recB','Rec B','recb@exemplo.invalid');
INSERT INTO usuario_clinica(usuario_id,clinica_id,papel) VALUES
 ('a3000000-0000-0000-0001-000000000002',:'cA','RECEPCAO'),
 ('b3000000-0000-0000-0001-000000000002',:'cB','RECEPCAO');
INSERT INTO profissional(id,crm,crm_uf,nome,telefone,canal_verificado_em) VALUES
 ('e3000000-0000-0000-0002-000000000001','F3001','PE','Dra Origem Aceite','+5581999993001',now()),
 ('e3000000-0000-0000-0002-000000000002','F3003','PE','Dr Outro Encaminhador','+5581999993003',now()),
 (:'pfB','F3002','PE','Dr Destino Aceite','+5581999993002',now());
INSERT INTO profissional_clinica(id,profissional_id,clinica_id,recebe_encaminhamento) VALUES (:'pcB',:'pfB',:'cB',true);
-- sessoes de teste: token conhecido so na semente (equipe e encaminhador ja verificados)
INSERT INTO sessao(token_hash,tipo,usuario_id,expira_em) VALUES
 (sha256(decode(repeat('a3',32),'hex')),'EQUIPE','a3000000-0000-0000-0001-000000000002',now()+interval '2 hours'),
 (sha256(decode(repeat('b3',32),'hex')),'EQUIPE','b3000000-0000-0000-0001-000000000002',now()+interval '2 hours');
INSERT INTO sessao(token_hash,tipo,profissional_id,expira_em) VALUES
 (sha256(decode(repeat('e3',32),'hex')),'ENCAMINHADOR','e3000000-0000-0000-0002-000000000001',now()+interval '2 hours'),
 (sha256(decode(repeat('e4',32),'hex')),'ENCAMINHADOR','e3000000-0000-0000-0002-000000000002',now()+interval '2 hours');
-- paciente cadastrado pela propria clinica B (controle de I-23)
\set ON_ERROR_STOP off

-- =====================================================================
-- T-20 no encaminhamento (escopo do encaminhador O1)
-- =====================================================================
\c - saas_app
SELECT set_config('app.sessao', repeat('e3',32), false) IS NOT NULL AS sessao_o1 \gset
SELECT encaminhamento_cria('Carla Mendes','+5581911110001',DATE '1979-03-03','\xf301','\xf3a1','d3000000-0000-0000-0000-000000000001','\xf3c1','ROTINA') AS e_a \gset
SELECT encaminhamento_cria('Bruno Mendes','+5581911110001',DATE '2015-06-06','\xf301','\xf3a1','d3000000-0000-0000-0000-000000000001','\xf3c2','URGENTE') AS e_b \gset
SELECT encaminhamento_cria('Carla Mendes','+5581911110001',DATE '1979-03-04','\xf301','\xf3a1','d3000000-0000-0000-0000-000000000001','\xf3c3','ROTINA') AS e_c \gset
SELECT encaminhamento_cria('carla   MENDES','+5581911110099',DATE '1979-03-03','\xf301','\xf3a1','d3000000-0000-0000-0000-000000000001','\xf3c4','ROTINA') AS e_d \gset
SELECT encaminhamento_cria('Carla Mendes','+5581911110001',NULL,'\xf301','\xf3a1','d3000000-0000-0000-0000-000000000001','\xf3c5','ROTINA') AS e_e \gset
SELECT encaminhamento_cria('Otavio Lins','+5581933330001',DATE '1960-07-07',NULL,NULL,'d3000000-0000-0000-0000-000000000001','\xf3c6','ROTINA') AS e_f \gset
SELECT encaminhamento_cria('Joana Reis','+5581944440001',DATE '2012-12-12',NULL,NULL,'d3000000-0000-0000-0000-000000000001','\xf3c7','PRIORITARIA') AS e_g \gset
SELECT encaminhamento_cria('Carla Mendes','+5581911110001',DATE '1979-03-03','\xf302','\xf3a9','d3000000-0000-0000-0000-000000000001','\xf3c8','ROTINA') AS e_h \gset
SELECT encaminhamento_cria('Fulana Souto','+5581911110001',DATE '1979-03-03',NULL,NULL,'d3000000-0000-0000-0000-000000000001','\xf3c9','ROTINA') AS e_i \gset
SELECT encaminhamento_cria('Carla Mendes','+5581911110001',NULL,NULL,NULL,'d3000000-0000-0000-0000-000000000001','\xf3ca','ROTINA') AS e_j \gset
SELECT set_config('app.sessao', repeat('e4',32), false) IS NOT NULL AS sessao_o2 \gset
SELECT encaminhamento_cria('Carla Mendes','+5581911110001',DATE '1979-03-03','\xf301','\xf3a1','d3000000-0000-0000-0000-000000000001','\xf3cb','ROTINA') AS e_k \gset
\c - pgtest
SET search_path = saas, public;
SELECT aceite.reg('F3.1','mesmo CPF, nome e nascimento diferentes (filho com CPF do responsavel): pacientes diferentes','IGUAL:2',
  (SELECT count(DISTINCT paciente_id)::text FROM encaminhamento WHERE id IN (:'e_a',:'e_b')));
SELECT aceite.reg('F3.1','mesmo CPF e nome, nascimento diferente por 1 dia: pacientes diferentes','IGUAL:2',
  (SELECT count(DISTINCT paciente_id)::text FROM encaminhamento WHERE id IN (:'e_a',:'e_c')));
SELECT aceite.reg('F3.1','controle: mesmo CPF, nome normalizado e nascimento iguais (telefone novo): mesma pessoa','IGUAL:1',
  (SELECT count(DISTINCT paciente_id)::text FROM encaminhamento WHERE id IN (:'e_a',:'e_d')));
SELECT aceite.reg('F3.1','controle: mesmo CPF e nome, nascimento so em um dos registros: mesma pessoa','IGUAL:1',
  (SELECT count(DISTINCT paciente_id)::text FROM encaminhamento WHERE id IN (:'e_a',:'e_e')));
SELECT aceite.reg('F3.1','regressao: nome, telefone e nascimento iguais com CPF diferente: pacientes diferentes','IGUAL:2',
  (SELECT count(DISTINCT paciente_id)::text FROM encaminhamento WHERE id IN (:'e_a',:'e_h')));
SELECT aceite.reg('F3.1','regressao: so telefone e nascimento iguais: pacientes diferentes','IGUAL:2',
  (SELECT count(DISTINCT paciente_id)::text FROM encaminhamento WHERE id IN (:'e_a',:'e_i')));
SELECT aceite.reg('F3.1','regressao: sem nascimento e sem CPF nunca deduplica','IGUAL:2',
  (SELECT count(DISTINCT paciente_id)::text FROM encaminhamento WHERE id IN (:'e_a',:'e_j')));
SELECT aceite.reg('F3.1','regressao: outro encaminhador com os dados exatos (inclusive CPF) nao alcanca o cadastro','IGUAL:2',
  (SELECT count(DISTINCT paciente_id)::text FROM encaminhamento WHERE id IN (:'e_a',:'e_k')));
SELECT aceite.reg('F3.1','cadastro original intacto (nome) depois do caso do filho','IGUAL:Carla Mendes',
  (SELECT p.nome FROM paciente p JOIN encaminhamento e ON e.paciente_id = p.id WHERE e.id = :'e_a'));
SELECT aceite.reg('F3.1','cadastro original intacto (nascimento)','IGUAL:1979-03-03',
  (SELECT p.data_nascimento::text FROM paciente p JOIN encaminhamento e ON e.paciente_id = p.id WHERE e.id = :'e_a'));
SELECT aceite.reg('F3.1','caso do filho grava o nome digitado para ele','IGUAL:Bruno Mendes',
  (SELECT p.nome FROM paciente p JOIN encaminhamento e ON e.paciente_id = p.id WHERE e.id = :'e_b'));
SELECT aceite.reg('F3.1','caso do filho grava o nascimento digitado para ele','IGUAL:2015-06-06',
  (SELECT p.data_nascimento::text FROM paciente p JOIN encaminhamento e ON e.paciente_id = p.id WHERE e.id = :'e_b'));

-- =====================================================================
-- T-20 na recepcao: coincidencia vira sugestao, nunca id
-- =====================================================================
\c - saas_app
SELECT set_config('app.sessao', repeat('a3',32), false), set_config('app.clinica_id', 'a3000000-0000-0000-0000-000000000001', false),
       set_config('app.papel', 'RECEPCAO', false) \gset
SELECT paciente_cadastra_na_clinica('Helena Prado','+5581922220001',DATE '1950-01-10','\xf3d0','\xf3d1') AS h1 \gset
SELECT aceite.val($$select paciente_cadastra_na_clinica('Helena Prado','+5581922220001',DATE '1950-01-10','\xf3d0','\xf3d1')::text$$) AS h2 \gset
SELECT aceite.val($$select paciente_cadastra_na_clinica('Ricardo Prado','+5581922220002',DATE '1990-02-02','\xf3d0','\xf3d1')::text$$) AS h3 \gset
SELECT aceite.val($$select paciente_cadastra_na_clinica('helena  prado','+5581922220001',DATE '1950-01-10',NULL,NULL)::text$$) AS h4 \gset
SELECT aceite.val($$select paciente_cadastra_na_clinica('Helena Prado','+5581922220001',DATE '1950-01-10','\xf3d8','\xf3d9')::text$$) AS h5 \gset
SELECT aceite.reg('F3.2','controle: recepcao cadastra paciente novo e recebe id','POSITIVO', :'h1');
SELECT aceite.reg('F3.2','recepcao repete os mesmos dados (nome, nascimento, telefone, CPF): nunca recebe o id existente','DIFERENTE:' || :'h1', :'h2');
SELECT aceite.reg('F3.2','recepcao: coincidencia por nome normalizado, nascimento e telefone sem CPF: nunca recebe o id existente','DIFERENTE:' || :'h1', :'h4');
SELECT aceite.reg('F3.2','regressao: recepcao, dados exatos com CPF diferente: nunca recebe o id existente','DIFERENTE:' || :'h1', :'h5');
RESET app.sessao; RESET app.clinica_id; RESET app.papel;
SELECT set_config('app.sessao', repeat('b3',32), false), set_config('app.clinica_id', 'b3000000-0000-0000-0000-000000000001', false),
       set_config('app.papel', 'RECEPCAO', false) \gset
SELECT aceite.val($$select paciente_cadastra_na_clinica('Helena Prado','+5581922220001',DATE '1950-01-10','\xf3d0','\xf3d1')::text$$) AS h6 \gset
SELECT aceite.reg('F3.2','regressao: recepcao de outra clinica com os dados exatos nao recebe o registro da clinica A','DIFERENTE:' || :'h1', :'h6');
SELECT aceite.reg('F3.2','recepcao: CPF igual de outra pessoa (nome e nascimento diferentes): nunca recebe o id dela','DIFERENTE:' || :'h1', :'h3');
\c - pgtest
SET search_path = saas, public;
SELECT aceite.reg('F3.2','cadastro de Helena intacto depois da coincidencia de CPF','IGUAL:Helena Prado|1950-01-10',
  (SELECT nome || '|' || data_nascimento FROM paciente WHERE id = :'h1'));

-- =====================================================================
-- I-22: telefone informado agora nunca e descartado em silencio
-- =====================================================================
-- lado negativo: caso SEM telefone de contato (linha gravada fora de encaminhamento_cria, como a
-- semente das baterias da Fase 1) de paciente com telefone na ficha. O envio nao pode cair no
-- telefone do cadastro: nem contato nem segredo saem, nenhum link nasce.
INSERT INTO paciente(id,nome,telefone) VALUES ('c3000000-0000-0000-0003-0000000000f1','Silvio Sem Contato','+5581955550001');
INSERT INTO encaminhamento(id,profissional_origem_id,paciente_id,especialidade_destino_id,motivo_cifrado,urgencia,expira_em)
  VALUES ('e3000000-0000-0000-0005-0000000000f1','e3000000-0000-0000-0002-000000000001','c3000000-0000-0000-0003-0000000000f1',
          :'esp','\xf3f1','ROTINA',now()+interval '10 days');
\c - saas_jobs
SELECT aceite.val($$select jobs_envio_link_paciente('e3000000-0000-0000-0005-0000000000f1')::text$$) AS env_n \gset
SELECT aceite.val(format('select contato from jobs_envio_prepara(%L::uuid)', :'env_n')) AS contato_n \gset
\c - pgtest
SET search_path = saas, public;
SELECT aceite.reg('F3.3','pre: caso sem telefone de contato tem envio de link pendente pelo caminho real (jobs)','IGUAL:1',
  (SELECT count(*)::text FROM envio_notificacao WHERE id::text = :'env_n' AND encaminhamento_id = 'e3000000-0000-0000-0005-0000000000f1'));
SELECT aceite.reg('F3.3','caso sem telefone de contato: o envio nunca sai para o telefone do cadastro','DIFERENTE:+5581955550001', :'contato_n');
SELECT aceite.reg('F3.3','caso sem telefone de contato: nenhum contato entregue (o envio nao sai)','IGUAL:true',
  (:'contato_n' = 'NULL' OR :'contato_n' LIKE 'ERRO%')::text);
SELECT aceite.reg('F3.3','caso sem telefone de contato: nenhum link (segredo) gerado','IGUAL:0',
  (SELECT count(*)::text FROM link_paciente WHERE encaminhamento_id = 'e3000000-0000-0000-0005-0000000000f1'));
SELECT aceite.reg('F3.3','caso sem telefone de contato: envio nao fica entregue nem pronto para reenvio ao cadastro','IGUAL:0',
  (SELECT count(*)::text FROM envio_notificacao WHERE encaminhamento_id = 'e3000000-0000-0000-0005-0000000000f1'
     AND (status NOT IN ('PENDENTE','FALHOU') OR link_paciente_id IS NOT NULL)));
\c - saas_jobs
SELECT aceite.val(format('select jobs_envio_link_paciente(%L)::text', :'e_d')) AS env_d \gset
SELECT aceite.val(format('select contato from jobs_envio_prepara(%L::uuid)', :'env_d')) AS contato_d \gset
SELECT aceite.reg('F3.3','link do caso novo (CPF existente, telefone novo) nunca vai ao telefone antigo do cadastro','DIFERENTE:+5581911110001', :'contato_d');
SELECT aceite.reg('F3.3','link do caso novo vai ao telefone digitado agora ou nao sai','IGUAL:true',
  (:'contato_d' IN ('+5581911110099','NULL') OR :'contato_d' LIKE 'ERRO%')::text);
SELECT aceite.val(format('select jobs_envio_link_paciente(%L)::text', :'e_f')) AS env_f \gset
SELECT aceite.val(format('select contato from jobs_envio_prepara(%L::uuid)', :'env_f')) AS contato_f \gset
SELECT aceite.reg('F3.3','controle: paciente novo recebe o link no telefone digitado','IGUAL:+5581933330001', :'contato_f');
\c - pgtest
SET search_path = saas, public;

-- =====================================================================
-- I-23: depois da revogacao, o vinculo nascido do encaminhamento nao serve a recepcao destino
-- =====================================================================
-- paciente da propria clinica B (vinculo de cadastro): controle
\c - saas_app
SELECT set_config('app.sessao', repeat('b3',32), false), set_config('app.clinica_id', 'b3000000-0000-0000-0000-000000000001', false),
       set_config('app.papel', 'RECEPCAO', false) \gset
SELECT paciente_cadastra_na_clinica('Marcos Teles','+5581955550001',DATE '1971-01-01',NULL,NULL) AS pac_mt \gset
RESET app.sessao; RESET app.clinica_id; RESET app.papel;
-- fluxo real do link de Joana (e_g)
\c - saas_jobs
SELECT jobs_envio_link_paciente(:'e_g') AS env_g \gset
SELECT segredo AS tok_g FROM jobs_envio_prepara(:'env_g') \gset
SELECT jobs_envio_resultado(:'env_g','ACEITO','aceite-g') AS t2_g \gset
\c - saas_app
SELECT paciente_pede_codigo(:'tok_g') AS pediu_g \gset
\c - saas_jobs
SELECT envio_id AS envc_g FROM jobs_envios_pendentes(100) WHERE finalidade = 'CODIGO_PACIENTE' LIMIT 1 \gset
SELECT segredo AS cod_g FROM jobs_envio_prepara(:'envc_g') \gset
\c - saas_app
SELECT paciente_confirma_codigo(:'tok_g', :'cod_g') AS sess_g \gset
SELECT set_config('app.sessao', :'sess_g', false) \gset
SELECT paciente_solicita(:'e_g', 'b3000000-0000-0000-0000-000000000001', 'e3000000-0000-0000-0002-0000000000b1', 'texto de consentimento aceite', 'aceite-v1') \gset
RESET app.sessao;
SELECT set_config('app.sessao', repeat('b3',32), false), set_config('app.clinica_id', 'b3000000-0000-0000-0000-000000000001', false),
       set_config('app.papel', 'RECEPCAO', false) \gset
SELECT destino_confirma_horario(:'e_g', 'b3000000-0000-0000-0004-000000000001', now() + interval '3 days', now() + interval '3 days 30 minutes', 'aceite-g-t4') AS ag_g \gset
SELECT paciente_id AS pac_g FROM encaminhamento WHERE id = :'e_g' \gset
SELECT aceite.reg('F3.4','controle: com consentimento ativo, recepcao destino marca consulta para o paciente do encaminhamento','POSITIVO',
  aceite.tenta(format($q$insert into agendamento(clinica_id,profissional_clinica_id,paciente_id,inicio,fim,origem,chave_idempotencia)
    values (%L,%L,%L, now() + interval '9 days', now() + interval '9 days 30 minutes','RECEPCAO','aceite-g-ag2')$q$,
    'b3000000-0000-0000-0000-000000000001','b3000000-0000-0000-0004-000000000001', :'pac_g')));
-- paciente revoga
RESET app.sessao; RESET app.clinica_id; RESET app.papel;
SELECT set_config('app.sessao', :'sess_g', false) \gset
SELECT aceite.reg('F3.4','controle: paciente revoga COMPARTILHAR_CASO','POSITIVO',
  aceite.tenta(format($q$update consentimento set revogado_em = now() where encaminhamento_id = %L and finalidade = 'COMPARTILHAR_CASO' and revogado_em is null$q$, :'e_g')));
RESET app.sessao;
SELECT set_config('app.sessao', repeat('b3',32), false), set_config('app.clinica_id', 'b3000000-0000-0000-0000-000000000001', false),
       set_config('app.papel', 'RECEPCAO', false) \gset
SELECT aceite.reg('F3.4','apos a revogacao, recepcao destino nao le o cadastro','IGUAL:0',
  aceite.val(format('select count(*)::text from paciente where id = %L', :'pac_g')));
SELECT aceite.val($$select paciente_cadastra_na_clinica('Joana Reis','+5581944440001',DATE '2012-12-12',NULL,NULL)::text$$) AS j2 \gset
SELECT aceite.reg('F3.4','apos a revogacao, cadastro com os mesmos dados nunca devolve o id do registro revogado','DIFERENTE:' || :'pac_g', :'j2');
SELECT aceite.reg('F3.4','apos a revogacao, recepcao destino marca consulta com o id revogado: negado','NEGADO',
  aceite.tenta(format($q$insert into agendamento(clinica_id,profissional_clinica_id,paciente_id,inicio,fim,origem,chave_idempotencia)
    values (%L,%L,%L, now() + interval '12 days', now() + interval '12 days 30 minutes','RECEPCAO','aceite-g-ag3')$q$,
    'b3000000-0000-0000-0000-000000000001','b3000000-0000-0000-0004-000000000001', :'pac_g')));
SELECT aceite.reg('F3.4','apos a revogacao, recepcao destino grava consentimento de WhatsApp em nome do paciente: negado','NEGADO',
  aceite.tenta(format($q$insert into consentimento(paciente_id,finalidade,clinica_id,texto_aceito,versao_texto,canal)
    values (%L,'COMUNICACAO_WHATSAPP',%L,'t','v','RECEPCAO')$q$, :'pac_g', 'b3000000-0000-0000-0000-000000000001')));
SELECT aceite.reg('F3.4','controle: paciente cadastrado pela propria clinica: recepcao marca consulta','POSITIVO',
  aceite.tenta(format($q$insert into agendamento(clinica_id,profissional_clinica_id,paciente_id,inicio,fim,origem,chave_idempotencia)
    values (%L,%L,%L, now() + interval '15 days', now() + interval '15 days 30 minutes','RECEPCAO','aceite-mt-1')$q$,
    'b3000000-0000-0000-0000-000000000001','b3000000-0000-0000-0004-000000000001', :'pac_mt')));
SELECT aceite.reg('F3.4','controle: paciente cadastrado pela propria clinica: recepcao registra consentimento','POSITIVO',
  aceite.tenta(format($q$insert into consentimento(paciente_id,finalidade,clinica_id,texto_aceito,versao_texto,canal)
    values (%L,'AGENDAMENTO',%L,'t','v','RECEPCAO')$q$, :'pac_mt', 'b3000000-0000-0000-0000-000000000001')));
\c - pgtest
SET search_path = saas, public;
SELECT crit, ok, esperado, obtido, descricao FROM aceite.res ORDER BY n;
