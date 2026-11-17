-- Semente de aceite F9 (superusuario). Sessoes com token conhecido so pelo teste (aqui so o sha256). Dados ficticios.
SET search_path = saas, public;
INSERT INTO clinica(id,nome) VALUES ('b9000000-0000-0000-0000-000000000001','Clinica F9 destino');
INSERT INTO especialidade(id,nome) VALUES ('d9000000-0000-0000-0000-000000000001','Ortopedia F9');
INSERT INTO usuario(id,sub_oidc,nome,email) VALUES ('b9000000-0000-0000-0001-000000000002','f9-recB','Rec F9','r9@exemplo.invalid');
INSERT INTO usuario_clinica(usuario_id,clinica_id,papel) VALUES ('b9000000-0000-0000-0001-000000000002','b9000000-0000-0000-0000-000000000001','RECEPCAO');
INSERT INTO profissional(id,crm,crm_uf,nome,telefone,canal_verificado_em) VALUES
 ('e9000000-0000-0000-0002-000000000001','F9001','PE','Dra Origem F9','+5581999999001',now());
INSERT INTO paciente(id,nome,telefone) VALUES
 ('c9000000-0000-0000-0003-000000000001','Paciente F9','+5581989999001'),
 ('c9000000-0000-0000-0003-000000000002','Paciente F9 outra','+5581989999002');
-- E (caso do link da sessao), E2 (outro caso da mesma paciente, sem link), E3 (caso de outra paciente)
INSERT INTO encaminhamento(id,profissional_origem_id,paciente_id,especialidade_destino_id,clinica_destino_id,motivo_cifrado,urgencia,expira_em) VALUES
 ('e9000000-0000-0000-0005-000000000001','e9000000-0000-0000-0002-000000000001','c9000000-0000-0000-0003-000000000001','d9000000-0000-0000-0000-000000000001','b9000000-0000-0000-0000-000000000001','\xf9c1','ROTINA',now()+interval '20 days'),
 ('e9000000-0000-0000-0005-000000000002','e9000000-0000-0000-0002-000000000001','c9000000-0000-0000-0003-000000000001','d9000000-0000-0000-0000-000000000001','b9000000-0000-0000-0000-000000000001','\xf9c2','ROTINA',now()+interval '20 days'),
 ('e9000000-0000-0000-0005-000000000003','e9000000-0000-0000-0002-000000000001','c9000000-0000-0000-0003-000000000002','d9000000-0000-0000-0000-000000000001','b9000000-0000-0000-0000-000000000001','\xf9c3','ROTINA',now()+interval '20 days');
INSERT INTO link_paciente(id,encaminhamento_id,paciente_id,token_hash,expira_em,usado_em) VALUES
 ('e9000000-0000-0000-0007-000000000001','e9000000-0000-0000-0005-000000000001','c9000000-0000-0000-0003-000000000001',sha256('\xf9f1'::bytea),now()+interval '1 day',now()),
 ('e9000000-0000-0000-0007-000000000003','e9000000-0000-0000-0005-000000000003','c9000000-0000-0000-0003-000000000002',sha256('\xf9f3'::bytea),now()+interval '1 day',now());
INSERT INTO sessao(token_hash,tipo,paciente_id,link_paciente_id,expira_em) VALUES
 (decode('deb1be905612fd9174f9d8fa47a026b1de25cb1bcbdebf24e8ecd244ff0747ea','hex'),'PACIENTE','c9000000-0000-0000-0003-000000000001','e9000000-0000-0000-0007-000000000001',now()+interval '25 minutes'),
 (decode('1633107147b1e85212714091aa92729a58150b8f950879c4428c32d859ea8a35','hex'),'PACIENTE','c9000000-0000-0000-0003-000000000002','e9000000-0000-0000-0007-000000000003',now()+interval '25 minutes');
INSERT INTO sessao(token_hash,tipo,usuario_id,expira_em) VALUES
 (decode('1b94733f0b38e495f8395c2613371230f0352fc1ab6d3b84f01c7b882d32eff5','hex'),'EQUIPE','b9000000-0000-0000-0001-000000000002',now()+interval '3 hours');
INSERT INTO consentimento(id,paciente_id,finalidade,encaminhamento_id,clinica_id,texto_aceito,versao_texto,canal) VALUES
 ('f9000000-0000-0000-000c-000000000003','c9000000-0000-0000-0003-000000000002','COMPARTILHAR_CASO','e9000000-0000-0000-0005-000000000003','b9000000-0000-0000-0000-000000000001','texto da outra paciente','semente','SITE');
