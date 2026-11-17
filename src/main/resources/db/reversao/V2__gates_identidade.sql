-- =====================================================================
-- Reversao de V2__gates_identidade.sql (executada por saas_migracao, fora do Flyway).
-- Devolve o schema saas exatamente ao estado da V1: funcoes com o texto da V1
-- (copiado sem mudanca), politicas com a expressao da V1 e sem a coluna
-- encaminhamento.telefone_contato. Por fim apaga a linha da V2 no historico do Flyway.
-- ATENCAO: reverter reabre os achados T-20, I-22 e I-23 do Red Team.
-- =====================================================================

SET ROLE saas_funcoes;
SET search_path = saas, public;

CREATE OR REPLACE FUNCTION mesma_pessoa(p paciente, p_nome text, p_telefone text, p_nascimento date, p_cpf_hash bytea)
RETURNS boolean LANGUAGE sql IMMUTABLE SET search_path = saas, pg_temp AS
$$ SELECT coalesce(
     (p_cpf_hash IS NOT NULL AND p.cpf_hash = p_cpf_hash)
     OR (p_nascimento IS NOT NULL AND p.data_nascimento = p_nascimento
         AND p.telefone = p_telefone
         AND nome_normalizado(p.nome) = nome_normalizado(p_nome)
         AND (p.cpf_hash IS NULL OR p_cpf_hash IS NULL)), false) $$;

CREATE OR REPLACE FUNCTION encaminhamento_cria(p_nome text, p_telefone text, p_nascimento date, p_cpf_cifrado bytea, p_cpf_hash bytea,
                                    p_especialidade uuid, p_motivo_cifrado bytea, p_urgencia text)
RETURNS uuid LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = saas, pg_temp AS
$$ DECLARE prof uuid := ator_profissional(); pac uuid; e uuid;
BEGIN
  IF prof IS NULL THEN RAISE EXCEPTION 'nao permitido'; END IF;
  SELECT p.id INTO pac FROM paciente p
   WHERE mesma_pessoa(p, p_nome, p_telefone, p_nascimento, p_cpf_hash)   -- r2-4: telefone sozinho nao identifica
     AND (EXISTS (SELECT 1 FROM encaminhamento x WHERE x.paciente_id = p.id AND x.profissional_origem_id = prof)
          OR (ator_tipo() = 'EQUIPE' AND EXISTS (SELECT 1 FROM paciente_clinica pc
                                                 WHERE pc.paciente_id = p.id AND pc.clinica_id = app_clinica_id()
                                                   AND pc.encaminhamento_id IS NULL)))
   ORDER BY p.criado_em LIMIT 1;
  IF pac IS NULL THEN
    INSERT INTO paciente(nome, telefone, data_nascimento, cpf_cifrado, cpf_hash)
    VALUES (p_nome, p_telefone, p_nascimento, p_cpf_cifrado, p_cpf_hash) RETURNING id INTO pac;
  END IF;
  INSERT INTO encaminhamento(profissional_origem_id, paciente_id, especialidade_destino_id, motivo_cifrado, urgencia, expira_em)
  VALUES (prof, pac, p_especialidade, p_motivo_cifrado, p_urgencia, now() + interval '30 days') RETURNING id INTO e;
  PERFORM audita('CRIAR_ENCAMINHAMENTO', 'encaminhamento', e);
  RETURN e;
END $$;

CREATE OR REPLACE FUNCTION paciente_cadastra_na_clinica(p_nome text, p_telefone text, p_nascimento date, p_cpf_cifrado bytea, p_cpf_hash bytea)
RETURNS uuid LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = saas, pg_temp AS
$$ DECLARE pac uuid;
BEGIN
  IF NOT eh_equipe(ARRAY['ADMIN','RECEPCAO']) THEN RAISE EXCEPTION 'nao permitido'; END IF;
  SELECT p.id INTO pac FROM paciente p JOIN paciente_clinica pc ON pc.paciente_id = p.id AND pc.clinica_id = app_clinica_id()
   WHERE mesma_pessoa(p, p_nome, p_telefone, p_nascimento, p_cpf_hash)   -- r2-4
   ORDER BY p.criado_em LIMIT 1;
  IF pac IS NOT NULL THEN RETURN pac; END IF;
  INSERT INTO paciente(nome, telefone, data_nascimento, cpf_cifrado, cpf_hash, cadastrado_por_clinica_id)
  VALUES (p_nome, p_telefone, p_nascimento, p_cpf_cifrado, p_cpf_hash, app_clinica_id()) RETURNING id INTO pac;
  INSERT INTO paciente_clinica(paciente_id, clinica_id) VALUES (pac, app_clinica_id());
  PERFORM audita('CADASTRAR_PACIENTE', 'paciente', pac, app_clinica_id());
  RETURN pac;
END $$;

