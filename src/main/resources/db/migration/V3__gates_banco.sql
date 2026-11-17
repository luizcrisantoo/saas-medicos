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
--  F4.4: agendamento que sai de AGENDADO/CONFIRMADO (cancelado direto ou em cascata por T9,
--        T10, T11, realizado ou falta) derruba confirmacao e lembrete PENDENTES e PREPARADOS
--        ainda nao enviados (FALHOU); reagendamento (horario ou profissional) derruba os
--        PREPARADOS (dado velho). Encaminhamento em estado final derruba os envios do caso
--        ainda nao enviados. jobs_envio_prepara e jobs_envio_resultado releem o estado do
--        agendamento e do encaminhamento: caso cancelado nao prepara nem confirma envio.
--  E-09: jobs_envio_prepara marca preparado_em e, a partir de 20 preparos em 1 hora para o
--        mesmo destinatario OU para o mesmo telefone normalizado (pacientes e casos somam),
--        grava ALERTA_PREPARO_VOLUME no log, sem contato nem segredo. Limite e janela num so
--        lugar (constantes c_volume_* em jobs_envio_prepara).
--  R-08: o alerta de DDL e gatilho de evento (superusuario): fica em infra/db/bootstrap.sql.
-- Executada pelo Flyway como saas_migracao; termina com RESET ROLE.
-- Reversao: src/main/resources/db/reversao/V3__gates_banco.sql.
-- =====================================================================

SET ROLE saas_owner;
SET LOCAL search_path = saas, public;

-- E-09: momento do preparo (o segredo saiu do banco). Sem contato gravado (ADR-0034).
ALTER TABLE envio_notificacao ADD COLUMN preparado_em timestamptz;
CREATE INDEX envio_preparado_em_idx ON envio_notificacao (preparado_em) WHERE preparado_em IS NOT NULL;

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

-- E-09: telefone so com digitos, sem zeros a esquerda; numero nacional (10 ou 11 digitos,
-- DDD + numero) ganha o 55. "+55 (81) 9 9999-0000", "081999990000" e "81999990000" somam
-- no mesmo contato. So para contar volume: nunca gravado nem logado.
CREATE FUNCTION telefone_normalizado(p text) RETURNS text LANGUAGE sql IMMUTABLE
  SET search_path = saas, pg_temp AS
$$ SELECT nullif(CASE WHEN d ~ '^[0-9]{10,11}$' THEN '55' || d ELSE d END, '')
     FROM (SELECT ltrim(regexp_replace(coalesce(p, ''), '[^0-9]', '', 'g'), '0') AS d) s $$;
REVOKE EXECUTE ON FUNCTION telefone_normalizado(text) FROM PUBLIC;

-- I-22: contato de um envio, resolvido sempre do mesmo jeito (preparo e contagem de volume).
-- Paciente ligado a caso (pelo envio ou, em confirmacao e lembrete, pelo agendamento): so o
-- telefone de contato do caso, nunca o do cadastro. Paciente sem caso: o proprio cadastro.
-- Profissional: o telefone do cadastro. Sem EXECUTE para papel de login.
CREATE FUNCTION envio_contato(p_envio uuid) RETURNS text LANGUAGE plpgsql STABLE SECURITY DEFINER
  SET search_path = saas, pg_temp AS
$$ DECLARE v envio_notificacao; enc uuid; ct text;
BEGIN
  SELECT * INTO v FROM envio_notificacao WHERE id = p_envio;
  IF v.id IS NULL THEN RETURN NULL; END IF;
  enc := v.encaminhamento_id;
  IF enc IS NULL AND v.finalidade IN ('CONFIRMACAO_AGENDAMENTO','LEMBRETE') THEN
    SELECT a.encaminhamento_id INTO enc FROM agendamento a WHERE a.id = v.agendamento_id;
  END IF;
  IF v.destinatario_tipo = 'PACIENTE' AND enc IS NOT NULL THEN
    SELECT e.telefone_contato INTO ct FROM encaminhamento e WHERE e.id = enc AND e.paciente_id = v.destinatario_id;
  ELSIF v.destinatario_tipo = 'PACIENTE' THEN
    SELECT telefone INTO ct FROM paciente WHERE id = v.destinatario_id;
  ELSE
    SELECT telefone INTO ct FROM profissional WHERE id = v.destinatario_id;
  END IF;
  RETURN ct;
