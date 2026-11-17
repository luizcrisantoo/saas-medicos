-- =====================================================================
-- V3__gates_banco.sql : gates de banco do Red Team da Fase 2 (F4).
-- Fontes: docs/fase2/spec.md (F4, secao 5); docs/seguranca/stride-encaminhamento.md (I-21,
-- E-09, R-08); docs/agents/red-team-t-fase1-arquitetura-r1.md (O3, N11a, N11d) e -r2.md;
-- teste-r2-independente.sql (N3-cancelamento: envios pendentes apos cancelamento);
-- decisao registrada no ADR-0039.
--  I-21: rede_ligada nao responde sem sessao valida (devolve falso). As demais funcoes
--        SECURITY DEFINER do papel web ja exigem sessao ou sao a entrada publica por token.
--  O3:   paciente e encaminhador so veem profissional com canal verificado ou com
--        usuario; a equipe continua vendo o cadastro inteiro (nome e CRM).
--  F4.4: cancelar agendamento (direto ou em cascata por T9, T10, T11) derruba os envios
--        CONFIRMACAO_AGENDAMENTO e LEMBRETE pendentes (FALHOU), e jobs_envio_prepara rele
--        o agendamento: fora de AGENDADO ou CONFIRMADO nada sai.
--  E-09: jobs_envio_prepara marca preparado_em e, a partir de 20 preparos para o mesmo
--        destinatario em 1 hora, grava ALERTA_PREPARO_VOLUME no log, sem contato nem segredo.
--  R-08: o alerta de DDL e gatilho de evento (superusuario): fica em infra/db/bootstrap.sql.
-- Executada pelo Flyway como saas_migracao; termina com RESET ROLE.
-- Reversao: src/main/resources/db/reversao/V3__gates_banco.sql.
-- =====================================================================

SET ROLE saas_owner;
SET LOCAL search_path = saas, public;

-- E-09: momento do preparo (o segredo saiu do banco). Sem contato gravado (ADR-0034).
ALTER TABLE envio_notificacao ADD COLUMN preparado_em timestamptz;
CREATE INDEX envio_preparo_destinatario_idx ON envio_notificacao (destinatario_tipo, destinatario_id, preparado_em)
  WHERE preparado_em IS NOT NULL;

-- O3 (Red Team r1, N11d): cadastro sem canal verificado e sem usuario (inclusive o de
-- quem tomou um CRM alheio) fica fora da visao de paciente e encaminhador.
ALTER POLICY profissional_ver ON profissional
  USING (ator_tipo() = 'EQUIPE'
         OR (ator_tipo() IN ('PACIENTE','ENCAMINHADOR')
             AND (canal_verificado_em IS NOT NULL OR usuario_id IS NOT NULL)));
-- Especialidade do profissional: so de quem o ator ve (a subconsulta passa pela politica
-- profissional_ver acima, com o SELECT por coluna do papel web).
ALTER POLICY profissional_especialidade_ver ON profissional_especialidade
  USING (ator_tipo() IS NOT NULL
         AND EXISTS (SELECT 1 FROM profissional p WHERE p.id = profissional_especialidade.profissional_id));

SET ROLE saas_funcoes;
SET LOCAL search_path = saas, public;

-- I-21 (N11a): sem sessao valida, nao responde por clinica nenhuma (falso). O EXECUTE do
-- papel web fica: a lista de funcoes executaveis pela web e conferida pela regressao (N1).
CREATE OR REPLACE FUNCTION rede_ligada(p_clinica uuid) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER
  SET search_path = saas, pg_temp AS
$$ SELECT ator_tipo() IS NOT NULL
      AND EXISTS (SELECT 1 FROM flag_clinica f
                   WHERE f.clinica_id = p_clinica AND f.chave = 'REDE_ENCAMINHAMENTO' AND f.ligada) $$;

-- F4.4: agendamento cancelado derruba confirmacao e lembrete pendentes. SECURITY DEFINER
-- porque o papel web cancela (T11 direto ou UPDATE de status) e nao tem privilegio em
-- envio_notificacao. Vale para a cascata de encaminhamento_apos_transicao.
CREATE FUNCTION agendamento_cancela_envios() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
  SET search_path = saas, pg_temp AS
