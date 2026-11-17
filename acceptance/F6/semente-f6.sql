-- Semente de aceite F6 (superusuario). Dados ficticios.
SET search_path = saas, public;
INSERT INTO clinica(id,nome) VALUES ('a6000000-0000-0000-0000-000000000001','Clinica F6');
INSERT INTO usuario(id,sub_oidc,nome,email,ativo) VALUES
 ('a6000000-0000-0000-0001-000000000002','f6-sub-recepcao','Rec F6','rec6@exemplo.invalid',true),
 ('a6000000-0000-0000-0001-000000000003','f6-sub-recepcao-2','Rec F6 dois','rec6b@exemplo.invalid',true),
 ('a6000000-0000-0000-0001-000000000004','f6-sub-inativo','Inativo F6','ina6@exemplo.invalid',false);
INSERT INTO usuario_clinica(usuario_id,clinica_id,papel) VALUES
 ('a6000000-0000-0000-0001-000000000002','a6000000-0000-0000-0000-000000000001','RECEPCAO'),
 ('a6000000-0000-0000-0001-000000000003','a6000000-0000-0000-0000-000000000001','RECEPCAO'),
 ('a6000000-0000-0000-0001-000000000004','a6000000-0000-0000-0000-000000000001','RECEPCAO');
