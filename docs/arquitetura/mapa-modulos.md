# Mapa de módulos v2 (Spring Modulith), revisão r2

Tarefa: t-fase1-arquitetura, critério 3. Fonte da verdade: `docs/briefing.md` (Mudanças 4, 5, 6, 7, 8 e 9; Decisões de arquitetura). Entidades: `docs/arquitetura/modelo-dados-v2.md` e `modelo-v2.sql`. Rodada 1: eventos sem consumidor cortados (ADR-0032), sessão verificável no banco (ADR-0023), jobs com papel próprio e funções estreitas (ADR-0024), `notificacoes` ganha `envio_notificacao` (ADR-0034). Comportamento do Spring Modulith: `docs/agents/pesquisador-t-fase1-arquitetura.md`, seção Spring Modulith (doc de verificação e doc de eventos, versão 2.1.1).

Rodada 2: nenhum módulo, dependência ou evento novo. Mudam contratos de `identidade` (sessão de paciente com escopo de caso; usuário inativo derruba a sessão), `pacientes` (critério de identidade, ADR-0036), `agenda` (status finais) e `encaminhamentos`/`notificacoes` (link e envio só com encaminhamento aberto). Regra transversal nova: token só por parâmetro ligado (ADR-0026, item 7).

Diagrama: `docs/arquitetura/diagramas/arquitetura-v2.html` (e `.png`).

## 1. Regras do mapa

| Regra | Como vale | Fonte |
|---|---|---|
| Um projeto Spring, 8 módulos | Um pacote de primeiro nível por módulo: `identidade`, `clinicas`, `agenda`, `pacientes`, `encaminhamentos`, `notificacoes`, `arquivos`, `auditoria` | briefing, Mudanças 6 |
| Só a API pública atravessa a fronteira | Cada módulo expõe um pacote de API (interfaces, comandos, consultas e tipos de evento); o resto é interno | Pesquisador: `ApplicationModules.of(...).verify()` rejeita acesso a tipo interno |
| Dependências declaradas | `@ApplicationModule(allowedDependencies = ...)` com a lista da seção 3; o teste `verify()` falha se aparecer outra | Pesquisador: doc de verificação |
| Sem ciclos | Grafo da seção 3 em ordem topológica; ouvir o evento de outro módulo conta como dependência dele | Pesquisador: `verify()` checa ausência de ciclos. [SUPOSIÇÃO: o Modulith conta o tipo do evento consumido como dependência do módulo que o publica, porque o listener referencia esse tipo] |
| Reação por evento, não chamada direta, quando a rede reage à agenda | `encaminhamentos` ouve `ConsultaRealizada`, `AgendamentoCancelado` e `PacienteFaltou`; a agenda nunca importa nada de `encaminhamentos` | briefing, Mudanças 7 |
| Outbox | Todo evento entre módulos é publicado na transação do negócio e entregue por `@ApplicationModuleListener`; o Event Publication Registry grava uma entrada por listener e só a marca concluída quando o listener termina; pendentes são reenviadas no reinício (`spring.modulith.events.republish-outstanding-events-on-restart=true`) | briefing, Decisões: Eventos; Pesquisador: doc de eventos |
| Payload só com ids | Evento carrega UUIDs, enumerações e o instante do fato. Nunca nome, telefone, CPF, motivo, conduta, nome de arquivo, token de link ou código de uso único | modelo-dados-v2.md, D6; Pesquisador: o registro grava o evento inteiro serializado e mantém entradas concluídas até limpeza |
| Envio de mensagem só em `notificacoes` | Nenhum outro módulo chama WhatsApp, SMS ou e-mail; pedem envio publicando evento | briefing, Mudanças 4 |
| Funcionalidade da rede atrás de flag | `encaminhamentos` e `notificacoes` consultam `clinicas.FlagsApi` antes de agir para uma clínica | briefing, Mudanças 8 |
| Segredo nunca em evento | Token do link e códigos são gerados na hora do envio por `jobs_envio_prepara` (papel `saas_jobs`) e só o hash é gravado | ADR-0020, ADR-0030 |
| Só evento com consumidor | Evento sem consumidor na fase não é publicado | ADR-0032 |
| Banco só por sessão ou função | A web age com a sessão da requisição; jobs e listeners só chamam funções `jobs_*` | ADR-0023, ADR-0024 |