$$ BEGIN
  UPDATE envio_notificacao SET status = 'FALHOU', atualizado_em = now()
   WHERE agendamento_id = NEW.id AND status = 'PENDENTE'
     AND finalidade IN ('CONFIRMACAO_AGENDAMENTO','LEMBRETE');
  RETURN NULL;
END $$;
REVOKE EXECUTE ON FUNCTION agendamento_cancela_envios() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION agendamento_cancela_envios() TO saas_owner;

-- Igual a V2, mais:
--  F4.4: confirmacao e lembrete exigem agendamento ativo (AGENDADO ou CONFIRMADO), do
--        proprio paciente destinatario; senao o envio vira FALHOU e nada sai.
--  I-22 mantido: envio ao paciente ligado a caso (pelo envio ou pelo agendamento) vai so ao
--        telefone de contato do caso; nunca ao telefone do cadastro como reserva.
--  E-09: preparado_em e alerta de volume por destinatario.
CREATE OR REPLACE FUNCTION jobs_envio_prepara(p_envio uuid) RETURNS TABLE (canal text, contato text, segredo text)
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = saas, pg_temp AS
$$ DECLARE v envio_notificacao; tok text; cod text; lid uuid; l link_paciente; d desafio_encaminhador; ct text;
  a agendamento; enc uuid; n int;
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
  enc := v.encaminhamento_id;
  -- F4.4: confirmacao e lembrete so com agendamento ativo, do mesmo caso e, se o destinatario
  -- e paciente, do mesmo paciente.
  IF v.finalidade IN ('CONFIRMACAO_AGENDAMENTO','LEMBRETE') THEN
    SELECT * INTO a FROM agendamento WHERE id = v.agendamento_id;
    IF a.id IS NULL OR a.status NOT IN ('AGENDADO','CONFIRMADO')
       OR (v.destinatario_tipo = 'PACIENTE' AND a.paciente_id <> v.destinatario_id)
       OR (v.encaminhamento_id IS NOT NULL AND a.encaminhamento_id IS DISTINCT FROM v.encaminhamento_id)
       OR (a.encaminhamento_id IS NOT NULL AND NOT encaminhamento_aberto(a.encaminhamento_id)) THEN
      UPDATE envio_notificacao SET status = 'FALHOU', atualizado_em = now() WHERE id = v.id;
      RETURN;
    END IF;
    enc := coalesce(v.encaminhamento_id, a.encaminhamento_id);
  END IF;
  -- I-22: contato resolvido antes de gerar qualquer segredo. Caso pelo envio ou pelo agendamento.
  IF v.destinatario_tipo = 'PACIENTE' AND enc IS NOT NULL THEN
    SELECT e.telefone_contato INTO ct FROM encaminhamento e
     WHERE e.id = enc AND e.paciente_id = v.destinatario_id;
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
  UPDATE envio_notificacao SET status = 'PREPARADO', tentativas = tentativas + 1, preparado_em = clock_timestamp(),
         atualizado_em = now() WHERE id = v.id;
  -- E-09: volume por destinatario (tipo e id) na ultima hora, contando este preparo. A linha
  -- leva so ids e a contagem: nunca contato, token ou codigo.
  SELECT count(*) INTO n FROM envio_notificacao x
   WHERE x.destinatario_tipo = v.destinatario_tipo AND x.destinatario_id = v.destinatario_id
     AND x.preparado_em > clock_timestamp() - interval '1 hour';
  IF n >= 20 THEN
    RAISE LOG 'ALERTA_PREPARO_VOLUME: % preparos em 1 hora para destinatario_tipo=% destinatario_id=% (envio=% finalidade=%)',
      n, v.destinatario_tipo, v.destinatario_id, v.id, v.finalidade;
  END IF;
  RETURN QUERY SELECT v.canal, ct, tok;
END $$;

SET ROLE saas_owner;
SET LOCAL search_path = saas, public;

CREATE TRIGGER agendamento_cancela_envios
  AFTER UPDATE OF status ON agendamento FOR EACH ROW
  WHEN (NEW.status = 'CANCELADO' AND OLD.status IS DISTINCT FROM 'CANCELADO')
  EXECUTE FUNCTION agendamento_cancela_envios();

RESET ROLE;