END $$;
REVOKE EXECUTE ON FUNCTION envio_contato(uuid) FROM PUBLIC;

-- F4.4 e r2-1: o caso do envio ainda admite que ele saia? Relido na fonte, no preparo e no
-- resultado. Link so para CRIADO ou ENVIADO_AO_PACIENTE; codigo so com encaminhamento aberto;
-- confirmacao e lembrete so com agendamento AGENDADO ou CONFIRMADO, do mesmo caso, do mesmo
-- paciente destinatario e com o encaminhamento (se houver) aberto. Sem EXECUTE para login.
CREATE FUNCTION envio_caso_ativo(p_envio uuid) RETURNS boolean LANGUAGE plpgsql STABLE SECURITY DEFINER
  SET search_path = saas, pg_temp AS
$$ DECLARE v envio_notificacao; a agendamento;
BEGIN
  SELECT * INTO v FROM envio_notificacao WHERE id = p_envio;
  IF v.id IS NULL THEN RETURN false; END IF;
  IF v.finalidade = 'LINK_PACIENTE' THEN
    RETURN EXISTS (SELECT 1 FROM encaminhamento e WHERE e.id = v.encaminhamento_id
                      AND e.status IN ('CRIADO','ENVIADO_AO_PACIENTE'));
  ELSIF v.finalidade = 'CODIGO_PACIENTE' THEN
    RETURN encaminhamento_aberto(v.encaminhamento_id);
  ELSIF v.finalidade IN ('CONFIRMACAO_AGENDAMENTO','LEMBRETE') THEN
    SELECT * INTO a FROM agendamento WHERE id = v.agendamento_id;
    RETURN a.id IS NOT NULL AND a.status IN ('AGENDADO','CONFIRMADO')
       AND NOT (v.destinatario_tipo = 'PACIENTE' AND a.paciente_id <> v.destinatario_id)
       AND NOT (v.encaminhamento_id IS NOT NULL AND a.encaminhamento_id IS DISTINCT FROM v.encaminhamento_id)
       AND (a.encaminhamento_id IS NULL OR encaminhamento_aberto(a.encaminhamento_id));
  END IF;
  RETURN true;
END $$;
REVOKE EXECUTE ON FUNCTION envio_caso_ativo(uuid) FROM PUBLIC;

-- F4.4: agendamento que deixa de estar ativo (CANCELADO direto ou em cascata por T9, T10 e
-- T11; REALIZADO; FALTOU) derruba confirmacao e lembrete PENDENTES e PREPARADOS ainda nao
-- enviados (PREPARADO e o estado entre o preparo e o resultado do provedor). Reagendamento
-- (horario ou profissional) derruba os PREPARADOS, que sairiam com o horario velho; os
-- PENDENTES ficam, porque o preparo rele o agendamento. SECURITY DEFINER porque o papel web
-- cancela e reagenda e nao tem privilegio em envio_notificacao.
CREATE FUNCTION agendamento_cancela_envios() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
  SET search_path = saas, pg_temp AS
$$ BEGIN
  IF NEW.status NOT IN ('AGENDADO','CONFIRMADO') THEN
    UPDATE envio_notificacao SET status = 'FALHOU', atualizado_em = now()
     WHERE agendamento_id = NEW.id AND status IN ('PENDENTE','PREPARADO')
       AND finalidade IN ('CONFIRMACAO_AGENDAMENTO','LEMBRETE');
  ELSE
    UPDATE envio_notificacao SET status = 'FALHOU', atualizado_em = now()
     WHERE agendamento_id = NEW.id AND status = 'PREPARADO'
       AND finalidade IN ('CONFIRMACAO_AGENDAMENTO','LEMBRETE');
  END IF;
  RETURN NULL;
