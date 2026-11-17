-- Semente de aceite F8 (superusuario). Sessao de encaminhador com token conhecido so pelo teste (aqui so o sha256).
SET search_path = saas, public;
INSERT INTO especialidade(id,nome) VALUES ('d8000000-0000-0000-0000-000000000001','Ortopedia F8');
INSERT INTO profissional(id,crm,crm_uf,nome,telefone,canal_verificado_em) VALUES
 ('e8000000-0000-0000-0002-000000000001','F8001','PE','Dra Origem F8','+5581999998001',now()),
 ('e8000000-0000-0000-0002-000000000002','F8002','PE','Dr Outro F8','+5581999998002',now());
INSERT INTO paciente(id,nome,telefone) VALUES
 ('c8000000-0000-0000-0003-000000000001','Paciente F8','+5581988888001'),
 ('c8000000-0000-0000-0003-000000000002','Paciente F8 outro','+5581988888002');
INSERT INTO encaminhamento(id,profissional_origem_id,paciente_id,especialidade_destino_id,motivo_cifrado,urgencia,expira_em) VALUES
 ('e8000000-0000-0000-0005-000000000001','e8000000-0000-0000-0002-000000000001','c8000000-0000-0000-0003-000000000001','d8000000-0000-0000-0000-000000000001','\xf8c1','ROTINA',now()+interval '20 days'),
 ('e8000000-0000-0000-0005-000000000002','e8000000-0000-0000-0002-000000000002','c8000000-0000-0000-0003-000000000002','d8000000-0000-0000-0000-000000000001','\xf8c2','ROTINA',now()+interval '20 days');
INSERT INTO sessao(token_hash,tipo,profissional_id,expira_em) VALUES
 (decode('1755a4f235fa99021f2e80be941ea71d1f37debbad1ba55f8e84464388d7db0a','hex'),'ENCAMINHADOR','e8000000-0000-0000-0002-000000000001',now()+interval '3 hours');
INSERT INTO anexo_encaminhamento(id,encaminhamento_id,tipo_mime,tamanho_bytes,sha256,enviado_por_tipo,enviado_por_id) VALUES
 ('a8000000-0000-0000-000b-000000000001','e8000000-0000-0000-0005-000000000001','application/pdf',1000,'\xf801','PROFISSIONAL','e8000000-0000-0000-0002-000000000001'),
 ('a8000000-0000-0000-000b-000000000002','e8000000-0000-0000-0005-000000000001','image/png',2000,'\xf802','PROFISSIONAL','e8000000-0000-0000-0002-000000000001'),
 ('a8000000-0000-0000-000b-000000000003','e8000000-0000-0000-0005-000000000001','image/jpeg',3000,'\xf803','PROFISSIONAL','e8000000-0000-0000-0002-000000000001'),
 ('a8000000-0000-0000-000b-000000000004','e8000000-0000-0000-0005-000000000002','application/pdf',4000,'\xf804','PROFISSIONAL','e8000000-0000-0000-0002-000000000002');
UPDATE anexo_encaminhamento SET status_varredura = 'LIMPO', varrido_em = now() WHERE id IN ('a8000000-0000-0000-000b-000000000001','a8000000-0000-0000-000b-000000000004');
UPDATE anexo_encaminhamento SET status_varredura = 'INFECTADO', varrido_em = now() WHERE id = 'a8000000-0000-0000-000b-000000000003';
CREATE SCHEMA aceite;
CREATE FUNCTION aceite.falha_auditoria() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'auditoria indisponivel (aceite F8)'; END $$;