Limpeza do registro: modo de conclusão e rotina de remoção das entradas concluídas ficam para a Fase 2 [SUPOSIÇÃO: modo DELETE ou ARCHIVE com limpeza diária; o doc lista UPDATE, DELETE e ARCHIVE e diz que entradas concluídas "precisam ser limpas periodicamente"].

## 2. Os 8 módulos

### identidade
- Possui: `Usuario` (`usuario`), `UsuarioClinica` (`usuario_clinica`, com `papel` ADMIN, RECEPCAO, MEDICO), `Sessao` (`sessao`).
- API pública:
  - `ContextoAcesso atual()`: tipo de sessão (EQUIPE, PACIENTE, ENCAMINHADOR), clínica e papel escolhidos, a partir do cookie de sessão.
  - `ContextoBanco.aplicar(ContextoAcesso)`: grava só `app.sessao` (token do cookie), `app.clinica_id` e `app.papel` com `set_config(..., true)`. Quem é o ator, o banco descobre pela tabela `sessao` (ADR-0023).
  - `SessaoApi`: `abrirEquipe(subOidc)` (só o componente de login, papel `saas_auth`), `encerrar()`. Sessões de paciente e de encaminhador nascem dentro das funções de banco de `encaminhamentos` e `clinicas` que conferem a prova (código), na mesma transação; nenhum módulo abre sessão sem prova. Contrato da rodada 2: a sessão de paciente carrega o caso do link (`ator_encaminhamento()`) e toda consulta de paciente em `encaminhamentos`, `agenda`, `pacientes` (consentimento) e `arquivos` filtra por esse caso; sessão de equipe de usuário desativado deixa de valer na hora.
  - Regra para todo módulo (ADR-0026, item 7): o token da sessão entra na transação só como parâmetro ligado em `set_config('app.sessao', ?, true)`, nunca concatenado no SQL.
  - `ServicoAutorizacao.exigir(acao, recurso)`: único ponto de decisão de acesso; nega por padrão (briefing, Decisões: Autorização).
  - SPI `PoliticaRelacionamento`: interface que outro módulo implementa para regras por relacionamento (a de Encaminhamento fica em `encaminhamentos`, que depende de `identidade`, e não o contrário).
  - `EquipeApi`: vincular usuário a clínica e mudar papel (só ADMIN).
- Depende de: `auditoria`.
- Publica: nenhum (UsuarioVinculado e UsuarioDesvinculado cortados, sem consumidor; ADR-0032).
- Consome: nenhum.

### clinicas
- Possui: `Clinica` (`clinica`, com `modo_recebimento`), `ClinicaEspecialidade`, `Especialidade` (catálogo global), `Profissional` (global), `ProfissionalEspecialidade`, `ProfissionalClinica`, `FlagClinica` (`flag_clinica`, nasce `ligada = false`), `DesafioEncaminhador` (`desafio_encaminhador`).
- API pública:
  - `CatalogoRedeApi`: clínicas com a flag REDE_ENCAMINHAMENTO ligada e a especialidade, sem `cnpj` nem contato (função `catalogo_rede`, exige sessão válida).
  - `ClinicaApi.modoRecebimento(clinicaId)`.
  - `ProfissionalApi`: cadastrar profissional da própria clínica (ADMIN); `pedirCodigoEncaminhador(crm, uf)`, `cadastrarEncaminhador(...)` e `confirmarEncaminhador(desafio, codigo)` para quem encaminha sem conta (ADR-0025). O cadastro nasce sem sessão até confirmar o código.
  - `FlagsApi.ligada(clinicaId, chave)` e `FlagsApi.alterar(...)` (só operação ou ADMIN).
- Depende de: `identidade`, `auditoria`.
- Publica: nenhum (FlagClinicaAlterada e ModoRecebimentoAlterado cortados; ADR-0032).
- Consome: nenhum.

