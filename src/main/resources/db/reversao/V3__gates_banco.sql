-- =====================================================================
-- Reversao de V3__gates_banco.sql (executada por saas_migracao, fora do Flyway).
-- Devolve o schema saas exatamente ao estado da V2: rede_ligada com o texto da V1,
-- politicas de profissional com a expressao da V1, jobs_envio_prepara com o texto da V2 (copiado sem mudanca), sem o gatilho
-- agendamento_cancela_envios e sem a coluna envio_notificacao.preparado_em.
-- O alerta de DDL (R-08) fica no bootstrap: e do cluster, nao da versao do schema.
-- Por fim apaga a linha da V3 no historico do Flyway.
-- ATENCAO: reverter reabre os achados I-21, O3, E-09 (alerta de volume) e os envios
-- pendentes apos cancelamento.
-- =====================================================================

SET ROLE saas_owner;
SET search_path = saas, public;

DROP TRIGGER agendamento_cancela_envios ON agendamento;

ALTER POLICY profissional_ver ON profissional USING (ator_tipo() IS NOT NULL);
ALTER POLICY profissional_especialidade_ver ON profissional_especialidade USING (ator_tipo() IS NOT NULL);

SET ROLE saas_funcoes;
SET search_path = saas, public;

DROP FUNCTION agendamento_cancela_envios();

CREATE OR REPLACE FUNCTION rede_ligada(p_clinica uuid) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER
  SET search_path = saas, pg_temp AS
$$ SELECT EXISTS (SELECT 1 FROM flag_clinica f
                   WHERE f.clinica_id = p_clinica AND f.chave = 'REDE_ENCAMINHAMENTO' AND f.ligada) $$;

CREATE OR REPLACE FUNCTION jobs_envio_prepara(p_envio uuid) RETURNS TABLE (canal text, contato text, segredo text)
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = saas, pg_temp AS
$$ DECLARE v envio_notificacao; tok text; cod text; lid uuid; l link_paciente; d desafio_encaminhador; ct text;
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
  -- I-22: contato resolvido antes de gerar qualquer segredo.
  IF v.destinatario_tipo = 'PACIENTE' AND v.encaminhamento_id IS NOT NULL THEN
    SELECT e.telefone_contato INTO ct FROM encaminhamento e
     WHERE e.id = v.encaminhamento_id AND e.paciente_id = v.destinatario_id;
  ELSIF v.destinatario_tipo = 'PACIENTE' THEN
    SELECT telefone INTO ct FROM paciente WHERE id = v.destinatario_id;      -- envio sem caso: o proprio cadastro
  ELSE
    SELECT telefone INTO ct FROM profissional WHERE id = v.destinatario_id;
  END IF;
  IF ct IS NULL OR btrim(ct) = '' THEN
    UPDATE envio_notificacao SET status = 'FALHOU', atualizado_em = now() WHERE id = v.id;
    PERFORM audita('ENVIO_SEM_CONTATO', 'envio_notificacao', v.id);
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
  RETURN QUERY SELECT v.canal, ct, tok;
END $$;

SET ROLE saas_owner;
SET search_path = saas, public;

DROP INDEX envio_preparo_destinatario_idx;
ALTER TABLE envio_notificacao DROP COLUMN preparado_em;

RESET ROLE;
RESET search_path;

DO $$
BEGIN
  IF to_regclass('migracao.flyway_schema_history') IS NOT NULL THEN
    DELETE FROM migracao.flyway_schema_history WHERE version = '3';
  END IF;
END $$;
