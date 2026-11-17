-- Semente de aceite F7 (superusuario). Sessoes com token conhecido so pelo teste: aqui so o sha256
-- (o token em si nunca passa pelo banco antes da aplicacao). Dados ficticios.
SET search_path = saas, public;
CREATE EXTENSION IF NOT EXISTS pg_stat_statements WITH SCHEMA public;
INSERT INTO clinica(id,nome) VALUES ('a7000000-0000-0000-0000-000000000001','Clinica F7 A'),('b7000000-0000-0000-0000-000000000001','Clinica F7 B');
INSERT INTO usuario(id,sub_oidc,nome,email) VALUES
 ('a7000000-0000-0000-0001-000000000001','f7-admA','Adm F7 A','a7@exemplo.invalid'),
 ('a7000000-0000-0000-0001-000000000002','f7-recA','Rec F7 A','r7@exemplo.invalid'),
 ('b7000000-0000-0000-0001-000000000001','f7-admB','Adm F7 B','b7@exemplo.invalid');
INSERT INTO usuario_clinica(usuario_id,clinica_id,papel) VALUES
 ('a7000000-0000-0000-0001-000000000001','a7000000-0000-0000-0000-000000000001','ADMIN'),
 ('a7000000-0000-0000-0001-000000000002','a7000000-0000-0000-0000-000000000001','RECEPCAO'),
 ('b7000000-0000-0000-0001-000000000001','b7000000-0000-0000-0000-000000000001','ADMIN');
INSERT INTO sessao(token_hash,tipo,usuario_id,expira_em) VALUES
 (decode('377e15efdc9e493f8e1b6ab832acc34ae8f50a4b56e8d0e17bc71cf884848104','hex'),'EQUIPE','a7000000-0000-0000-0001-000000000001',now()+interval '3 hours'),
 (decode('5f2e1a1fb9a0bc26f0f4e75e1af891f569f9de8f14c20c8b1bd2eb433aaccd8a','hex'),'EQUIPE','a7000000-0000-0000-0001-000000000002',now()+interval '3 hours'),
 (decode('fdd64f7423a9bc064e56a085573bf51ff5ea77e8d99322ca7afb7bb58c2b72c1','hex'),'EQUIPE','b7000000-0000-0000-0001-000000000001',now()+interval '3 hours');
INSERT INTO evento_auditoria(id,ator_papel,clinica_id,acao,recurso_tipo,recurso_id,canal) VALUES
 ('a7000000-0000-0000-000a-000000000001','ADMIN','a7000000-0000-0000-0000-000000000001','ACEITE_F7','paciente',gen_random_uuid(),'WEB'),
 ('a7000000-0000-0000-000a-000000000002','ADMIN','a7000000-0000-0000-0000-000000000001','ACEITE_F7','paciente',gen_random_uuid(),'WEB'),
 ('a7000000-0000-0000-000a-000000000003','RECEPCAO','a7000000-0000-0000-0000-000000000001','ACEITE_F7','encaminhamento',gen_random_uuid(),'WEB'),
 ('b7000000-0000-0000-000a-000000000001','ADMIN','b7000000-0000-0000-0000-000000000001','ACEITE_F7','paciente',gen_random_uuid(),'WEB'),
 ('b7000000-0000-0000-000a-000000000002','ADMIN','b7000000-0000-0000-0000-000000000001','ACEITE_F7','anexo',gen_random_uuid(),'WEB');