### pacientes
- Possui: `Paciente` (global, `cpf_cifrado`, `cpf_hash` sem UNIQUE), `PacienteClinica`, `Consentimento`.
- API pública:
  - `PacienteApi.cadastrarNaClinica(...)` (função `paciente_cadastra_na_clinica`; deduplicação só entre pacientes da clínica, ADR-0029; critério do ADR-0036: CPF igual, ou nome normalizado + nascimento + telefone; telefone sozinho nunca identifica), `trocarTelefonePresencial(...)`.
  - O vínculo de encaminhamento nasce dentro de `EncaminhamentoApi.confirmarHorario` (função `destino_confirma_horario`); `garantirVinculo` com UUID vindo do cliente não existe mais (Red Team, item 6).
  - O contato do paciente para envio sai só por `jobs_envio_prepara`, um envio por vez (Red Team, item 18).
  - `ConsentimentoApi.conceder(...)`, `revogar(...)`, `vigente(pacienteId, finalidade, encaminhamentoId, clinicaId)`.
- Depende de: `identidade`, `auditoria`.
- Publica: nenhum (ConsentimentoConcedido e ConsentimentoRevogado cortados; ADR-0032).
- Consome: nenhum. A revogação de `COMPARTILHAR_CASO` já tira a visibilidade da clínica destino pela RLS (política `encaminhamento_destino`), sem precisar de listener.

### agenda
- Possui: `HorarioAtendimento`, `Agendamento` (com `origem`, `encaminhamento_id` opcional e `status_alterado_por` preenchido pela sessão), `VagaEncaminhamento` (só forma até a Fase 6, ADR-0031).
- API pública:
  - `AgendaApi.horariosLivres(profissionalClinicaId, periodo)`: só horários (vagas para o paciente na Fase 6).
  - `AgendaApi.agendar(comando)` com `chaveIdempotencia` e `origem` (sem encaminhamento: o agendamento de encaminhamento nasce em `destino_confirma_horario`, para não haver dois caminhos).
  - `AgendaApi.cancelar(agendamentoId, motivoCodigo)`, `confirmar(...)`, `registrarRealizada(...)`, `registrarFalta(...)`. Rodada 2: REALIZADO, FALTOU e CANCELADO são finais e CONFIRMADO não volta a AGENDADO (gatilho no banco); "reabrir" é agendamento novo.
  - `AgendaApi.agendamentoAtivoDoEncaminhamento(encaminhamentoId)`.
  - `VagasApi`: Fase 6 (ADR-0031).
- Depende de: `clinicas`, `pacientes`, `identidade`, `auditoria`.
- Publica:
  - `AgendamentoCriado {agendamentoId, clinicaId, pacienteId, profissionalClinicaId, origem, encaminhamentoId?, autorId}` (briefing, Mudanças 7)
  - `AgendamentoConfirmado {agendamentoId, clinicaId, autorId}`
  - `AgendamentoCancelado {agendamentoId, clinicaId, encaminhamentoId?, vagaEncaminhamentoId?, autorId}`
  - `ConsultaRealizada {agendamentoId, clinicaId, encaminhamentoId?, autorId}` (briefing, Mudanças 7)
  - `PacienteFaltou {agendamentoId, clinicaId, encaminhamentoId?, autorId}`
- Consome: nenhum. A agenda é o núcleo e não conhece a rede (briefing: "A rede reage a eventos da agenda").