END $$;
REVOKE EXECUTE ON FUNCTION agendamento_cancela_envios() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION agendamento_cancela_envios() TO saas_owner;

-- F4.4 e r2-1: encaminhamento em estado final derruba tambem os envios do caso ja PREPARADOS
-- e ainda nao enviados (a V1 so derrubava LINK e CODIGO PENDENTES).
CREATE FUNCTION encaminhamento_derruba_envios() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
  SET search_path = saas, pg_temp AS
$$ BEGIN
  UPDATE envio_notificacao SET status = 'FALHOU', atualizado_em = now()
   WHERE encaminhamento_id = NEW.id AND status IN ('PENDENTE','PREPARADO')
     AND finalidade IN ('LINK_PACIENTE','CODIGO_PACIENTE','CONFIRMACAO_AGENDAMENTO','LEMBRETE');
  RETURN NULL;
END $$;
REVOKE EXECUTE ON FUNCTION encaminhamento_derruba_envios() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION encaminhamento_derruba_envios() TO saas_owner;

-- Igual a V2, mais:
--  F4.4: o caso tem que admitir o envio (envio_caso_ativo); senao FALHOU e nada sai.
--  I-22 mantido: contato por envio_contato (caso pelo envio ou pelo agendamento: so o
--        telefone de contato do caso).
--  E-09: preparado_em e alerta de volume por destinatario e por telefone normalizado.
CREATE OR REPLACE FUNCTION jobs_envio_prepara(p_envio uuid) RETURNS TABLE (canal text, contato text, segredo text)
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = saas, pg_temp AS
$$ DECLARE
  -- E-09 (docs/fase2/spec.md, F4.5): 20 ou mais preparos em 1 hora. Unico lugar do limite.
  c_volume_limite        CONSTANT int := 20;
  c_volume_janela_horas  CONSTANT int := 1;
  v envio_notificacao; tok text; cod text; lid uuid; l link_paciente; d desafio_encaminhador; ct text;
  ctn text; n int; nc int; nd int;
BEGIN
  SELECT * INTO v FROM envio_notificacao WHERE id = p_envio AND status = 'PENDENTE' AND tentativas < 5 FOR UPDATE;
  IF v.id IS NULL THEN RAISE EXCEPTION 'envio inexistente ou ja preparado'; END IF;
  -- r2-1 e F4.4: caso relido na fonte. Fora de estado o envio vira FALHOU e nada sai:
  -- nem segredo, nem contato.
  IF NOT envio_caso_ativo(v.id) THEN
    UPDATE envio_notificacao SET status = 'FALHOU', atualizado_em = now() WHERE id = v.id;
    RETURN;
  END IF;
  -- I-22: contato resolvido antes de gerar qualquer segredo.
  ct := envio_contato(v.id);
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
  -- E-09: volume na janela, contando este preparo, por destinatario (tipo e id) e pelo telefone
  -- normalizado (varios pacientes, casos ou profissionais com o mesmo numero somam; o contato de
  -- cada envio e resolvido de novo por envio_contato, nada de contato gravado, ADR-0034).
  -- A linha leva so ids e contagens: nunca contato, token ou codigo.
  ctn := telefone_normalizado(ct);
  SELECT count(*) FILTER (WHERE x.destinatario_tipo = v.destinatario_tipo AND x.destinatario_id = v.destinatario_id),
         count(*) FILTER (WHERE ctn IS NOT NULL AND telefone_normalizado(envio_contato(x.id)) = ctn),
         count(DISTINCT (x.destinatario_tipo, x.destinatario_id))
               FILTER (WHERE ctn IS NOT NULL AND telefone_normalizado(envio_contato(x.id)) = ctn)
    INTO n, nc, nd
    FROM envio_notificacao x
   WHERE x.preparado_em > clock_timestamp() - make_interval(hours => c_volume_janela_horas);
  IF n >= c_volume_limite THEN
    RAISE LOG 'ALERTA_PREPARO_VOLUME: % preparos em % hora para destinatario_tipo=% destinatario_id=% (envio=% finalidade=%)',
      n, c_volume_janela_horas, v.destinatario_tipo, v.destinatario_id, v.id, v.finalidade;
  END IF;
  IF nc >= c_volume_limite AND nc > n THEN
    RAISE LOG 'ALERTA_PREPARO_VOLUME: % preparos em % hora para o mesmo contato, % destinatarios (envio=% finalidade=% destinatario_tipo=% destinatario_id=%)',
      nc, c_volume_janela_horas, nd, v.id, v.finalidade, v.destinatario_tipo, v.destinatario_id;
  END IF;
  RETURN QUERY SELECT v.canal, ct, tok;
