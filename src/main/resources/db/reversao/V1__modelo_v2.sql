-- =====================================================================
-- Reversao de V1__modelo_v2.sql (executada por saas_migracao, fora do Flyway).
-- Devolve o schema saas ao estado anterior a V1: o schema vazio deixado por
-- infra/db/bootstrap.sql (dono, USAGE e CREATE continuam do bootstrap).
-- Ordem: primeiro as funcoes (dono saas_funcoes; CASCADE leva os gatilhos e as
-- politicas que as usam), depois as tabelas (dono saas_owner).
-- Por fim apaga a linha da V1 no historico do Flyway, para que o historico
-- continue coerente com o schema.
-- =====================================================================

SET ROLE saas_funcoes;
DO $$
DECLARE f regprocedure;
BEGIN
  FOR f IN SELECT p.oid::regprocedure
             FROM pg_proc p
            WHERE p.pronamespace = 'saas'::regnamespace
              AND p.proowner = 'saas_funcoes'::regrole
  LOOP
    EXECUTE format('DROP FUNCTION %s CASCADE', f);
  END LOOP;
END $$;

SET ROLE saas_owner;
DROP TABLE IF EXISTS
  saas.evento_auditoria,
  saas.envio_notificacao,
  saas.anexo_encaminhamento,
  saas.contrarreferencia,
  saas.agendamento,
  saas.vaga_encaminhamento,
  saas.sessao,
  saas.desafio_encaminhador,
  saas.link_paciente,
  saas.consentimento,
  saas.historico_status_encaminhamento,
  saas.paciente_clinica,
  saas.encaminhamento,
  saas.paciente,
  saas.horario_atendimento,
  saas.profissional_clinica,
  saas.profissional_especialidade,
  saas.profissional,
  saas.flag_clinica,
  saas.usuario_clinica,
  saas.clinica_especialidade,
  saas.clinica,
  saas.especialidade,
  saas.usuario
  CASCADE;

RESET ROLE;

DO $$
BEGIN
  IF to_regclass('migracao.flyway_schema_history') IS NOT NULL THEN
    DELETE FROM migracao.flyway_schema_history WHERE version = '1';
  END IF;
END $$;