### encaminhamentos
- Possui: `Encaminhamento`, `HistoricoStatusEncaminhamento` (só gatilho grava), `Contrarreferencia`, `LinkPaciente`.
- API pública:
  - `EncaminhamentoApi.criar(...)` (T1, `encaminhamento_cria`: paciente nunca por UUID do cliente), `cancelar(...)` (T9, T10, T11), `escolherDestino(...)` (T3, `paciente_solicita`), `confirmarHorario(...)` (T4, `destino_confirma_horario`), `registrarContrarreferencia(...)` (T6).
  - `LinkPacienteApi.consultar(token)` (GET, não consome), `pedirCodigo(token)`, `confirmarCodigo(token, codigo)` (abre sessão de paciente do caso daquele link). Rodada 2: as três recusam link de encaminhamento CANCELADO, EXPIRADO ou CONTRARREFERIDO, e a entrada nesses estados revoga o link e derruba envio pendente. Emissão do link e geração do código ficam em `jobs_envio_prepara`, chamado por `notificacoes`.
  - `PoliticaEncaminhamento` implementa a SPI `PoliticaRelacionamento` de `identidade`: visível só para origem, clínica destino (com consentimento `COMPARTILHAR_CASO` ativo) e paciente (briefing, Mudanças 5; modelo-dados-v2.md, D5).
  - `MetricasRedeApi`: contagens por clínica destino para o painel (taxa de chegada), sem dado pessoal.
  - Job de expiração (`jobs_expirar_encaminhamentos`, papel `saas_jobs`).
- Depende de: `agenda`, `pacientes`, `clinicas`, `arquivos`, `identidade`, `auditoria`.
- Publica (só ids, só com consumidor):
  - `EncaminhamentoCriado {encaminhamentoId}`
  - `EncaminhamentoAgendado {encaminhamentoId, agendamentoId, clinicaDestinoId}` (briefing, Mudanças 7)
  - `EncaminhamentoContrarreferido {encaminhamentoId, contrarreferenciaId}`
  - `EncaminhamentoExpirado {encaminhamentoId}`
- Consome (de `agenda`): `ConsultaRealizada` (T5, `jobs_consulta_realizada`), `AgendamentoCancelado` e `PacienteFaltou` (T7, `jobs_agendamento_desfeito`). Cada listener passa só o `agendamentoId`; a função relê agendamento e encaminhamento e é idempotente.

### notificacoes
- Possui: templates (código, sem tabela) e `EnvioNotificacao` (`envio_notificacao`: finalidade, canal, destinatário por id, chave de idempotência, status, tentativas; sem corpo, ADR-0034).
- API pública: nenhuma API de envio para outros módulos (envio só por evento, briefing Mudanças 4). Entrada HTTP: webhook do WhatsApp com assinatura validada (briefing, Segurança da aplicação). `StatusEntregaApi` para o painel da recepção [SUPOSIÇÃO].
- Canais: WhatsApp Business Cloud API (principal); SMS e e-mail como plano B para os avisos críticos (confirmação e link de encaminhamento) quando o WhatsApp falhar ou o número for bloqueado (briefing, Mudanças 9).
- Corpo de mensagem: só texto de template sem dado clínico mais link autenticado com expiração (briefing, Regras inegociáveis, Segurança).
- Idempotência: `envio_notificacao.chave_idempotencia` única (ex.: `LINK:<encaminhamento>:<n>`), para reentrega do outbox não mandar a mesma mensagem duas vezes (briefing, Segurança da aplicação).
- Fluxo do worker (papel `saas_jobs`): `jobs_envios_pendentes` lista ids; `jobs_envio_prepara(envio)` devolve canal, contato daquele destinatário e segredo gerado agora; o worker chama o provedor; `jobs_envio_resultado` grava o status e faz T2 quando o link é aceito.
- Mensagem de entrada nunca autentica, consente nem muda status; webhook não grava corpo (ADR-0033).
- Depende de: `encaminhamentos`, `agenda` (horário para lembrete), `pacientes` (consentimento `COMUNICACAO_WHATSAPP`), `clinicas` (`FlagsApi`, nome da clínica), `identidade`, `auditoria`.
- Publica: nenhum evento consumido por outro módulo na Fase 1. Falha definitiva de entrega vira registro em `auditoria` e alerta [SUPOSIÇÃO].
- Consome:
  - de `agenda`: `AgendamentoCriado` (confirmação; ignorado quando `origem = ENCAMINHAMENTO`, para não duplicar com EncaminhamentoAgendado, ADR-0032), `AgendamentoConfirmado`, `AgendamentoCancelado` (aviso), mais lembretes [SUPOSIÇÃO: job interno lê `AgendaApi`].
  - de `encaminhamentos`: `EncaminhamentoCriado` (`jobs_envio_link_paciente`, que recusa origem não verificada), `EncaminhamentoAgendado` (a confirmação única ao paciente e aviso à origem), `EncaminhamentoContrarreferido` (aviso à origem, que entra pelo desafio do ADR-0025; a conduta nunca vai na mensagem), `EncaminhamentoExpirado` (aviso à origem).
  - Pedidos de código (paciente e encaminhador) chegam como linhas de `envio_notificacao`, não como evento.

