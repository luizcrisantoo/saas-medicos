-- =====================================================================
-- V1__modelo_v2.sql : modelo de dados v2 (revisao r2) como primeira migracao.
-- Fonte: docs/arquitetura/modelo-v2.sql (secoes 1 a 16), docs/arquitetura/modelo-dados-v2.md.
-- Executada pelo Flyway como saas_migracao (ADR-0027): cada bloco assume o papel
-- dono com SET ROLE e a migracao termina com RESET ROLE. Papeis, extensao, schemas,
-- parametros por papel e gatilhos de evento ficam em infra/db/bootstrap.sql
-- (exigem superusuario); o restante do modelo esta aqui sem mudanca de conteudo.
-- Reversao: src/main/resources/db/reversao/V1__modelo_v2.sql.
-- =====================================================================

SET ROLE saas_owner;
SET LOCAL search_path = saas, public;


-- ---------------------------------------------------------------------
-- 1. Identidade (modulo identidade)
-- ---------------------------------------------------------------------
-- Usuario: conta de equipe no provedor OIDC (admin, recepcao, medico). Pessoa global.
CREATE TABLE usuario (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  sub_oidc    text NOT NULL UNIQUE,
  nome        text NOT NULL,
  email       text NOT NULL,
  ativo       boolean NOT NULL DEFAULT true,
  criado_em   timestamptz NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------
-- 2. Clinicas (modulo clinicas)
-- ---------------------------------------------------------------------
CREATE TABLE especialidade (
  id    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  nome  text NOT NULL UNIQUE
);

CREATE TABLE clinica (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  nome               text NOT NULL,
  cnpj               text,
  modo_recebimento   text NOT NULL DEFAULT 'PEDIDO'
                     CHECK (modo_recebimento IN ('PEDIDO','VAGAS','AGENDA_NATIVA')),
  -- ADR-0031: VAGAS e AGENDA_NATIVA so na Fase 6. Ate la o banco recusa.
  CONSTRAINT modo_ate_fase6_so_pedido CHECK (modo_recebimento = 'PEDIDO'),
  criado_em          timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE clinica_especialidade (
  clinica_id        uuid NOT NULL REFERENCES clinica(id),
  especialidade_id  uuid NOT NULL REFERENCES especialidade(id),
  PRIMARY KEY (clinica_id, especialidade_id)
);

-- UsuarioClinica: papel por clinica (ADR-0016).
CREATE TABLE usuario_clinica (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  usuario_id  uuid NOT NULL REFERENCES usuario(id),
  clinica_id  uuid NOT NULL REFERENCES clinica(id),
  papel       text NOT NULL CHECK (papel IN ('ADMIN','RECEPCAO','MEDICO')),
  ativo       boolean NOT NULL DEFAULT true,
  criado_em   timestamptz NOT NULL DEFAULT now(),
  UNIQUE (usuario_id, clinica_id, papel)
);

-- Feature flag por clinica (ADR-0019). A rede usa a chave REDE_ENCAMINHAMENTO e o
-- banco a confere (funcao rede_ligada), nao so a aplicacao (Red Team, item 15).
CREATE TABLE flag_clinica (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  clinica_id   uuid NOT NULL REFERENCES clinica(id),
  chave        text NOT NULL,
  ligada       boolean NOT NULL DEFAULT false,
  alterado_em  timestamptz NOT NULL DEFAULT now(),
  alterado_por uuid REFERENCES usuario(id),
  UNIQUE (clinica_id, chave)
);

-- Profissional: medico GLOBAL com CRM (briefing, Glossario).
CREATE TABLE profissional (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  crm                 text NOT NULL,
  crm_uf              char(2) NOT NULL,
  nome                text NOT NULL CHECK (char_length(nome) <= 120 AND nome !~* '(https?://|www\.)'),
  telefone            text,           -- nunca legivel pelo papel web (GRANT por coluna); mascarar em log
  email               text,           -- idem
  usuario_id          uuid UNIQUE REFERENCES usuario(id),  -- so operacao liga; nulo para quem encaminha sem conta
  canal_verificado_em timestamptz,    -- posse do telefone confirmada por codigo (ADR-0025)
  criado_em           timestamptz NOT NULL DEFAULT now(),
  UNIQUE (crm, crm_uf)
);

CREATE TABLE profissional_especialidade (
  profissional_id   uuid NOT NULL REFERENCES profissional(id),
  especialidade_id  uuid NOT NULL REFERENCES especialidade(id),
  PRIMARY KEY (profissional_id, especialidade_id)
);

CREATE TABLE profissional_clinica (
  id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  profissional_id       uuid NOT NULL REFERENCES profissional(id),
  clinica_id            uuid NOT NULL REFERENCES clinica(id),
  duracao_consulta_min  smallint NOT NULL DEFAULT 30 CHECK (duracao_consulta_min BETWEEN 5 AND 240),
  recebe_encaminhamento boolean NOT NULL DEFAULT false,
  ativo                 boolean NOT NULL DEFAULT true,
  criado_em             timestamptz NOT NULL DEFAULT now(),
  UNIQUE (profissional_id, clinica_id),
  UNIQUE (clinica_id, id)
);

-- ---------------------------------------------------------------------
-- 3. Agenda: horarios (modulo agenda)
-- ---------------------------------------------------------------------
CREATE TABLE horario_atendimento (
  id                       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  clinica_id               uuid NOT NULL,
  profissional_clinica_id  uuid NOT NULL,
  dia_semana               smallint NOT NULL CHECK (dia_semana BETWEEN 0 AND 6),
  hora_inicio              time NOT NULL,
  hora_fim                 time NOT NULL,
  CHECK (hora_fim > hora_inicio),
  FOREIGN KEY (clinica_id, profissional_clinica_id) REFERENCES profissional_clinica(clinica_id, id)
);

-- ---------------------------------------------------------------------
-- 4. Pacientes (modulo pacientes)
-- ---------------------------------------------------------------------
CREATE TABLE paciente (
  id                        uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  nome                      text NOT NULL,
  telefone                  text NOT NULL,   -- imutavel pelo papel web (ADR-0029)
  data_nascimento           date,
  cpf_cifrado               bytea,           -- CIFRADO NA APLICACAO
  cpf_hash                  bytea,           -- HMAC com chave do KMS; sem UNIQUE (ADR-0017); nao legivel pela web
  cadastrado_por_clinica_id uuid REFERENCES clinica(id),  -- nulo se nasceu de encaminhamento
  criado_em                 timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX paciente_cpf_hash_idx ON paciente (cpf_hash);
CREATE INDEX paciente_telefone_idx ON paciente (telefone);

-- ---------------------------------------------------------------------
-- 5. Encaminhamentos (modulo encaminhamentos)
-- ---------------------------------------------------------------------
CREATE TABLE encaminhamento (
  id                        uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  profissional_origem_id    uuid NOT NULL REFERENCES profissional(id),
  paciente_id               uuid NOT NULL REFERENCES paciente(id),
  especialidade_destino_id  uuid NOT NULL REFERENCES especialidade(id),
  clinica_destino_id        uuid REFERENCES clinica(id),
  profissional_destino_id   uuid REFERENCES profissional(id),
  motivo_cifrado            bytea NOT NULL,
  urgencia                  text NOT NULL CHECK (urgencia IN ('ROTINA','PRIORITARIA','URGENTE')),
  status                    text NOT NULL DEFAULT 'CRIADO'
                            CHECK (status IN ('CRIADO','ENVIADO_AO_PACIENTE','SOLICITADO','AGENDADO',
                                              'ATENDIDO','CONTRARREFERIDO','EXPIRADO','CANCELADO')),
  expira_em                 timestamptz NOT NULL,
  criado_em                 timestamptz NOT NULL DEFAULT now(),
  atualizado_em             timestamptz NOT NULL DEFAULT now(),
  CHECK (profissional_destino_id IS NULL OR clinica_destino_id IS NOT NULL),
  -- Alvos de FK composta (Red Team, item 5): quem referencia o encaminhamento
  -- referencia tambem o paciente e/ou a clinica destino dele.
  UNIQUE (paciente_id, id),
  UNIQUE (clinica_destino_id, id),
  UNIQUE (clinica_destino_id, paciente_id, id)
);
CREATE INDEX encaminhamento_origem_idx  ON encaminhamento (profissional_origem_id);
CREATE INDEX encaminhamento_destino_idx ON encaminhamento (clinica_destino_id);
CREATE INDEX encaminhamento_expira_idx  ON encaminhamento (expira_em) WHERE status IN ('CRIADO','ENVIADO_AO_PACIENTE','SOLICITADO');

-- PacienteClinica: vinculo do paciente com a clinica. Nasce SO por funcao
-- (cadastro pela propria clinica ou confirmacao de horario de encaminhamento),
-- nunca por UUID vindo do cliente (Red Team, item 6).
CREATE TABLE paciente_clinica (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  paciente_id        uuid NOT NULL REFERENCES paciente(id),
  clinica_id         uuid NOT NULL REFERENCES clinica(id),
  encaminhamento_id  uuid,             -- preenchido quando o vinculo nasceu de um encaminhamento
  criado_em          timestamptz NOT NULL DEFAULT now(),
  UNIQUE (clinica_id, paciente_id),
  FOREIGN KEY (clinica_id, paciente_id, encaminhamento_id)
    REFERENCES encaminhamento(clinica_destino_id, paciente_id, id)
);

-- Historico: uma linha por transicao. So inclusao; gravado SO pelo gatilho
-- (sem INSERT para a aplicacao). Separa ator tecnico de autor de negocio (Red Team, item 12).
CREATE TABLE historico_status_encaminhamento (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  encaminhamento_id  uuid NOT NULL REFERENCES encaminhamento(id),
  status_anterior    text,
  status_novo        text NOT NULL,
  transicao          text NOT NULL CHECK (transicao IN ('T1','T2','T3','T4','T5','T6','T7','T8','T9','T10','T11')),
  ator_tecnico       text NOT NULL,   -- papel de banco de login (session_user): saas_app, saas_jobs ou operacao
  ator_tipo          text NOT NULL CHECK (ator_tipo IN ('EQUIPE','PACIENTE','ENCAMINHADOR','SISTEMA','OPERACAO')),
  ator_papel         text,            -- ADMIN, RECEPCAO, MEDICO, PACIENTE, ENCAMINHADOR (verificado pela sessao)
  ator_id            uuid,            -- usuario, paciente ou profissional da sessao verificada
  autor_negocio_id   uuid,            -- T5 e T7: usuario que marcou na agenda, lido do agendamento
  alterado_em        timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX historico_enc_idx ON historico_status_encaminhamento (encaminhamento_id);

-- Consentimento LGPD. FKs compostas: o encaminhamento tem que ser DO paciente e a
-- clinica tem que ser a DESTINO do encaminhamento (Red Team, item 11).
CREATE TABLE consentimento (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  paciente_id        uuid NOT NULL REFERENCES paciente(id),
  finalidade         text NOT NULL CHECK (finalidade IN ('AGENDAMENTO','COMPARTILHAR_CASO','COMUNICACAO_WHATSAPP')),
  encaminhamento_id  uuid,
  clinica_id         uuid REFERENCES clinica(id),
  texto_aceito       text NOT NULL,
  versao_texto       text NOT NULL,
  canal              text NOT NULL CHECK (canal IN ('WHATSAPP','SITE','RECEPCAO')),
  aceito_em          timestamptz NOT NULL DEFAULT now(),
  revogado_em        timestamptz,
  CHECK (finalidade <> 'COMPARTILHAR_CASO' OR (encaminhamento_id IS NOT NULL AND clinica_id IS NOT NULL)),
  CHECK (revogado_em IS NULL OR revogado_em >= aceito_em),
  FOREIGN KEY (paciente_id, encaminhamento_id) REFERENCES encaminhamento(paciente_id, id),
  FOREIGN KEY (clinica_id, encaminhamento_id)  REFERENCES encaminhamento(clinica_destino_id, id)
);
CREATE INDEX consentimento_enc_idx ON consentimento (encaminhamento_id);

-- LinkPaciente: guarda so hashes. Sem GRANT para o papel web: tudo passa por funcao
-- (link_consulta, paciente_pede_codigo, paciente_confirma_codigo). ADR-0030.
CREATE TABLE link_paciente (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  encaminhamento_id  uuid NOT NULL,
  paciente_id        uuid NOT NULL,
  token_hash         bytea NOT NULL UNIQUE,   -- sha256 do token; o token nunca e gravado
  expira_em          timestamptz NOT NULL,
  usado_em           timestamptz,             -- codigo confirmado (sessao aberta)
  revogado_em        timestamptz,             -- reemissao revoga o anterior
  codigo_hash        bytea,                   -- sha256(link_id || ':' || codigo)
  codigo_expira_em   timestamptz,
  tentativas_codigo  smallint NOT NULL DEFAULT 0 CHECK (tentativas_codigo BETWEEN 0 AND 10),
  criado_em          timestamptz NOT NULL DEFAULT now(),
  CHECK (expira_em <= criado_em + interval '7 days'),
  FOREIGN KEY (paciente_id, encaminhamento_id) REFERENCES encaminhamento(paciente_id, id)
);
-- Um link ativo por encaminhamento (Red Team, item 13; T-16).
CREATE UNIQUE INDEX link_um_ativo_por_encaminhamento ON link_paciente (encaminhamento_id)
  WHERE usado_em IS NULL AND revogado_em IS NULL;
CREATE INDEX link_paciente_pac_idx ON link_paciente (paciente_id, criado_em);

-- Desafio do encaminhador: verificacao de posse do canal do proprio medico (ADR-0025).
CREATE TABLE desafio_encaminhador (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  profissional_id   uuid NOT NULL REFERENCES profissional(id),
  desafio_hash      bytea NOT NULL UNIQUE,   -- sha256 do token entregue ao navegador
  codigo_hash       bytea,                   -- gerado pelo papel saas_jobs no envio
  codigo_expira_em  timestamptz,
  tentativas        smallint NOT NULL DEFAULT 0 CHECK (tentativas BETWEEN 0 AND 5),
  expira_em         timestamptz NOT NULL,
  usado_em          timestamptz,
  criado_em         timestamptz NOT NULL DEFAULT now(),
  CHECK (expira_em <= criado_em + interval '30 minutes')
);

-- Sessao: identidade verificavel no banco para TODO ator (ADR-0023; Red Team, item 1).
-- Sem GRANT para nenhum papel de login. Lida so por funcoes SECURITY DEFINER.
CREATE TABLE sessao (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  token_hash        bytea NOT NULL UNIQUE,   -- sha256 do token de sessao (cookie HttpOnly)
  tipo              text NOT NULL CHECK (tipo IN ('EQUIPE','PACIENTE','ENCAMINHADOR')),
  usuario_id        uuid REFERENCES usuario(id),
  paciente_id       uuid REFERENCES paciente(id),
  profissional_id   uuid REFERENCES profissional(id),
  link_paciente_id  uuid REFERENCES link_paciente(id),          -- origem da sessao do paciente
  desafio_id        uuid REFERENCES desafio_encaminhador(id),  -- origem da sessao do encaminhador
  criada_em         timestamptz NOT NULL DEFAULT now(),
  expira_em         timestamptz NOT NULL,
  encerrada_em      timestamptz,
  CHECK ((tipo = 'EQUIPE') = (usuario_id IS NOT NULL)),
  CHECK ((tipo = 'PACIENTE') = (paciente_id IS NOT NULL AND link_paciente_id IS NOT NULL)),
  CHECK ((tipo = 'ENCAMINHADOR') = (profissional_id IS NOT NULL)),
  CHECK (expira_em > criada_em AND expira_em <= criada_em + interval '12 hours'),
  CHECK (tipo <> 'PACIENTE' OR expira_em <= criada_em + interval '30 minutes')
);

-- ---------------------------------------------------------------------
-- 6. Agenda: vagas e agendamentos (modulo agenda)
-- ---------------------------------------------------------------------
-- VagaEncaminhamento: entidade do briefing mantida so com a forma; uso pelo paciente
-- (modo VAGAS) fica para a Fase 6 (ADR-0031). Sem politica para paciente.
CREATE TABLE vaga_encaminhamento (
  id                         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  clinica_id                 uuid NOT NULL,
  profissional_clinica_id    uuid NOT NULL,
  inicio                     timestamptz NOT NULL,
  fim                        timestamptz NOT NULL,
  liberar_automaticamente_em timestamptz,
  liberada_em                timestamptz,
  CHECK (fim > inicio),
  FOREIGN KEY (clinica_id, profissional_clinica_id) REFERENCES profissional_clinica(clinica_id, id),
  UNIQUE (clinica_id, id)
);

CREATE TABLE agendamento (
  id                       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  clinica_id               uuid NOT NULL,
  profissional_clinica_id  uuid NOT NULL,
  paciente_id              uuid NOT NULL,
  inicio                   timestamptz NOT NULL,
  fim                      timestamptz NOT NULL,
  origem                   text NOT NULL CHECK (origem IN ('SITE','WHATSAPP','RECEPCAO','ENCAMINHAMENTO')),
  encaminhamento_id        uuid,
  vaga_encaminhamento_id   uuid,
  status                   text NOT NULL DEFAULT 'AGENDADO'
                           CHECK (status IN ('AGENDADO','CONFIRMADO','REALIZADO','FALTOU','CANCELADO')),
  status_alterado_por      uuid REFERENCES usuario(id),   -- preenchido por gatilho a partir da sessao
  chave_idempotencia       text NOT NULL,
  criado_em                timestamptz NOT NULL DEFAULT now(),
  atualizado_em            timestamptz NOT NULL DEFAULT now(),
  CHECK (fim > inicio),
  CHECK ((origem = 'ENCAMINHAMENTO') = (encaminhamento_id IS NOT NULL)),
  FOREIGN KEY (clinica_id, profissional_clinica_id) REFERENCES profissional_clinica(clinica_id, id),
  FOREIGN KEY (clinica_id, vaga_encaminhamento_id)  REFERENCES vaga_encaminhamento(clinica_id, id),
  -- Red Team, item 5: paciente so se for vinculado a ESTA clinica; encaminhamento so
  -- se a clinica destino e o paciente forem os mesmos.
  FOREIGN KEY (clinica_id, paciente_id) REFERENCES paciente_clinica(clinica_id, paciente_id),
  FOREIGN KEY (clinica_id, paciente_id, encaminhamento_id) REFERENCES encaminhamento(clinica_destino_id, paciente_id, id),
  UNIQUE (clinica_id, chave_idempotencia),
  EXCLUDE USING gist (profissional_clinica_id WITH =, tstzrange(inicio, fim) WITH &&)
    WHERE (status <> 'CANCELADO')
);
CREATE INDEX agendamento_clinica_inicio_idx ON agendamento (clinica_id, inicio);
CREATE UNIQUE INDEX agendamento_um_ativo_por_encaminhamento ON agendamento (encaminhamento_id)
  WHERE status IN ('AGENDADO','CONFIRMADO');

-- Contrarreferencia: uma por encaminhamento; so com status ATENDIDO e agendamento
-- REALIZADO do proprio medico autor (T-17).
CREATE TABLE contrarreferencia (
  id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  encaminhamento_id     uuid NOT NULL UNIQUE,
  clinica_id            uuid NOT NULL REFERENCES clinica(id),
  autor_profissional_id uuid NOT NULL REFERENCES profissional(id),
  conduta_cifrada       bytea NOT NULL,
  criado_em             timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (clinica_id, encaminhamento_id) REFERENCES encaminhamento(clinica_destino_id, id)
);

-- ---------------------------------------------------------------------
-- 7. Arquivos (modulo arquivos)
-- ---------------------------------------------------------------------
CREATE TABLE anexo_encaminhamento (
  id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  encaminhamento_id     uuid NOT NULL REFERENCES encaminhamento(id),
  chave_storage         text NOT NULL UNIQUE DEFAULT gen_random_uuid()::text,  -- gerada pelo servidor; sem GRANT de escrita
  tipo_mime             text NOT NULL CHECK (tipo_mime IN ('application/pdf','image/jpeg','image/png')),
  tamanho_bytes         bigint NOT NULL CHECK (tamanho_bytes > 0 AND tamanho_bytes <= 20971520),
  sha256                bytea NOT NULL,
  nome_original_cifrado bytea,
  status_varredura      text NOT NULL DEFAULT 'PENDENTE' CHECK (status_varredura IN ('PENDENTE','LIMPO','INFECTADO')),
  enviado_por_tipo      text NOT NULL CHECK (enviado_por_tipo IN ('PROFISSIONAL','PACIENTE')),
  enviado_por_id        uuid NOT NULL,
  criado_em             timestamptz NOT NULL DEFAULT now(),
  varrido_em            timestamptz,
  reter_ate             timestamptz            -- PERGUNTA ABERTA: prazo (Lei 13.787; advogado)
);

-- ---------------------------------------------------------------------
-- 8. Notificacoes (modulo notificacoes): registro de envio SEM corpo (ADR-0034, S2)
-- ---------------------------------------------------------------------
CREATE TABLE envio_notificacao (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  finalidade         text NOT NULL CHECK (finalidade IN ('LINK_PACIENTE','CODIGO_PACIENTE','CODIGO_ENCAMINHADOR',
                                                         'CONFIRMACAO_AGENDAMENTO','AVISO_ORIGEM','LEMBRETE')),
  canal              text NOT NULL CHECK (canal IN ('WHATSAPP','SMS','EMAIL')),
  destinatario_tipo  text NOT NULL CHECK (destinatario_tipo IN ('PACIENTE','PROFISSIONAL')),
  destinatario_id    uuid NOT NULL,
  encaminhamento_id  uuid REFERENCES encaminhamento(id),
  agendamento_id     uuid REFERENCES agendamento(id),
  link_paciente_id   uuid REFERENCES link_paciente(id),
  desafio_id         uuid REFERENCES desafio_encaminhador(id),
  chave_idempotencia text NOT NULL UNIQUE,
  status             text NOT NULL DEFAULT 'PENDENTE' CHECK (status IN ('PENDENTE','PREPARADO','ACEITO','ENTREGUE','FALHOU')),
  tentativas         smallint NOT NULL DEFAULT 0 CHECK (tentativas BETWEEN 0 AND 5),
  id_provedor        text,
  criado_em          timestamptz NOT NULL DEFAULT now(),
  atualizado_em      timestamptz NOT NULL DEFAULT now()
  -- Sem coluna de texto da mensagem, de proposito (briefing: nenhum dado clinico na mensagem).
);
CREATE INDEX envio_pendente_idx ON envio_notificacao (criado_em) WHERE status = 'PENDENTE';

-- ---------------------------------------------------------------------
-- 9. Auditoria (modulo auditoria): SO INCLUSAO
-- ---------------------------------------------------------------------
CREATE TABLE evento_auditoria (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ocorrido_em   timestamptz NOT NULL DEFAULT now(),
  ator_tecnico  text NOT NULL DEFAULT session_user,  -- sobrescrito por gatilho
  ator_papel    text NOT NULL,     -- conferido contra a sessao (politica auditoria_inclui)
  ator_id       uuid,              -- idem; preenchido pela sessao quando nulo
  clinica_id    uuid,
  acao          text NOT NULL,
  recurso_tipo  text NOT NULL,
  recurso_id    uuid,
  ip_origem     inet,
  canal         text
);
CREATE INDEX evento_auditoria_clinica_idx ON evento_auditoria (clinica_id, ocorrido_em);


-- Privilegios do dono das funcoes (concedidos pelo dono das tabelas). O codigo de
-- cada funcao e a barreira; nenhuma funcao executa SQL vindo de parametro.
GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA saas TO saas_funcoes;
REVOKE UPDATE ON saas.evento_auditoria, saas.historico_status_encaminhamento FROM saas_funcoes;

-- =====================================================================
-- 10. Funcoes de contexto (dono saas_funcoes, SECURITY DEFINER, search_path fixo)
-- =====================================================================
SET ROLE saas_funcoes;
SET LOCAL search_path = saas, public;

-- Escolhas de contexto da equipe (conferidas por eh_equipe; nao identificam ninguem).
CREATE FUNCTION app_clinica_id() RETURNS uuid LANGUAGE sql STABLE SET search_path = saas, pg_temp AS
$$ SELECT nullif(current_setting('app.clinica_id', true), '')::uuid $$;
CREATE FUNCTION app_papel() RETURNS text LANGUAGE sql STABLE SET search_path = saas, pg_temp AS
$$ SELECT nullif(current_setting('app.papel', true), '') $$;

-- A unica identidade: sessao valida apresentada pelo token em claro.
-- Hex invalido em app.sessao gera erro (falha fechada).
CREATE FUNCTION sessao_valida() RETURNS sessao LANGUAGE sql STABLE SECURITY DEFINER
  SET search_path = saas, pg_temp AS
$$ SELECT s.* FROM sessao s
    WHERE s.token_hash = sha256(decode(nullif(current_setting('app.sessao', true), ''), 'hex'))
      AND s.expira_em > now() AND s.encerrada_em IS NULL
      -- r2-3 (Testador F3): sessao de equipe de usuario desativado deixa de valer na hora,
      -- para TODA politica e funcao (antes so ator_usuario conferia ativo).
      AND (s.tipo <> 'EQUIPE' OR EXISTS (SELECT 1 FROM usuario u WHERE u.id = s.usuario_id AND u.ativo)) $$;

CREATE FUNCTION ator_tipo() RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path = saas, pg_temp AS
$$ SELECT (sessao_valida()).tipo $$;
CREATE FUNCTION ator_usuario() RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER SET search_path = saas, pg_temp AS
$$ SELECT s.usuario_id FROM sessao_valida() s
    JOIN usuario u ON u.id = s.usuario_id AND u.ativo WHERE s.tipo = 'EQUIPE' $$;
CREATE FUNCTION ator_paciente() RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER SET search_path = saas, pg_temp AS
$$ SELECT s.paciente_id FROM sessao_valida() s WHERE s.tipo = 'PACIENTE' $$;
-- r2-5 (Red Team I-19): a sessao do paciente vale para o CASO do link que a abriu, nao para
-- a pessoa toda. Toda politica e funcao de paciente sobre encaminhamento, agendamento,
-- consentimento e anexo exige id = ator_encaminhamento().
CREATE FUNCTION ator_encaminhamento() RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER SET search_path = saas, pg_temp AS
$$ SELECT l.encaminhamento_id FROM sessao_valida() s
     JOIN link_paciente l ON l.id = s.link_paciente_id AND l.paciente_id = s.paciente_id
    WHERE s.tipo = 'PACIENTE' $$;

-- Membro da equipe: sessao EQUIPE + papel declarado existe e esta ativo na clinica declarada.
CREATE FUNCTION eh_equipe(papeis text[]) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER
  SET search_path = saas, pg_temp AS
$$ SELECT app_clinica_id() IS NOT NULL
      AND coalesce(app_papel() = ANY (papeis), false)
      AND EXISTS (SELECT 1 FROM usuario_clinica uc
                   WHERE uc.usuario_id = ator_usuario()
                     AND uc.clinica_id = app_clinica_id()
                     AND uc.papel = app_papel()
                     AND uc.ativo) $$;

-- Profissional do ator, DERIVADO (Red Team, item 3). app.profissional_id nao existe mais.
CREATE FUNCTION ator_profissional() RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER
  SET search_path = saas, pg_temp AS
$$ SELECT CASE s.tipo
            WHEN 'ENCAMINHADOR' THEN s.profissional_id
            WHEN 'EQUIPE' THEN (
              SELECT p.id FROM profissional p
                JOIN profissional_clinica pc ON pc.profissional_id = p.id
               WHERE p.usuario_id = s.usuario_id
                 AND pc.clinica_id = app_clinica_id() AND pc.ativo
                 AND eh_equipe(ARRAY['MEDICO']))
          END
     FROM sessao_valida() s $$;

CREATE FUNCTION papel_efetivo() RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path = saas, pg_temp AS
$$ SELECT CASE ator_tipo()
            WHEN 'EQUIPE' THEN CASE WHEN eh_equipe(ARRAY[app_papel()]) THEN app_papel() END
            WHEN 'PACIENTE' THEN 'PACIENTE'
            WHEN 'ENCAMINHADOR' THEN 'ENCAMINHADOR' END $$;
CREATE FUNCTION ator_id_efetivo() RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER SET search_path = saas, pg_temp AS
$$ SELECT CASE ator_tipo()
            WHEN 'EQUIPE' THEN ator_usuario()
            WHEN 'PACIENTE' THEN ator_paciente()
            WHEN 'ENCAMINHADOR' THEN ator_profissional() END $$;

CREATE FUNCTION rede_ligada(p_clinica uuid) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER
  SET search_path = saas, pg_temp AS
$$ SELECT EXISTS (SELECT 1 FROM flag_clinica f
                   WHERE f.clinica_id = p_clinica AND f.chave = 'REDE_ENCAMINHAMENTO' AND f.ligada) $$;

-- Auxiliares de politica (evitam recursao). So respondem sobre a clinica do proprio ator.
CREATE FUNCTION consentimento_ativo(p_enc uuid, p_clinica uuid) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER
  SET search_path = saas, pg_temp AS
$$ SELECT p_clinica = app_clinica_id()
      AND eh_equipe(ARRAY['ADMIN','RECEPCAO','MEDICO'])
      AND EXISTS (SELECT 1 FROM consentimento c
                   WHERE c.encaminhamento_id = p_enc AND c.clinica_id = p_clinica
                     AND c.finalidade = 'COMPARTILHAR_CASO' AND c.revogado_em IS NULL) $$;

CREATE FUNCTION pode_contrarreferenciar(p_enc uuid) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER
  SET search_path = saas, pg_temp AS
$$ SELECT eh_equipe(ARRAY['MEDICO']) AND EXISTS (
     SELECT 1 FROM encaminhamento e
       JOIN agendamento a ON a.encaminhamento_id = e.id AND a.clinica_id = e.clinica_destino_id
       JOIN profissional_clinica pc ON pc.id = a.profissional_clinica_id AND pc.clinica_id = a.clinica_id
      WHERE e.id = p_enc AND e.status = 'ATENDIDO' AND e.clinica_destino_id = app_clinica_id()
        AND a.status = 'REALIZADO' AND pc.profissional_id = ator_profissional()) $$;

-- r2-1 (Testador F1): link e envio ao paciente so valem enquanto o encaminhamento nao esta
-- em estado final. Conferido em toda funcao de link e de envio, alem da revogacao por gatilho.
CREATE FUNCTION encaminhamento_aberto(p_enc uuid) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER
  SET search_path = saas, pg_temp AS
$$ SELECT EXISTS (SELECT 1 FROM encaminhamento e WHERE e.id = p_enc
                   AND e.status NOT IN ('CONTRARREFERIDO','EXPIRADO','CANCELADO')) $$;

-- r2-4 (Red Team T-18, ADR-0036): telefone e CONTATO, nao identidade. Dois cadastros sao a
-- mesma pessoa so se (a) o HMAC do CPF bate, ou (b) nome normalizado + data de nascimento +
-- telefone batem e nenhum dos dois tem CPF diferente. Sem CPF e sem data de nascimento:
-- nunca deduplica (registro novo; duplicata se resolve na recepcao, nunca fusao automatica).
CREATE FUNCTION nome_normalizado(p text) RETURNS text LANGUAGE sql IMMUTABLE SET search_path = saas, pg_temp AS
$$ SELECT lower(regexp_replace(btrim(p), '\s+', ' ', 'g')) $$;
CREATE FUNCTION mesma_pessoa(p paciente, p_nome text, p_telefone text, p_nascimento date, p_cpf_hash bytea)
RETURNS boolean LANGUAGE sql IMMUTABLE SET search_path = saas, pg_temp AS
$$ SELECT coalesce(
     (p_cpf_hash IS NOT NULL AND p.cpf_hash = p_cpf_hash)
     OR (p_nascimento IS NOT NULL AND p.data_nascimento = p_nascimento
         AND p.telefone = p_telefone
         AND nome_normalizado(p.nome) = nome_normalizado(p_nome)
         AND (p.cpf_hash IS NULL OR p_cpf_hash IS NULL)), false) $$;

-- Token aleatorio (2 x 122 bits de gen_random_uuid) e codigo de 6 digitos.
CREATE FUNCTION novo_token() RETURNS text LANGUAGE sql VOLATILE SET search_path = saas, pg_temp AS
$$ SELECT replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', '') $$;
CREATE FUNCTION novo_codigo() RETURNS text LANGUAGE sql VOLATILE SET search_path = saas, pg_temp AS
$$ SELECT lpad(((('x' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 8))::bit(32)::bigint) % 1000000)::text, 6, '0') $$;
CREATE FUNCTION hash_token(p text) RETURNS bytea LANGUAGE sql IMMUTABLE SET search_path = saas, pg_temp AS
$$ SELECT sha256(decode(p, 'hex')) $$;
CREATE FUNCTION hash_codigo(p_dono uuid, p_codigo text) RETURNS bytea LANGUAGE sql IMMUTABLE SET search_path = saas, pg_temp AS
$$ SELECT sha256(convert_to(p_dono::text || ':' || p_codigo, 'UTF8')) $$;

-- Registro de auditoria por funcao (ator conferido aqui, nao vindo do chamador).
CREATE FUNCTION audita(p_acao text, p_recurso_tipo text, p_recurso uuid, p_clinica uuid DEFAULT NULL)
RETURNS void LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = saas, pg_temp AS
$$ INSERT INTO evento_auditoria(ator_papel, ator_id, clinica_id, acao, recurso_tipo, recurso_id, canal)
   VALUES (CASE WHEN session_user = 'saas_jobs' THEN 'SISTEMA' ELSE coalesce(papel_efetivo(), 'PUBLICO') END,
           CASE WHEN session_user = 'saas_jobs' THEN NULL ELSE ator_id_efetivo() END,
           p_clinica, p_acao, p_recurso_tipo, p_recurso, 'WEB') $$;

-- =====================================================================
-- 11. Gatilhos (funcoes de gatilho nao podem ser chamadas diretamente)
-- =====================================================================
CREATE FUNCTION bloqueia_alteracao() RETURNS trigger LANGUAGE plpgsql SET search_path = saas, pg_temp AS
$$ BEGIN
  RAISE EXCEPTION 'tabela % e so de inclusao (%)', TG_TABLE_NAME, TG_OP;
END $$;

-- Transicoes T1 a T11 (Red Team, item 10; Testador, maquina de estados; sugestao S3).
-- SECURITY INVOKER de proposito: current_user diz se a mudanca veio de dentro de uma
-- funcao do sistema (saas_funcoes) ou de UPDATE direto do papel web.
--  * Via funcao: so T2 a T8, e o par tem que bater com a transicao declarada pela funcao.
--  * UPDATE direto: so cancelamento (T9 origem, T10 paciente, T11 recepcao ou admin do
--    destino) e urgencia pela origem antes de SOLICITADO. Estados finais sem saida.
--  * Colunas imutaveis para todos (Red Team, item 9), alem do GRANT por coluna.
CREATE FUNCTION transicao_cancelamento(o encaminhamento) RETURNS text LANGUAGE sql STABLE SECURITY DEFINER
  SET search_path = saas, pg_temp AS
$$ SELECT CASE
     WHEN o.status IN ('CRIADO','ENVIADO_AO_PACIENTE','SOLICITADO','AGENDADO')
          AND o.profissional_origem_id = ator_profissional() THEN 'T9'
     WHEN o.status IN ('ENVIADO_AO_PACIENTE','SOLICITADO','AGENDADO')
          AND o.paciente_id = ator_paciente() AND o.id = ator_encaminhamento() THEN 'T10'
     WHEN o.status IN ('SOLICITADO','AGENDADO')
          AND o.clinica_destino_id = app_clinica_id() AND eh_equipe(ARRAY['ADMIN','RECEPCAO']) THEN 'T11'
   END $$;

CREATE FUNCTION transicao_sistema(de text, para text) RETURNS text LANGUAGE sql IMMUTABLE SET search_path = saas, pg_temp AS
$$ SELECT CASE
     WHEN de = 'CRIADO' AND para = 'ENVIADO_AO_PACIENTE' THEN 'T2'
     WHEN de = 'ENVIADO_AO_PACIENTE' AND para = 'SOLICITADO' THEN 'T3'
     WHEN de = 'SOLICITADO' AND para = 'AGENDADO' THEN 'T4'
     WHEN de = 'AGENDADO' AND para = 'ATENDIDO' THEN 'T5'
     WHEN de = 'ATENDIDO' AND para = 'CONTRARREFERIDO' THEN 'T6'
     WHEN de = 'AGENDADO' AND para = 'SOLICITADO' THEN 'T7'
     WHEN de IN ('CRIADO','ENVIADO_AO_PACIENTE','SOLICITADO') AND para = 'EXPIRADO' THEN 'T8'
   END $$;

CREATE FUNCTION encaminhamento_valida() RETURNS trigger LANGUAGE plpgsql SET search_path = saas, pg_temp AS
$$ DECLARE
  via_funcao boolean := (current_user = 'saas_funcoes');
  t text;
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.status <> 'CRIADO' THEN RAISE EXCEPTION 'encaminhamento nasce CRIADO (T1)'; END IF;
    RETURN NEW;
  END IF;
  IF NEW.id <> OLD.id OR NEW.paciente_id <> OLD.paciente_id
     OR NEW.profissional_origem_id <> OLD.profissional_origem_id
     OR NEW.especialidade_destino_id <> OLD.especialidade_destino_id
     OR NEW.motivo_cifrado <> OLD.motivo_cifrado OR NEW.criado_em <> OLD.criado_em THEN
    RAISE EXCEPTION 'coluna imutavel do encaminhamento';
  END IF;
  IF NEW.status IS DISTINCT FROM OLD.status THEN
    IF via_funcao THEN
      t := transicao_sistema(OLD.status, NEW.status);
      IF t IS NULL OR t IS DISTINCT FROM nullif(current_setting('saas.transicao', true), '') THEN
        RAISE EXCEPTION 'transicao % -> % recusada', OLD.status, NEW.status;
      END IF;
    ELSE
      IF NEW.status = 'CANCELADO' THEN t := transicao_cancelamento(OLD); END IF;
      IF t IS NULL THEN
        RAISE EXCEPTION 'transicao % -> % recusada para este ator', OLD.status, NEW.status;
      END IF;
    END IF;
  END IF;
  IF (NEW.clinica_destino_id IS DISTINCT FROM OLD.clinica_destino_id
      OR NEW.profissional_destino_id IS DISTINCT FROM OLD.profissional_destino_id)
     AND NOT (via_funcao AND t = 'T3') THEN
    RAISE EXCEPTION 'destino so muda na transicao T3';
  END IF;
  IF NEW.expira_em <> OLD.expira_em AND NOT (via_funcao AND t = 'T7') THEN
    RAISE EXCEPTION 'expira_em so muda na transicao T7';
  END IF;
  -- coalesce: sem ator, a comparacao da NULL e o IF nao pode tratar NULL como permissao.
  IF NEW.urgencia <> OLD.urgencia
     AND NOT (NOT via_funcao AND OLD.status IN ('CRIADO','ENVIADO_AO_PACIENTE')
              AND coalesce(OLD.profissional_origem_id = ator_profissional(), false)) THEN
    RAISE EXCEPTION 'urgencia so muda pela origem antes de SOLICITADO';
  END IF;
  NEW.atualizado_em := now();
  RETURN NEW;
END $$;

-- Depois da transicao: historico (unica forma de escrever nele) e efeitos.
-- SECURITY DEFINER: grava historico e cancela o agendamento ativo em T9 a T11 a partir
-- de AGENDADO (o paciente e a origem nao alteram agenda; S1 item d).
CREATE FUNCTION encaminhamento_apos_transicao() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
  SET search_path = saas, pg_temp AS
$$ DECLARE
  v_t text; v_tipo text; v_papel text; v_id uuid; v_autor uuid;
BEGIN
  IF TG_OP = 'UPDATE' AND NEW.status IS NOT DISTINCT FROM OLD.status THEN RETURN NULL; END IF;
  IF TG_OP = 'INSERT' THEN v_t := 'T1';
  ELSIF NEW.status = 'CANCELADO' THEN v_t := transicao_cancelamento(OLD);
  ELSE v_t := transicao_sistema(OLD.status, NEW.status); END IF;
  IF session_user = 'saas_jobs' THEN v_tipo := 'SISTEMA';
  ELSE v_tipo := coalesce(ator_tipo(), 'OPERACAO'); v_papel := papel_efetivo(); v_id := ator_id_efetivo();
  END IF;
  IF v_t IN ('T5','T7') THEN
    SELECT a.status_alterado_por INTO v_autor FROM agendamento a
     WHERE a.encaminhamento_id = NEW.id ORDER BY a.atualizado_em DESC LIMIT 1;
  END IF;
  INSERT INTO historico_status_encaminhamento
    (encaminhamento_id, status_anterior, status_novo, transicao, ator_tecnico, ator_tipo, ator_papel, ator_id, autor_negocio_id)
  VALUES (NEW.id, CASE WHEN TG_OP = 'UPDATE' THEN OLD.status END, NEW.status, coalesce(v_t, 'T1'),
          session_user, v_tipo, v_papel, v_id, v_autor);
  IF TG_OP = 'UPDATE' AND NEW.status = 'CANCELADO' AND OLD.status = 'AGENDADO' THEN
    UPDATE agendamento SET status = 'CANCELADO'
     WHERE encaminhamento_id = NEW.id AND status IN ('AGENDADO','CONFIRMADO');
  END IF;
  -- r2-1: estado final revoga todo link ativo e derruba todo envio ainda nao preparado.
  IF TG_OP = 'UPDATE' AND NEW.status IN ('CONTRARREFERIDO','EXPIRADO','CANCELADO') THEN
    UPDATE link_paciente SET revogado_em = now()
     WHERE encaminhamento_id = NEW.id AND usado_em IS NULL AND revogado_em IS NULL;
    UPDATE envio_notificacao SET status = 'FALHOU', atualizado_em = now()
     WHERE encaminhamento_id = NEW.id AND status = 'PENDENTE'
       AND finalidade IN ('LINK_PACIENTE','CODIGO_PACIENTE');
  END IF;
  RETURN NULL;
END $$;

-- Agendamento: quem mudou o status vem da sessao, nunca do cliente (autor de negocio de T5 e T7).
-- r2-2 (Testador F2): status do agendamento so anda para a frente. REALIZADO, FALTOU e
-- CANCELADO sao finais (nem status nem horario mudam); AGENDADO -> CONFIRMADO e a unica
-- mudanca entre ativos. Mantem a invariante "encaminhamento AGENDADO <=> agendamento ativo":
-- reabrir a agenda exige agendamento NOVO, que para encaminhamento so nasce por T4.
CREATE FUNCTION agendamento_marca_autor() RETURNS trigger LANGUAGE plpgsql SET search_path = saas, pg_temp AS
$$ BEGIN
  IF TG_OP = 'UPDATE' THEN
    IF OLD.status IN ('REALIZADO','FALTOU','CANCELADO')
       AND (NEW.status, NEW.inicio, NEW.fim, NEW.profissional_clinica_id, NEW.vaga_encaminhamento_id)
           IS DISTINCT FROM (OLD.status, OLD.inicio, OLD.fim, OLD.profissional_clinica_id, OLD.vaga_encaminhamento_id) THEN
      RAISE EXCEPTION 'agendamento % e final', OLD.status;
    END IF;
    IF OLD.status = 'CONFIRMADO' AND NEW.status = 'AGENDADO' THEN
      RAISE EXCEPTION 'agendamento CONFIRMADO nao volta a AGENDADO';
    END IF;
  END IF;
  IF TG_OP = 'INSERT' OR NEW.status IS DISTINCT FROM OLD.status THEN
    NEW.status_alterado_por := coalesce(ator_usuario(), CASE WHEN TG_OP = 'UPDATE' THEN OLD.status_alterado_por ELSE NEW.status_alterado_por END);
  END IF;
  NEW.atualizado_em := now();
  RETURN NEW;
END $$;

-- Contrarreferencia gravada: T6.
CREATE FUNCTION contrarreferencia_t6() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = saas, pg_temp AS
$$ BEGIN
  PERFORM set_config('saas.transicao', 'T6', true);
  UPDATE encaminhamento SET status = 'CONTRARREFERIDO' WHERE id = NEW.encaminhamento_id;
  PERFORM set_config('saas.transicao', '', true);
  RETURN NULL;
END $$;

-- Anexo: depois de gravado, so status_varredura de PENDENTE para LIMPO ou INFECTADO (item 14).
CREATE FUNCTION anexo_valida_update() RETURNS trigger LANGUAGE plpgsql SET search_path = saas, pg_temp AS
$$ BEGIN
  IF (NEW.id, NEW.encaminhamento_id, NEW.chave_storage, NEW.tipo_mime, NEW.tamanho_bytes, NEW.sha256,
      NEW.nome_original_cifrado, NEW.enviado_por_tipo, NEW.enviado_por_id, NEW.criado_em, NEW.reter_ate)
     IS DISTINCT FROM
     (OLD.id, OLD.encaminhamento_id, OLD.chave_storage, OLD.tipo_mime, OLD.tamanho_bytes, OLD.sha256,
      OLD.nome_original_cifrado, OLD.enviado_por_tipo, OLD.enviado_por_id, OLD.criado_em, OLD.reter_ate) THEN
    RAISE EXCEPTION 'anexo e imutavel; so o status de varredura muda';
  END IF;
  IF NOT (OLD.status_varredura = 'PENDENTE' AND NEW.status_varredura IN ('LIMPO','INFECTADO')) THEN
    RAISE EXCEPTION 'varredura so de PENDENTE para LIMPO ou INFECTADO';
  END IF;
  RETURN NEW;
END $$;

-- Link: hash, dono e validade imutaveis; tentativas nunca diminuem; uso e revogacao uma vez so.
CREATE FUNCTION link_valida_update() RETURNS trigger LANGUAGE plpgsql SET search_path = saas, pg_temp AS
$$ BEGIN
  IF NEW.id <> OLD.id OR NEW.token_hash <> OLD.token_hash OR NEW.encaminhamento_id <> OLD.encaminhamento_id
     OR NEW.paciente_id <> OLD.paciente_id OR NEW.expira_em <> OLD.expira_em OR NEW.criado_em <> OLD.criado_em
     OR NEW.tentativas_codigo < OLD.tentativas_codigo
     OR (OLD.usado_em IS NOT NULL AND NEW.usado_em IS DISTINCT FROM OLD.usado_em)
     OR (OLD.revogado_em IS NOT NULL AND NEW.revogado_em IS DISTINCT FROM OLD.revogado_em) THEN
    RAISE EXCEPTION 'link_paciente: alteracao recusada';
  END IF;
  RETURN NEW;
END $$;

-- Auditoria: ator tecnico sempre do banco; ator_id preenchido pela sessao quando vier nulo.
CREATE FUNCTION auditoria_preenche() RETURNS trigger LANGUAGE plpgsql SET search_path = saas, pg_temp AS
$$ BEGIN
  NEW.ator_tecnico := session_user;
  NEW.ocorrido_em := now();
  IF NEW.ator_id IS NULL AND current_user <> 'saas_funcoes' THEN NEW.ator_id := ator_id_efetivo(); END IF;
  RETURN NEW;
END $$;

-- =====================================================================
-- 12. Funcoes da aplicacao web (EXECUTE so para saas_app). Cada uma confere o ator pela sessao.
-- =====================================================================

-- Login OIDC da equipe (EXECUTE so para saas_auth). Devolve o token de sessao em claro, uma vez.
CREATE FUNCTION sessao_equipe_abre(p_sub_oidc text) RETURNS text LANGUAGE plpgsql VOLATILE SECURITY DEFINER
  SET search_path = saas, pg_temp AS
$$ DECLARE u uuid; tok text := novo_token();
BEGIN
  SELECT id INTO u FROM usuario WHERE sub_oidc = p_sub_oidc AND ativo;
  IF u IS NULL THEN RAISE EXCEPTION 'nao permitido'; END IF;
  INSERT INTO sessao(token_hash, tipo, usuario_id, expira_em) VALUES (hash_token(tok), 'EQUIPE', u, now() + interval '12 hours');
  RETURN tok;
END $$;

CREATE FUNCTION sessao_encerra() RETURNS void LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = saas, pg_temp AS
$$ UPDATE sessao SET encerrada_em = now()
    WHERE token_hash = sha256(decode(nullif(current_setting('app.sessao', true), ''), 'hex')) AND encerrada_em IS NULL $$;

-- Link do paciente. GET da pagina chama so link_consulta: nao consome, nao mostra dado (ADR-0026).
CREATE FUNCTION link_consulta(p_token text) RETURNS TABLE (valido boolean, codigo_enviado boolean, expira_em timestamptz)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = saas, pg_temp AS
$$ SELECT true, l.codigo_hash IS NOT NULL AND l.codigo_expira_em > now(), l.expira_em
     FROM link_paciente l
    WHERE l.token_hash = hash_token(p_token) AND l.expira_em > now()
      AND l.usado_em IS NULL AND l.revogado_em IS NULL
      AND encaminhamento_aberto(l.encaminhamento_id) $$;   -- r2-1

-- Pedido de codigo: limite por link e por paciente por hora (D-04). Envio feito pelo saas_jobs.
CREATE FUNCTION paciente_pede_codigo(p_token text) RETURNS boolean LANGUAGE plpgsql VOLATILE SECURITY DEFINER
  SET search_path = saas, pg_temp AS
$$ DECLARE l link_paciente;
BEGIN
  SELECT * INTO l FROM link_paciente
   WHERE token_hash = hash_token(p_token) AND expira_em > now() AND usado_em IS NULL AND revogado_em IS NULL;
  IF l.id IS NULL OR NOT encaminhamento_aberto(l.encaminhamento_id) THEN RETURN false; END IF;   -- r2-1
  IF (SELECT count(*) FROM envio_notificacao WHERE link_paciente_id = l.id AND finalidade = 'CODIGO_PACIENTE'
        AND criado_em > now() - interval '1 hour') >= 3
     OR (SELECT count(*) FROM envio_notificacao WHERE destinatario_tipo = 'PACIENTE' AND destinatario_id = l.paciente_id
        AND finalidade = 'CODIGO_PACIENTE' AND criado_em > now() - interval '1 hour') >= 5 THEN
    RETURN false;
  END IF;
  INSERT INTO envio_notificacao(finalidade, canal, destinatario_tipo, destinatario_id, encaminhamento_id, link_paciente_id, chave_idempotencia)
  VALUES ('CODIGO_PACIENTE', 'WHATSAPP', 'PACIENTE', l.paciente_id, l.encaminhamento_id, l.id, 'CODP:' || gen_random_uuid());
  RETURN true;
END $$;

-- Troca link + codigo por sessao de paciente (POST). Limite de tentativas somado por
-- encaminhamento (10, inclui links revogados) e por paciente em 24 h (20): reemitir
-- link nao zera (Red Team, item 13; D-03). Erro de codigo devolve NULL sem desfazer a contagem.
CREATE FUNCTION paciente_confirma_codigo(p_token text, p_codigo text) RETURNS text LANGUAGE plpgsql VOLATILE SECURITY DEFINER
  SET search_path = saas, pg_temp AS
$$ DECLARE l link_paciente; tok text;
BEGIN
  SELECT * INTO l FROM link_paciente
   WHERE token_hash = hash_token(p_token) AND expira_em > now() AND usado_em IS NULL AND revogado_em IS NULL
   FOR UPDATE;
  IF l.id IS NULL OR NOT encaminhamento_aberto(l.encaminhamento_id) THEN RETURN NULL; END IF;   -- r2-1
  IF (SELECT sum(tentativas_codigo) FROM link_paciente WHERE encaminhamento_id = l.encaminhamento_id) >= 10
     OR (SELECT sum(tentativas_codigo) FROM link_paciente WHERE paciente_id = l.paciente_id
          AND criado_em > now() - interval '24 hours') >= 20
     OR l.tentativas_codigo >= 10 THEN
    RETURN NULL;
  END IF;
  IF l.codigo_hash IS NULL OR l.codigo_expira_em <= now() OR l.codigo_hash <> hash_codigo(l.id, p_codigo) THEN
    UPDATE link_paciente SET tentativas_codigo = tentativas_codigo + 1 WHERE id = l.id;
    RETURN NULL;
  END IF;
  UPDATE link_paciente SET usado_em = now() WHERE id = l.id;
  tok := novo_token();
  INSERT INTO sessao(token_hash, tipo, paciente_id, link_paciente_id, expira_em)
  VALUES (hash_token(tok), 'PACIENTE', l.paciente_id, l.id, now() + interval '30 minutes');
  INSERT INTO evento_auditoria(ator_papel, ator_id, acao, recurso_tipo, recurso_id, canal)
  VALUES ('PACIENTE', l.paciente_id, 'ABRIR_SESSAO_PACIENTE', 'link_paciente', l.id, 'WEB');
  RETURN tok;
END $$;

-- Medico que encaminha sem conta (ADR-0025). Sempre devolve um token de desafio, exista
-- o CRM ou nao (sem oraculo). Digitar CRM nunca abre registro: o codigo vai so para o
-- telefone cadastrado do proprio medico, gerado e enviado pelo saas_jobs.
CREATE FUNCTION encaminhador_pede_codigo(p_crm text, p_uf text) RETURNS text LANGUAGE plpgsql VOLATILE SECURITY DEFINER
  SET search_path = saas, pg_temp AS
$$ DECLARE p uuid; tok text := novo_token(); d uuid;
BEGIN
  SELECT id INTO p FROM profissional WHERE crm = p_crm AND crm_uf = upper(p_uf) AND telefone IS NOT NULL;
  IF p IS NOT NULL AND (SELECT count(*) FROM desafio_encaminhador WHERE profissional_id = p
                          AND criado_em > now() - interval '1 hour') < 3 THEN
    INSERT INTO desafio_encaminhador(profissional_id, desafio_hash, expira_em)
    VALUES (p, hash_token(tok), now() + interval '15 minutes') RETURNING id INTO d;
    INSERT INTO envio_notificacao(finalidade, canal, destinatario_tipo, destinatario_id, desafio_id, chave_idempotencia)
    VALUES ('CODIGO_ENCAMINHADOR', 'WHATSAPP', 'PROFISSIONAL', p, d, 'CODE:' || d);
  END IF;
  RETURN tok;
END $$;

-- Cadastro pelo formulario: CRM ja existente nao revela nada nem cria nada; CRM novo
-- nasce isolado (sem sessao) ate o codigo enviado ao telefone informado ser confirmado.
CREATE FUNCTION encaminhador_cadastra(p_crm text, p_uf text, p_nome text, p_telefone text, p_email text)
RETURNS text LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = saas, pg_temp AS
$$ DECLARE p uuid; tok text := novo_token(); d uuid;
BEGIN
  IF EXISTS (SELECT 1 FROM profissional WHERE crm = p_crm AND crm_uf = upper(p_uf)) THEN
    RETURN tok;   -- token sem desafio: nunca confirma
  END IF;
  INSERT INTO profissional(crm, crm_uf, nome, telefone, email) VALUES (p_crm, upper(p_uf), p_nome, p_telefone, p_email)
  RETURNING id INTO p;
  INSERT INTO desafio_encaminhador(profissional_id, desafio_hash, expira_em)
  VALUES (p, hash_token(tok), now() + interval '15 minutes') RETURNING id INTO d;
  INSERT INTO envio_notificacao(finalidade, canal, destinatario_tipo, destinatario_id, desafio_id, chave_idempotencia)
  VALUES ('CODIGO_ENCAMINHADOR', 'WHATSAPP', 'PROFISSIONAL', p, d, 'CODE:' || d);
  RETURN tok;
END $$;

CREATE FUNCTION encaminhador_confirma_codigo(p_desafio text, p_codigo text) RETURNS text LANGUAGE plpgsql VOLATILE SECURITY DEFINER
  SET search_path = saas, pg_temp AS
$$ DECLARE d desafio_encaminhador; tok text;
BEGIN
  SELECT * INTO d FROM desafio_encaminhador
   WHERE desafio_hash = hash_token(p_desafio) AND expira_em > now() AND usado_em IS NULL FOR UPDATE;
  IF d.id IS NULL OR d.tentativas >= 5 THEN RETURN NULL; END IF;
  IF d.codigo_hash IS NULL OR d.codigo_expira_em <= now() OR d.codigo_hash <> hash_codigo(d.id, p_codigo) THEN
    UPDATE desafio_encaminhador SET tentativas = tentativas + 1 WHERE id = d.id;
    RETURN NULL;
  END IF;
  UPDATE desafio_encaminhador SET usado_em = now() WHERE id = d.id;
  UPDATE profissional SET canal_verificado_em = coalesce(canal_verificado_em, now()) WHERE id = d.profissional_id;
  tok := novo_token();
  INSERT INTO sessao(token_hash, tipo, profissional_id, desafio_id, expira_em)
  VALUES (hash_token(tok), 'ENCAMINHADOR', d.profissional_id, d.id, now() + interval '12 hours');
  INSERT INTO evento_auditoria(ator_papel, ator_id, acao, recurso_tipo, recurso_id, canal)
  VALUES ('ENCAMINHADOR', d.profissional_id, 'ABRIR_SESSAO_ENCAMINHADOR', 'desafio_encaminhador', d.id, 'WEB');
  RETURN tok;
END $$;

-- T1. paciente_id NUNCA vem do cliente (Red Team, itens 6 e 8; ADR-0029): o paciente e
-- localizado so entre os ja ligados ao ator (encaminhamentos do mesmo profissional ou,
-- para MEDICO, pacientes vinculados a clinica); senao nasce um registro novo.
CREATE FUNCTION encaminhamento_cria(p_nome text, p_telefone text, p_nascimento date, p_cpf_cifrado bytea, p_cpf_hash bytea,
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

-- Cadastro de paciente pela recepcao: mesma regra de deduplicacao, restrita a clinica.
CREATE FUNCTION paciente_cadastra_na_clinica(p_nome text, p_telefone text, p_nascimento date, p_cpf_cifrado bytea, p_cpf_hash bytea)
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

-- Troca de telefone: so presencial, pela recepcao ou admin da clinica que CADASTROU o
-- paciente, auditada (Red Team, item 7). Paciente e outras clinicas nao trocam.
CREATE FUNCTION paciente_troca_telefone_presencial(p_paciente uuid, p_novo text) RETURNS void LANGUAGE plpgsql VOLATILE SECURITY DEFINER
  SET search_path = saas, pg_temp AS
$$ BEGIN
  IF NOT eh_equipe(ARRAY['ADMIN','RECEPCAO'])
     OR NOT EXISTS (SELECT 1 FROM paciente WHERE id = p_paciente AND cadastrado_por_clinica_id = app_clinica_id()) THEN
    RAISE EXCEPTION 'nao permitido';
  END IF;
  UPDATE paciente SET telefone = p_novo WHERE id = p_paciente;
  PERFORM audita('TROCAR_TELEFONE_PRESENCIAL', 'paciente', p_paciente, app_clinica_id());
END $$;

-- Catalogo da rede (Red Team, item 17): so com sessao valida, so clinicas com a rede ligada
-- e a especialidade, sem cnpj nem contato.
CREATE FUNCTION catalogo_rede(p_especialidade uuid) RETURNS TABLE (clinica_id uuid, nome text, modo_recebimento text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = saas, pg_temp AS
$$ SELECT c.id, c.nome, c.modo_recebimento FROM clinica c
    JOIN clinica_especialidade ce ON ce.clinica_id = c.id AND ce.especialidade_id = p_especialidade
   WHERE ator_tipo() IS NOT NULL AND rede_ligada(c.id) $$;

-- T3: paciente escolhe destino e consente, numa so transacao. Flag da rede imposta aqui.
CREATE FUNCTION paciente_solicita(p_enc uuid, p_clinica uuid, p_profissional uuid, p_texto text, p_versao text)
RETURNS void LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = saas, pg_temp AS
$$ DECLARE e encaminhamento;
BEGIN
  SELECT * INTO e FROM encaminhamento WHERE id = p_enc AND paciente_id = ator_paciente()
     AND id = ator_encaminhamento()   -- r2-5
     AND status = 'ENVIADO_AO_PACIENTE' FOR UPDATE;
  IF e.id IS NULL OR NOT rede_ligada(p_clinica)
     OR NOT EXISTS (SELECT 1 FROM clinica_especialidade WHERE clinica_id = p_clinica AND especialidade_id = e.especialidade_destino_id)
     OR (p_profissional IS NOT NULL AND NOT EXISTS (SELECT 1 FROM profissional_clinica
           WHERE profissional_id = p_profissional AND clinica_id = p_clinica AND ativo AND recebe_encaminhamento)) THEN
    RAISE EXCEPTION 'nao permitido';
  END IF;
  PERFORM set_config('saas.transicao', 'T3', true);
  UPDATE encaminhamento SET clinica_destino_id = p_clinica, profissional_destino_id = p_profissional, status = 'SOLICITADO'
   WHERE id = p_enc;
  PERFORM set_config('saas.transicao', '', true);
  INSERT INTO consentimento(paciente_id, finalidade, encaminhamento_id, clinica_id, texto_aceito, versao_texto, canal)
  VALUES (e.paciente_id, 'COMPARTILHAR_CASO', p_enc, p_clinica, p_texto, p_versao, 'SITE');
  PERFORM audita('SOLICITAR_ENCAMINHAMENTO', 'encaminhamento', p_enc, p_clinica);
END $$;

-- T4 (modo PEDIDO): recepcao ou admin da clinica destino confirma o horario.
CREATE FUNCTION destino_confirma_horario(p_enc uuid, p_profissional_clinica uuid, p_inicio timestamptz, p_fim timestamptz, p_chave text)
RETURNS uuid LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = saas, pg_temp AS
$$ DECLARE e encaminhamento; a uuid;
BEGIN
  IF NOT eh_equipe(ARRAY['ADMIN','RECEPCAO']) THEN RAISE EXCEPTION 'nao permitido'; END IF;
  SELECT * INTO e FROM encaminhamento WHERE id = p_enc AND clinica_destino_id = app_clinica_id()
     AND status = 'SOLICITADO' FOR UPDATE;
  IF e.id IS NULL OR NOT consentimento_ativo(p_enc, app_clinica_id()) OR NOT rede_ligada(app_clinica_id()) THEN
    RAISE EXCEPTION 'nao permitido';
  END IF;
  INSERT INTO paciente_clinica(paciente_id, clinica_id, encaminhamento_id) VALUES (e.paciente_id, app_clinica_id(), p_enc)
  ON CONFLICT (clinica_id, paciente_id) DO NOTHING;
  INSERT INTO agendamento(clinica_id, profissional_clinica_id, paciente_id, inicio, fim, origem, encaminhamento_id, chave_idempotencia)
  VALUES (app_clinica_id(), p_profissional_clinica, e.paciente_id, p_inicio, p_fim, 'ENCAMINHAMENTO', p_enc, p_chave)
  RETURNING id INTO a;
  PERFORM set_config('saas.transicao', 'T4', true);
  UPDATE encaminhamento SET status = 'AGENDADO' WHERE id = p_enc;
  PERFORM set_config('saas.transicao', '', true);
  RETURN a;
END $$;

-- =====================================================================
-- 13. Funcoes de jobs e listeners (EXECUTE so para saas_jobs). Uma por acao,
--     nenhuma "SISTEMA ve tudo" (Red Team, item 18; S1). Cada uma rele o estado na fonte.
-- =====================================================================
CREATE FUNCTION jobs_envios_pendentes(p_limite int) RETURNS TABLE (envio_id uuid, finalidade text, canal text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = saas, pg_temp AS
$$ SELECT id, finalidade, canal FROM envio_notificacao
    WHERE status = 'PENDENTE' AND tentativas < 5 ORDER BY criado_em LIMIT least(p_limite, 100) $$;

-- Listener de EncaminhamentoCriado: agenda o envio do link (idempotente). So se a origem
-- estiver verificada (S-02: nada sai ao paciente por encaminhador nao verificado).
CREATE FUNCTION jobs_envio_link_paciente(p_enc uuid) RETURNS uuid LANGUAGE plpgsql VOLATILE SECURITY DEFINER
  SET search_path = saas, pg_temp AS
$$ DECLARE e encaminhamento; v uuid; n int;
BEGIN
  SELECT * INTO e FROM encaminhamento WHERE id = p_enc AND status IN ('CRIADO','ENVIADO_AO_PACIENTE');
  IF e.id IS NULL OR NOT EXISTS (SELECT 1 FROM profissional p WHERE p.id = e.profissional_origem_id
                                   AND (p.canal_verificado_em IS NOT NULL OR p.usuario_id IS NOT NULL)) THEN
    RAISE EXCEPTION 'nao permitido';
  END IF;
  SELECT count(*) INTO n FROM link_paciente WHERE encaminhamento_id = p_enc;
  INSERT INTO envio_notificacao(finalidade, canal, destinatario_tipo, destinatario_id, encaminhamento_id, chave_idempotencia)
  VALUES ('LINK_PACIENTE', 'WHATSAPP', 'PACIENTE', e.paciente_id, p_enc, 'LINK:' || p_enc || ':' || n)
  ON CONFLICT (chave_idempotencia) DO NOTHING RETURNING id INTO v;
  IF v IS NULL THEN SELECT id INTO v FROM envio_notificacao WHERE chave_idempotencia = 'LINK:' || p_enc || ':' || n; END IF;
  RETURN v;
END $$;

-- Prepara UM envio: devolve so o contato do destinatario daquele envio e o segredo gerado
-- agora (token do link ou codigo). O segredo nunca passa por evento nem fica gravado em claro.
CREATE FUNCTION jobs_envio_prepara(p_envio uuid) RETURNS TABLE (canal text, contato text, segredo text)
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

-- Resultado do provedor. T2 so quando o envio do LINK foi aceito e o encaminhamento ainda esta CRIADO.
CREATE FUNCTION jobs_envio_resultado(p_envio uuid, p_status text, p_id_provedor text) RETURNS boolean LANGUAGE plpgsql VOLATILE SECURITY DEFINER
  SET search_path = saas, pg_temp AS
$$ DECLARE v envio_notificacao; n int;
BEGIN
  IF p_status NOT IN ('ACEITO','ENTREGUE','FALHOU') THEN RAISE EXCEPTION 'status invalido'; END IF;
  UPDATE envio_notificacao SET status = p_status, id_provedor = p_id_provedor, atualizado_em = now()
   WHERE id = p_envio AND status IN ('PREPARADO','ACEITO') RETURNING * INTO v;
  IF v.id IS NULL THEN RAISE EXCEPTION 'envio inexistente'; END IF;
  IF v.finalidade = 'LINK_PACIENTE' AND p_status = 'ACEITO' THEN
    PERFORM set_config('saas.transicao', 'T2', true);
    UPDATE encaminhamento SET status = 'ENVIADO_AO_PACIENTE' WHERE id = v.encaminhamento_id AND status = 'CRIADO';
    GET DIAGNOSTICS n = ROW_COUNT;
    PERFORM set_config('saas.transicao', '', true);
    RETURN n = 1;
  END IF;
  RETURN false;
END $$;

-- T8 com WHERE (Testador, falha 6; Red Team, item 16). Devolve quantos expiraram.
CREATE FUNCTION jobs_expirar_encaminhamentos() RETURNS integer LANGUAGE plpgsql VOLATILE SECURITY DEFINER
  SET search_path = saas, pg_temp AS
$$ DECLARE n int;
BEGIN
  PERFORM set_config('saas.transicao', 'T8', true);
  UPDATE encaminhamento SET status = 'EXPIRADO'
   WHERE expira_em < now() AND status IN ('CRIADO','ENVIADO_AO_PACIENTE','SOLICITADO');
  GET DIAGNOSTICS n = ROW_COUNT;
  PERFORM set_config('saas.transicao', '', true);
  RETURN n;
END $$;

-- T5: listener de ConsultaRealizada. Rele o agendamento: tem que estar REALIZADO, ligado a
-- encaminhamento AGENDADO da mesma clinica destino (Red Team, item 21 antecipado).
CREATE FUNCTION jobs_consulta_realizada(p_agendamento uuid) RETURNS boolean LANGUAGE plpgsql VOLATILE SECURITY DEFINER
  SET search_path = saas, pg_temp AS
$$ DECLARE n int;
BEGIN
  PERFORM set_config('saas.transicao', 'T5', true);
  UPDATE encaminhamento e SET status = 'ATENDIDO'
    FROM agendamento a
   WHERE a.id = p_agendamento AND a.status = 'REALIZADO' AND a.encaminhamento_id = e.id
     AND a.clinica_id = e.clinica_destino_id AND e.status = 'AGENDADO';
  GET DIAGNOSTICS n = ROW_COUNT;
  PERFORM set_config('saas.transicao', '', true);
  RETURN n = 1;
END $$;

-- T7: listener de AgendamentoCancelado e PacienteFaltou. So se nao houver outro agendamento ativo.
CREATE FUNCTION jobs_agendamento_desfeito(p_agendamento uuid) RETURNS boolean LANGUAGE plpgsql VOLATILE SECURITY DEFINER
  SET search_path = saas, pg_temp AS
$$ DECLARE n int;
BEGIN
  PERFORM set_config('saas.transicao', 'T7', true);
  UPDATE encaminhamento e SET status = 'SOLICITADO', expira_em = now() + interval '30 days'
    FROM agendamento a
   WHERE a.id = p_agendamento AND a.status IN ('CANCELADO','FALTOU') AND a.encaminhamento_id = e.id
     AND a.clinica_id = e.clinica_destino_id AND e.status = 'AGENDADO'
     AND NOT EXISTS (SELECT 1 FROM agendamento b WHERE b.encaminhamento_id = e.id AND b.status IN ('AGENDADO','CONFIRMADO'));
  GET DIAGNOSTICS n = ROW_COUNT;
  PERFORM set_config('saas.transicao', '', true);
  RETURN n = 1;
END $$;

-- Varredura de anexo: so status, so a partir de PENDENTE (Red Team, item 14).
CREATE FUNCTION jobs_anexo_varredura(p_anexo uuid, p_resultado text) RETURNS void LANGUAGE plpgsql VOLATILE SECURITY DEFINER
  SET search_path = saas, pg_temp AS
$$ BEGIN
  IF p_resultado NOT IN ('LIMPO','INFECTADO') THEN RAISE EXCEPTION 'resultado invalido'; END IF;
  UPDATE anexo_encaminhamento SET status_varredura = p_resultado, varrido_em = now()
   WHERE id = p_anexo AND status_varredura = 'PENDENTE';
  IF NOT FOUND THEN RAISE EXCEPTION 'anexo inexistente ou ja varrido'; END IF;
END $$;


-- Nenhuma funcao executavel por PUBLIC (alem do privilegio padrao do bootstrap).
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA saas FROM PUBLIC;


-- =====================================================================
-- 14. Gatilhos nas tabelas (criados pelo dono)
-- =====================================================================
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA saas TO saas_owner;
SET ROLE saas_owner;
SET LOCAL search_path = saas, public;

CREATE TRIGGER evento_auditoria_so_inclusao
  BEFORE UPDATE OR DELETE ON evento_auditoria FOR EACH ROW EXECUTE FUNCTION bloqueia_alteracao();
CREATE TRIGGER evento_auditoria_sem_truncate
  BEFORE TRUNCATE ON evento_auditoria FOR EACH STATEMENT EXECUTE FUNCTION bloqueia_alteracao();
CREATE TRIGGER evento_auditoria_preenche
  BEFORE INSERT ON evento_auditoria FOR EACH ROW EXECUTE FUNCTION auditoria_preenche();
CREATE TRIGGER historico_so_inclusao
  BEFORE UPDATE OR DELETE ON historico_status_encaminhamento FOR EACH ROW EXECUTE FUNCTION bloqueia_alteracao();
CREATE TRIGGER historico_sem_truncate
  BEFORE TRUNCATE ON historico_status_encaminhamento FOR EACH STATEMENT EXECUTE FUNCTION bloqueia_alteracao();

CREATE TRIGGER encaminhamento_valida
  BEFORE INSERT OR UPDATE ON encaminhamento FOR EACH ROW EXECUTE FUNCTION encaminhamento_valida();
CREATE TRIGGER encaminhamento_apos_transicao
  AFTER INSERT OR UPDATE OF status ON encaminhamento FOR EACH ROW EXECUTE FUNCTION encaminhamento_apos_transicao();
CREATE TRIGGER agendamento_marca_autor
  BEFORE INSERT OR UPDATE ON agendamento FOR EACH ROW EXECUTE FUNCTION agendamento_marca_autor();
CREATE TRIGGER contrarreferencia_t6
  AFTER INSERT ON contrarreferencia FOR EACH ROW EXECUTE FUNCTION contrarreferencia_t6();
CREATE TRIGGER anexo_valida_update
  BEFORE UPDATE ON anexo_encaminhamento FOR EACH ROW EXECUTE FUNCTION anexo_valida_update();
CREATE TRIGGER link_valida_update
  BEFORE UPDATE ON link_paciente FOR EACH ROW EXECUTE FUNCTION link_valida_update();

-- =====================================================================
-- 15. Row-Level Security. ENABLE + FORCE em toda tabela com dado. Sem politica = nega.
--     Nenhuma politica testa app.papel sozinho: todo ator passa por sessao valida.
-- =====================================================================
DO $$ DECLARE t text; BEGIN
  FOR t IN SELECT tablename FROM pg_tables WHERE schemaname = 'saas' AND tablename <> 'especialidade' LOOP
    EXECUTE format('ALTER TABLE saas.%I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format('ALTER TABLE saas.%I FORCE ROW LEVEL SECURITY', t);
  END LOOP;
END $$;
-- especialidade: catalogo publico sem dado pessoal; sem RLS, so SELECT.
-- sessao, link_paciente, desafio_encaminhador, envio_notificacao: RLS sem politica e sem
-- GRANT a papel de login. Acesso so pelas funcoes das secoes 12 e 13.

-- ---- identidade --------------------------------------------------------
CREATE POLICY usuario_proprio ON usuario FOR SELECT USING (id = ator_usuario());
CREATE POLICY usuario_admin_da_clinica ON usuario FOR SELECT
  USING (eh_equipe(ARRAY['ADMIN'])
         AND EXISTS (SELECT 1 FROM usuario_clinica uc WHERE uc.usuario_id = usuario.id AND uc.clinica_id = app_clinica_id()));
CREATE POLICY usuario_clinica_ver ON usuario_clinica FOR SELECT
  USING (usuario_id = ator_usuario() OR (clinica_id = app_clinica_id() AND eh_equipe(ARRAY['ADMIN'])));

-- ---- clinicas ----------------------------------------------------------
CREATE POLICY clinica_equipe ON clinica FOR SELECT
  USING (id = app_clinica_id() AND eh_equipe(ARRAY['ADMIN','RECEPCAO','MEDICO']));
CREATE POLICY clinica_admin_altera ON clinica FOR UPDATE
  USING (id = app_clinica_id() AND eh_equipe(ARRAY['ADMIN'])) WITH CHECK (id = app_clinica_id());
-- Sem politica de catalogo: rede ve clinicas so por catalogo_rede() (Red Team, item 17).

CREATE POLICY clinica_especialidade_ver ON clinica_especialidade FOR SELECT
  USING (clinica_id = app_clinica_id() AND eh_equipe(ARRAY['ADMIN','RECEPCAO','MEDICO']));
CREATE POLICY clinica_especialidade_admin ON clinica_especialidade FOR INSERT
  WITH CHECK (clinica_id = app_clinica_id() AND eh_equipe(ARRAY['ADMIN']));

CREATE POLICY flag_clinica_ver ON flag_clinica FOR SELECT
  USING (clinica_id = app_clinica_id() AND eh_equipe(ARRAY['ADMIN','RECEPCAO','MEDICO']));

-- Nome e CRM sao publicos [SUPOSICAO: consulta publica do CFM]; telefone e e-mail sem GRANT.
CREATE POLICY profissional_ver ON profissional FOR SELECT USING (ator_tipo() IS NOT NULL);
CREATE POLICY profissional_cadastra ON profissional FOR INSERT WITH CHECK (eh_equipe(ARRAY['ADMIN']));
CREATE POLICY profissional_especialidade_ver ON profissional_especialidade FOR SELECT USING (ator_tipo() IS NOT NULL);

CREATE POLICY profissional_clinica_equipe ON profissional_clinica FOR ALL
  USING (clinica_id = app_clinica_id() AND eh_equipe(ARRAY['ADMIN','RECEPCAO','MEDICO']))
  WITH CHECK (clinica_id = app_clinica_id() AND eh_equipe(ARRAY['ADMIN']));

-- ---- agenda ------------------------------------------------------------
CREATE POLICY horario_equipe ON horario_atendimento FOR ALL
  USING (clinica_id = app_clinica_id() AND eh_equipe(ARRAY['ADMIN','RECEPCAO','MEDICO']))
  WITH CHECK (clinica_id = app_clinica_id() AND eh_equipe(ARRAY['ADMIN','RECEPCAO']));

CREATE POLICY agendamento_equipe_ver ON agendamento FOR SELECT
  USING (clinica_id = app_clinica_id() AND eh_equipe(ARRAY['ADMIN','RECEPCAO','MEDICO']));
-- Agendamento de encaminhamento so nasce por destino_confirma_horario (T4).
CREATE POLICY agendamento_equipe_cria ON agendamento FOR INSERT
  WITH CHECK (clinica_id = app_clinica_id() AND eh_equipe(ARRAY['ADMIN','RECEPCAO','MEDICO']) AND encaminhamento_id IS NULL);
CREATE POLICY agendamento_equipe_altera ON agendamento FOR UPDATE
  USING (clinica_id = app_clinica_id() AND eh_equipe(ARRAY['ADMIN','RECEPCAO','MEDICO']))
  WITH CHECK (clinica_id = app_clinica_id() AND eh_equipe(ARRAY['ADMIN','RECEPCAO','MEDICO']));
CREATE POLICY agendamento_paciente_ver ON agendamento FOR SELECT
  USING (paciente_id = ator_paciente() AND encaminhamento_id = ator_encaminhamento());   -- r2-5
-- Sem INSERT por paciente ate a Fase 6 (ADR-0031; Red Team, item 15).

CREATE POLICY vaga_equipe ON vaga_encaminhamento FOR ALL
  USING (clinica_id = app_clinica_id() AND eh_equipe(ARRAY['ADMIN','RECEPCAO','MEDICO']))
  WITH CHECK (clinica_id = app_clinica_id() AND eh_equipe(ARRAY['ADMIN','RECEPCAO']));

-- ---- pacientes ---------------------------------------------------------
CREATE POLICY paciente_proprio ON paciente FOR SELECT USING (id = ator_paciente());
-- Vinculo nascido de encaminhamento so vale enquanto o consentimento estiver ativo (I-03).
CREATE POLICY paciente_da_clinica ON paciente FOR SELECT
  USING (eh_equipe(ARRAY['ADMIN','RECEPCAO','MEDICO'])
         AND EXISTS (SELECT 1 FROM paciente_clinica pc
                      WHERE pc.paciente_id = paciente.id AND pc.clinica_id = app_clinica_id()
                        AND (pc.encaminhamento_id IS NULL OR consentimento_ativo(pc.encaminhamento_id, pc.clinica_id))));
CREATE POLICY paciente_via_encaminhamento ON paciente FOR SELECT
  USING (EXISTS (SELECT 1 FROM encaminhamento e WHERE e.paciente_id = paciente.id));
-- Alteracao de cadastro (sem telefone): so a clinica que cadastrou.
CREATE POLICY paciente_altera ON paciente FOR UPDATE
  USING (eh_equipe(ARRAY['ADMIN','RECEPCAO']) AND cadastrado_por_clinica_id = app_clinica_id())
  WITH CHECK (cadastrado_por_clinica_id = app_clinica_id());

CREATE POLICY paciente_clinica_ver ON paciente_clinica FOR SELECT
  USING (clinica_id = app_clinica_id() AND eh_equipe(ARRAY['ADMIN','RECEPCAO','MEDICO']));

-- ---- encaminhamentos ---------------------------------------------------
CREATE POLICY encaminhamento_origem ON encaminhamento FOR SELECT
  USING (profissional_origem_id = ator_profissional());
CREATE POLICY encaminhamento_paciente ON encaminhamento FOR SELECT
  USING (paciente_id = ator_paciente() AND id = ator_encaminhamento());   -- r2-5: so o caso do link
CREATE POLICY encaminhamento_destino ON encaminhamento FOR SELECT
  USING (clinica_destino_id = app_clinica_id()
         AND eh_equipe(ARRAY['ADMIN','RECEPCAO','MEDICO'])
         AND EXISTS (SELECT 1 FROM consentimento c
                      WHERE c.encaminhamento_id = encaminhamento.id
                        AND c.clinica_id = encaminhamento.clinica_destino_id
                        AND c.finalidade = 'COMPARTILHAR_CASO' AND c.revogado_em IS NULL));
-- UPDATE direto: so colunas status e urgencia (GRANT por coluna); o gatilho decide o par e o ator.
CREATE POLICY encaminhamento_origem_altera ON encaminhamento FOR UPDATE
  USING (profissional_origem_id = ator_profissional()) WITH CHECK (profissional_origem_id = ator_profissional());
CREATE POLICY encaminhamento_paciente_altera ON encaminhamento FOR UPDATE
  USING (paciente_id = ator_paciente() AND id = ator_encaminhamento())
  WITH CHECK (paciente_id = ator_paciente() AND id = ator_encaminhamento());
CREATE POLICY encaminhamento_destino_altera ON encaminhamento FOR UPDATE
  USING (clinica_destino_id = app_clinica_id() AND consentimento_ativo(id, clinica_destino_id))
  WITH CHECK (clinica_destino_id = app_clinica_id());
-- Sem INSERT direto: so encaminhamento_cria (T1).

CREATE POLICY historico_ver ON historico_status_encaminhamento FOR SELECT
  USING (EXISTS (SELECT 1 FROM encaminhamento e WHERE e.id = encaminhamento_id));
-- Sem INSERT: so o gatilho grava (Red Team, item 12).

CREATE POLICY contrarreferencia_ver ON contrarreferencia FOR SELECT
  USING (EXISTS (SELECT 1 FROM encaminhamento e WHERE e.id = encaminhamento_id));
CREATE POLICY contrarreferencia_medico_destino ON contrarreferencia FOR INSERT
  WITH CHECK (clinica_id = app_clinica_id()
              AND autor_profissional_id = ator_profissional()
              AND pode_contrarreferenciar(encaminhamento_id));

CREATE POLICY anexo_ver ON anexo_encaminhamento FOR SELECT
  USING (EXISTS (SELECT 1 FROM encaminhamento e WHERE e.id = encaminhamento_id));
CREATE POLICY anexo_inclui ON anexo_encaminhamento FOR INSERT
  WITH CHECK (EXISTS (SELECT 1 FROM encaminhamento e
                       WHERE e.id = encaminhamento_id
                         AND e.status NOT IN ('CONTRARREFERIDO','EXPIRADO','CANCELADO')
                         AND ((e.profissional_origem_id = ator_profissional()
                               AND enviado_por_tipo = 'PROFISSIONAL' AND enviado_por_id = ator_profissional())
                           OR (e.paciente_id = ator_paciente() AND e.id = ator_encaminhamento()   -- r2-5
                               AND enviado_por_tipo = 'PACIENTE' AND enviado_por_id = ator_paciente()))));
-- Sem UPDATE pelo papel web; varredura so por jobs_anexo_varredura.

CREATE POLICY consentimento_paciente ON consentimento FOR SELECT
  USING (paciente_id = ator_paciente() AND encaminhamento_id = ator_encaminhamento());   -- r2-5
CREATE POLICY consentimento_clinica ON consentimento FOR SELECT
  USING (clinica_id = app_clinica_id() AND eh_equipe(ARRAY['ADMIN','RECEPCAO','MEDICO']));
-- Paciente concede para si; FKs compostas garantem encaminhamento dele e clinica destino.
CREATE POLICY consentimento_paciente_concede ON consentimento FOR INSERT
  WITH CHECK (paciente_id = ator_paciente() AND encaminhamento_id = ator_encaminhamento()   -- r2-5
              AND revogado_em IS NULL AND canal IN ('SITE','WHATSAPP'));
-- Recepcao registra so para paciente vinculado a propria clinica (T-14).
CREATE POLICY consentimento_recepcao_registra ON consentimento FOR INSERT
  WITH CHECK (eh_equipe(ARRAY['ADMIN','RECEPCAO']) AND clinica_id = app_clinica_id()
              AND canal = 'RECEPCAO' AND finalidade <> 'COMPARTILHAR_CASO' AND revogado_em IS NULL
              AND EXISTS (SELECT 1 FROM paciente_clinica pc
                           WHERE pc.paciente_id = consentimento.paciente_id AND pc.clinica_id = app_clinica_id()));
CREATE POLICY consentimento_paciente_revoga ON consentimento FOR UPDATE
  USING (paciente_id = ator_paciente() AND encaminhamento_id = ator_encaminhamento() AND revogado_em IS NULL)
  WITH CHECK (paciente_id = ator_paciente() AND encaminhamento_id = ator_encaminhamento() AND revogado_em IS NOT NULL);

-- ---- auditoria ---------------------------------------------------------
-- Ator conferido: papel e id iguais aos da sessao (Red Team, item 12; R-02).
CREATE POLICY auditoria_inclui ON evento_auditoria FOR INSERT
  WITH CHECK (ator_tipo() IS NOT NULL
              AND ator_papel = papel_efetivo()
              AND ator_id = ator_id_efetivo()
              AND (clinica_id IS NULL OR clinica_id = app_clinica_id()));
CREATE POLICY auditoria_admin_ve ON evento_auditoria FOR SELECT
  USING (clinica_id = app_clinica_id() AND eh_equipe(ARRAY['ADMIN']));


-- =====================================================================
-- 16. Privilegios dos papeis de login (por coluna onde ha escrita; Red Team, item 9)
-- =====================================================================
-- Concedidos pelo dono das tabelas.
GRANT SELECT ON especialidade TO saas_app;
GRANT SELECT ON usuario, usuario_clinica, flag_clinica, clinica_especialidade,
               profissional_especialidade, profissional_clinica, horario_atendimento,
               paciente_clinica, encaminhamento, historico_status_encaminhamento,
               consentimento, vaga_encaminhamento, agendamento, contrarreferencia,
               anexo_encaminhamento, evento_auditoria TO saas_app;
GRANT SELECT ON clinica TO saas_app;
GRANT UPDATE (nome, cnpj, modo_recebimento) ON clinica TO saas_app;
GRANT INSERT ON clinica_especialidade TO saas_app;
GRANT SELECT (id, crm, crm_uf, nome, canal_verificado_em, criado_em) ON profissional TO saas_app;
GRANT INSERT (crm, crm_uf, nome, telefone, email) ON profissional TO saas_app;
GRANT INSERT, UPDATE (duracao_consulta_min, recebe_encaminhamento, ativo) ON profissional_clinica TO saas_app;
GRANT INSERT, UPDATE (dia_semana, hora_inicio, hora_fim) ON horario_atendimento TO saas_app;
GRANT SELECT (id, nome, telefone, data_nascimento, cpf_cifrado, cadastrado_por_clinica_id, criado_em) ON paciente TO saas_app;
GRANT UPDATE (nome, data_nascimento) ON paciente TO saas_app;
GRANT UPDATE (status, urgencia) ON encaminhamento TO saas_app;
GRANT INSERT ON consentimento TO saas_app;
GRANT UPDATE (revogado_em) ON consentimento TO saas_app;
GRANT INSERT, UPDATE (inicio, fim, liberar_automaticamente_em, liberada_em) ON vaga_encaminhamento TO saas_app;
GRANT INSERT (clinica_id, profissional_clinica_id, paciente_id, inicio, fim, origem, vaga_encaminhamento_id, chave_idempotencia)
  ON agendamento TO saas_app;
GRANT UPDATE (status, inicio, fim, profissional_clinica_id, vaga_encaminhamento_id) ON agendamento TO saas_app;
GRANT INSERT (encaminhamento_id, clinica_id, autor_profissional_id, conduta_cifrada) ON contrarreferencia TO saas_app;
GRANT INSERT (encaminhamento_id, tipo_mime, tamanho_bytes, sha256, nome_original_cifrado, enviado_por_tipo, enviado_por_id)
  ON anexo_encaminhamento TO saas_app;
GRANT INSERT (ator_papel, ator_id, clinica_id, acao, recurso_tipo, recurso_id, ip_origem, canal) ON evento_auditoria TO saas_app;
-- Nenhum DELETE, TRUNCATE nem INSERT em paciente, paciente_clinica, encaminhamento,
-- historico, link_paciente, desafio_encaminhador, sessao ou envio_notificacao para saas_app.
-- saas_jobs e saas_auth: nenhum privilegio em tabela.

-- Concedidos pelo dono das funcoes.
SET ROLE saas_funcoes;

GRANT EXECUTE ON FUNCTION
  app_clinica_id(), app_papel(), ator_tipo(), ator_usuario(), ator_paciente(), ator_encaminhamento(), ator_profissional(),
  eh_equipe(text[]), papel_efetivo(), ator_id_efetivo(), rede_ligada(uuid),
  consentimento_ativo(uuid, uuid), pode_contrarreferenciar(uuid), transicao_cancelamento(encaminhamento),
  sessao_encerra(), link_consulta(text), paciente_pede_codigo(text), paciente_confirma_codigo(text, text),
  encaminhador_pede_codigo(text, text), encaminhador_cadastra(text, text, text, text, text),
  encaminhador_confirma_codigo(text, text),
  encaminhamento_cria(text, text, date, bytea, bytea, uuid, bytea, text),
  paciente_cadastra_na_clinica(text, text, date, bytea, bytea),
  paciente_troca_telefone_presencial(uuid, text), catalogo_rede(uuid),
  paciente_solicita(uuid, uuid, uuid, text, text),
  destino_confirma_horario(uuid, uuid, timestamptz, timestamptz, text)
TO saas_app;
GRANT EXECUTE ON FUNCTION
  jobs_envios_pendentes(int), jobs_envio_link_paciente(uuid), jobs_envio_prepara(uuid),
  jobs_envio_resultado(uuid, text, text), jobs_expirar_encaminhamentos(),
  jobs_consulta_realizada(uuid), jobs_agendamento_desfeito(uuid), jobs_anexo_varredura(uuid, text)
TO saas_jobs;
GRANT EXECUTE ON FUNCTION sessao_equipe_abre(text) TO saas_auth;

RESET ROLE;