END $$;

-- Igual a V1 (T2 so com LINK aceito e encaminhamento CRIADO), mais F4.4: o resultado rele o
-- caso. Envio derrubado (FALHOU, por cancelamento ou estado final) nao e confirmado: devolve
-- falso e nada muda. Envio PREPARADO cujo caso nao admite mais o envio vira FALHOU e devolve
-- falso: ACEITO e ENTREGUE nunca sao gravados para caso cancelado.
CREATE OR REPLACE FUNCTION jobs_envio_resultado(p_envio uuid, p_status text, p_id_provedor text) RETURNS boolean LANGUAGE plpgsql VOLATILE SECURITY DEFINER
  SET search_path = saas, pg_temp AS
$$ DECLARE v envio_notificacao; n int;
BEGIN
  IF p_status NOT IN ('ACEITO','ENTREGUE','FALHOU') THEN RAISE EXCEPTION 'status invalido'; END IF;
  SELECT * INTO v FROM envio_notificacao WHERE id = p_envio FOR UPDATE;
  IF v.id IS NOT NULL AND v.status = 'FALHOU' THEN RETURN false; END IF;
  IF v.id IS NULL OR v.status NOT IN ('PREPARADO','ACEITO') THEN RAISE EXCEPTION 'envio inexistente'; END IF;
  IF v.status = 'PREPARADO' AND p_status <> 'FALHOU' AND NOT envio_caso_ativo(v.id) THEN
    UPDATE envio_notificacao SET status = 'FALHOU', id_provedor = p_id_provedor, atualizado_em = now() WHERE id = v.id;
    RETURN false;
  END IF;
  UPDATE envio_notificacao SET status = p_status, id_provedor = p_id_provedor, atualizado_em = now()
   WHERE id = v.id RETURNING * INTO v;
  IF v.finalidade = 'LINK_PACIENTE' AND p_status = 'ACEITO' THEN
    PERFORM set_config('saas.transicao', 'T2', true);
    UPDATE encaminhamento SET status = 'ENVIADO_AO_PACIENTE' WHERE id = v.encaminhamento_id AND status = 'CRIADO';
    GET DIAGNOSTICS n = ROW_COUNT;
    PERFORM set_config('saas.transicao', '', true);
    RETURN n = 1;
  END IF;
  RETURN false;
END $$;

SET ROLE saas_owner;
SET LOCAL search_path = saas, public;

CREATE TRIGGER agendamento_cancela_envios
  AFTER UPDATE OF status, inicio, fim, profissional_clinica_id ON agendamento FOR EACH ROW
  WHEN ((NEW.status NOT IN ('AGENDADO','CONFIRMADO') AND OLD.status IN ('AGENDADO','CONFIRMADO'))
        OR (NEW.inicio, NEW.fim, NEW.profissional_clinica_id) IS DISTINCT FROM (OLD.inicio, OLD.fim, OLD.profissional_clinica_id))
  EXECUTE FUNCTION agendamento_cancela_envios();

CREATE TRIGGER encaminhamento_derruba_envios
  AFTER UPDATE OF status ON encaminhamento FOR EACH ROW
  WHEN (NEW.status IN ('CONTRARREFERIDO','EXPIRADO','CANCELADO') AND OLD.status IS DISTINCT FROM NEW.status)
  EXECUTE FUNCTION encaminhamento_derruba_envios();

RESET ROLE;