### arquivos
- Possui: `AnexoEncaminhamento` (metadados; o arquivo fica em bucket privado criptografado, `chave_storage` opaca).
- API pública:
  - `ArquivosApi.autorizarUpload(encaminhamentoId, tipoMime, tamanho)`: valida tipo e tamanho e devolve URL assinada de upload.
  - `ArquivosApi.urlDownload(anexoId)`: só com `status_varredura = LIMPO`, URL assinada de poucos minutos, grava `EventoAuditoria` (briefing, Decisões: Arquivos).
  - Job de varredura de vírus (papel `saas_jobs`, função `jobs_anexo_varredura`: só PENDENTE para LIMPO ou INFECTADO). `chave_storage` é gerada pelo servidor e imutável.
- Depende de: `identidade` (a autorização do anexo passa por `ServicoAutorizacao`, que aplica a `PoliticaEncaminhamento` registrada), `auditoria`. Não depende de `encaminhamentos`.
- Publica: `AnexoRecebido {anexoId}`, consumido pelo próprio módulo (varredura). AnexoVarrido cortado (ADR-0032).
- Consome: o próprio `AnexoRecebido`.

### auditoria
- Possui: `EventoAuditoria` (só inclusão; gatilho barra UPDATE, DELETE e TRUNCATE).
- API pública: `AuditoriaApi.registrar(acao, recursoTipo, recursoId, clinicaId, ipOrigem, canal)` (o ator não é parâmetro: o banco confere papel e id contra a sessão, política `auditoria_inclui`), chamada síncrona na mesma transação do acesso, para que acesso sem registro não aconteça (briefing, Regras inegociáveis LGPD: "Todo acesso a dado de saúde fica registrado"). `AuditoriaApi.consultar(...)` só para ADMIN da própria clínica.
- Depende de: nenhum.
- Publica: nenhum. Consome: nenhum.

## 3. Dependências permitidas (sem ciclos)

| Módulo | `allowedDependencies` | Nível |
|---|---|---|
| auditoria | (nenhuma) | 0 |
| identidade | auditoria | 1 |
| clinicas | identidade, auditoria | 2 |
| pacientes | identidade, auditoria | 2 |
| arquivos | identidade, auditoria | 2 |
| agenda | clinicas, pacientes, identidade, auditoria | 3 |
| encaminhamentos | agenda, pacientes, clinicas, arquivos, identidade, auditoria | 4 |
| notificacoes | encaminhamentos, agenda, pacientes, clinicas, identidade, auditoria | 5 |

Prova de ausência de ciclo: cada módulo só depende de módulos de nível menor (ordem topológica acima). Toda seta "consome evento de X" da seção 2 aponta para um nível menor: `encaminhamentos` (4) consome de `agenda` (3); `notificacoes` (5) consome de `agenda` (3) e `encaminhamentos` (4); `arquivos` consome de si mesmo. Nenhum módulo de nível menor importa tipo de módulo de nível maior. O teste `ApplicationModules.of(Aplicacao.class).verify()` na Fase 2 transforma esta tabela em verificação automática (briefing, Testes que não podem faltar: "Teste das fronteiras de módulo pelo Spring Modulith").

Escolhas que evitam ciclo:
- `encaminhamentos` chama `AgendaApi.agendar` (dependência para baixo) e a agenda devolve o resultado por evento; a agenda nunca chama `encaminhamentos`.
- `notificacoes` chama `LinkPacienteApi` (para baixo); `encaminhamentos` nunca chama `notificacoes`, só publica evento.
- Autorização por relacionamento: `identidade` define a SPI, `encaminhamentos` implementa. `arquivos` pergunta a `identidade`, não a `encaminhamentos`.

## 4. Eventos: publicação e consumo