CREATE OR REPLACE FUNCTION jobs_envio_prepara(p_envio uuid) RETURNS TABLE (canal text, contato text, segredo text)
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = saas, pg_temp AS
$$ DECLARE v envio_notificacao; tok text; cod text; lid uuid; l link_paciente; d desafio_encaminhador;
BEGIN
  SELECT * INTO v FROM envio_notificacao WHERE id = p_envio AND status = 'PENDENTE' AND tentativas < 5 FOR UPDATE;
  IF v.id IS NULL THEN RAISE EXCEPTION 'envio inexistente ou ja preparado'; END IF;
  -- r2-1 (Testador F1): rele o encaminhamento. Link so para CRIADO ou ENVIADO_AO_PACIENTE (a
  -- mesma regra de jobs_envio_link_paciente); codigo so com encaminhamento aberto. Fora disso
  -- o envio vira FALHOU e nada sai: nem segredo, nem contato.
  IF (v.finalidade = 'LINK_PACIENTE' AND NOT EXISTS (SELECT 1 FROM encaminhamento e WHERE e.id = v.encaminhamento_id
                                                       AND e.status IN ('CRIADO','ENVIADO_AO_PACIENTE')))
     OR (v.finalidade = 'CODIGO_PACIENTE' AND NOT encaminhamento_aberto(v.encaminhamento_id)) THEN
    UPDATE envio_notificacao SET status = 'FALHOU', atualizado_em = now() WHERE id = v.id;
    RETURN;
  END IF;
  IF v.finalidade = 'LINK_PACIENTE' THEN
    UPDATE link_paciente SET revogado_em = now()
     WHERE encaminhamento_id = v.encaminhamento_id AND usado_em IS NULL AND revogado_em IS NULL;
    tok := novo_token();
    INSERT INTO link_paciente(encaminhamento_id, paciente_id, token_hash, expira_em)
    VALUES (v.encaminhamento_id, v.destinatario_id, hash_token(tok), now() + interval '3 days') RETURNING id INTO lid;
    UPDATE envio_notificacao SET link_paciente_id = lid WHERE id = v.id;
  ELSIF v.finalidade = 'CODIGO_PACIENTE' THEN
    SELECT * INTO l FROM link_paciente WHERE id = v.link_paciente_id AND usado_em IS NULL AND revogado_em IS NULL
       AND expira_em > now() FOR UPDATE;
    IF l.id IS NULL THEN RAISE EXCEPTION 'link invalido'; END IF;
    cod := novo_codigo();
    UPDATE link_paciente SET codigo_hash = hash_codigo(l.id, cod), codigo_expira_em = now() + interval '10 minutes' WHERE id = l.id;
    tok := cod;
  ELSIF v.finalidade = 'CODIGO_ENCAMINHADOR' THEN
    SELECT * INTO d FROM desafio_encaminhador WHERE id = v.desafio_id AND usado_em IS NULL AND expira_em > now() FOR UPDATE;
    IF d.id IS NULL THEN RAISE EXCEPTION 'desafio invalido'; END IF;
    cod := novo_codigo();
    UPDATE desafio_encaminhador SET codigo_hash = hash_codigo(d.id, cod), codigo_expira_em = now() + interval '10 minutes' WHERE id = d.id;
    tok := cod;
  END IF;
  UPDATE envio_notificacao SET status = 'PREPARADO', tentativas = tentativas + 1, atualizado_em = now() WHERE id = v.id;
  RETURN QUERY SELECT v.canal,
    CASE v.destinatario_tipo WHEN 'PACIENTE' THEN (SELECT telefone FROM paciente WHERE id = v.destinatario_id)
                             ELSE (SELECT telefone FROM profissional WHERE id = v.destinatario_id) END,
    tok;
END $$;

SET ROLE saas_owner;
SET search_path = saas, public;

ALTER POLICY agendamento_equipe_cria ON agendamento
  WITH CHECK (clinica_id = app_clinica_id() AND eh_equipe(ARRAY['ADMIN','RECEPCAO','MEDICO']) AND encaminhamento_id IS NULL);
ALTER POLICY consentimento_recepcao_registra ON consentimento
  WITH CHECK (eh_equipe(ARRAY['ADMIN','RECEPCAO']) AND clinica_id = app_clinica_id()
              AND canal = 'RECEPCAO' AND finalidade <> 'COMPARTILHAR_CASO' AND revogado_em IS NULL
              AND EXISTS (SELECT 1 FROM paciente_clinica pc
                           WHERE pc.paciente_id = consentimento.paciente_id AND pc.clinica_id = app_clinica_id()));

ALTER TABLE encaminhamento DROP COLUMN telefone_contato;

RESET ROLE;
RESET search_path;

DO $$
BEGIN
  IF to_regclass('migracao.flyway_schema_history') IS NOT NULL THEN
    DELETE FROM migracao.flyway_schema_history WHERE version = '2';
  END IF;
END $$;