| Evento | Publica | Consome | Efeito no consumidor |
|---|---|---|---|
| AgendamentoCriado | agenda | notificacoes | Confirmação ao paciente (ignorado se `origem = ENCAMINHAMENTO`) |
| AgendamentoConfirmado | agenda | notificacoes | [SUPOSIÇÃO] aviso de confirmação de presença |
| AgendamentoCancelado | agenda | encaminhamentos, notificacoes | T7 se o encaminhamento estiver AGENDADO; aviso ao paciente |
| ConsultaRealizada | agenda | encaminhamentos | T5 |
| PacienteFaltou | agenda | encaminhamentos | T7 |
| EncaminhamentoCriado | encaminhamentos | notificacoes | Agenda o envio do link (`jobs_envio_link_paciente`) |
| EncaminhamentoAgendado | encaminhamentos | notificacoes | Confirmação única ao paciente e aviso à origem |
| EncaminhamentoContrarreferido | encaminhamentos | notificacoes | Aviso à origem |
| EncaminhamentoExpirado | encaminhamentos | notificacoes | Aviso à origem |
| AnexoRecebido | arquivos | arquivos | Varredura de vírus |

Cortados por não terem consumidor (ADR-0032): UsuarioVinculado, UsuarioDesvinculado, FlagClinicaAlterada, ModoRecebimentoAlterado, ConsentimentoConcedido, ConsentimentoRevogado, VagaEncaminhamentoLiberada, EncaminhamentoEnviadoAoPaciente, EncaminhamentoSolicitado, EncaminhamentoAtendido, EncaminhamentoCancelado, AnexoVarrido, CodigoPacienteSolicitado.

A taxa de chegada "desde o primeiro encaminhamento" (briefing, Fase 5) é calculada por consulta ao status e ao histórico, sem evento.

## 5. Contexto de execução dos listeners (sugestão S1 resolvida)

Listeners rodam fora da requisição (`@Async` + `REQUIRES_NEW`, Pesquisador) com a credencial do papel `saas_jobs`, que não tem privilégio em tabela nenhuma (ADR-0024). Cada ação de sistema é uma função estreita, revisada pelo Red Team, que relê o estado na fonte:

| Ação | Função | O que relê antes de agir |
|---|---|---|
| Agendar envio do link (EncaminhamentoCriado) | `jobs_envio_link_paciente(encaminhamento)` | Encaminhamento em CRIADO ou ENVIADO_AO_PACIENTE; origem verificada |
| Preparar um envio | `jobs_envio_prepara(envio)` | Envio PENDENTE; link ou desafio válido; r2: encaminhamento em CRIADO ou ENVIADO_AO_PACIENTE (link) ou aberto (código), senão marca FALHOU e não devolve segredo nem contato; devolve só o contato daquele destinatário |
| Resultado do provedor (T2) | `jobs_envio_resultado(envio, status, idProvedor)` | Envio preparado; T2 só se LINK aceito e encaminhamento em CRIADO |
| Expiração (T8) | `jobs_expirar_encaminhamentos()` | `expira_em < now()` e estado não final |
| ConsultaRealizada (T5) | `jobs_consulta_realizada(agendamento)` | Agendamento REALIZADO, mesma clínica destino, encaminhamento AGENDADO |
| AgendamentoCancelado, PacienteFaltou (T7) | `jobs_agendamento_desfeito(agendamento)` | Agendamento CANCELADO ou FALTOU, encaminhamento AGENDADO, nenhum outro agendamento ativo |
| Varredura de anexo | `jobs_anexo_varredura(anexo, resultado)` | Anexo PENDENTE |
| Fila de envio | `jobs_envios_pendentes(limite)` | Só ids, finalidade e canal |

O autor de negócio de T5 e T7 não vem do evento: o gatilho do histórico lê `agendamento.status_alterado_por`. Não existe política "SISTEMA vê tudo" (Red Team, item 18). Provas: seção jobs de `evidencias/teste-rls-r1.log` e `teste-rls-r2.log`; rodada 2: `evidencias/sondas-r2.log` (R2-1, R2-2) e J-link de `teste-r1-independente-r2.log`.
