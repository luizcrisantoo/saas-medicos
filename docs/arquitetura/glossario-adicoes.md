# Glossário: adições da Fase 1

Tarefa: t-fase1-arquitetura, critério 8. Regra do briefing: "Os mesmos nomes valem no código, no banco, na tela e nas conversas com os agentes. Termo novo entra aqui antes de entrar no código." (docs/briefing.md, Glossário). Estes termos precisam ser levados ao glossário do briefing pelo Orquestrador.

## Regra de grafia no banco

| No briefing (código) | No banco | Exemplo |
|---|---|---|
| Entidade em PascalCase | Tabela em snake_case, singular | `ProfissionalClinica` = `profissional_clinica` |
| Campo em camelCase | Coluna em snake_case; referência a outra entidade ganha `_id` | `profissionalOrigem` = `profissional_origem_id`; `clinicaDestino` = `clinica_destino_id`; `profissionalDestino` = `profissional_destino_id`; `encaminhamentoId` = `encaminhamento_id` |
| tenant_id (Decisões de arquitetura) | `clinica_id` | O tenant é a Clínica (Glossário) |
| Valores de enumeração | MAIÚSCULAS, sem acento | `ModoRecebimento`: PEDIDO, VAGAS, AGENDA_NATIVA (literal do briefing) |

## Termos novos

| Termo | Significado | No código | No banco | Por que entrou |
|---|---|---|---|---|
| Usuário | Conta de equipe no provedor OIDC (admin, recepção, médico). Paciente não é Usuário | Usuario | `usuario` | Recepção não tem CRM, então não é Profissional; papéis por clínica precisam de uma pessoa autenticada (briefing, Mudanças 5) |
| Vínculo de usuário | Relação de um Usuário com uma Clínica e o papel nela | UsuarioClinica | `usuario_clinica` | Fonte única de papel por clínica (ver modelo-dados-v2.md, D3) |
| Papel | Função de acesso na clínica: ADMIN, RECEPCAO, MEDICO | Papel | `usuario_clinica.papel`, `app.papel` | briefing, Mudanças 5. Rodada 1: ENCAMINHADOR e PACIENTE viram tipos de sessão; PUBLICO_LINK e SISTEMA deixam de ser papel de contexto |
| Vínculo de paciente | Relação do Paciente global com uma Clínica onde é atendido | PacienteClinica | `paciente_clinica` | briefing, Mudanças 1 pede pessoa global separada do vínculo; o briefing só nomeia o vínculo do profissional |
| Especialidade | Catálogo global de especialidades médicas | Especialidade | `especialidade` | Usada por Profissional, Clinica e "especialidade destino" do Encaminhamento (briefing, entidades) |
| Especialidade destino | Especialidade pedida no encaminhamento | especialidadeDestino | `especialidade_destino_id` | Campo listado no briefing ("especialidade destino") sem nome de código |
| Horário de atendimento | Dia da semana e faixa de horas em que um ProfissionalClinica atende; é a "agenda" do vínculo | HorarioAtendimento | `horario_atendimento` | briefing, Camada 1 ("cada clínica com seus médicos, dias e horários") e campo "agenda" de ProfissionalClinica |
| Histórico de status | Registro só de inclusão de cada mudança de status do Encaminhamento, com data e autor | HistoricoStatusEncaminhamento | `historico_status_encaminhamento` | briefing, Mudanças 3 |
| Status do encaminhamento | CRIADO, ENVIADO_AO_PACIENTE, SOLICITADO, AGENDADO, ATENDIDO, CONTRARREFERIDO, EXPIRADO, CANCELADO | StatusEncaminhamento | `encaminhamento.status` | Grafia dos 8 status do briefing (Mudanças 3) |
| Urgência | ROTINA, PRIORITARIA, URGENTE | Urgencia | `encaminhamento.urgencia` | Campo do briefing; os três valores são [SUPOSIÇÃO], validar com o Rodrigo |
| Origem do agendamento | SITE, WHATSAPP, RECEPCAO, ENCAMINHAMENTO | OrigemAgendamento | `agendamento.origem` | briefing, entidade Agendamento. Não confundir com Origem (glossário) = quem encaminhou |
| Finalidade do consentimento | AGENDAMENTO, COMPARTILHAR_CASO, COMUNICACAO_WHATSAPP | FinalidadeConsentimento | `consentimento.finalidade` | briefing, entidade Consentimento ("Finalidade"); valores são [SUPOSIÇÃO] a validar com o advogado |
| Link do paciente | Link de uso único e com expiração enviado ao paciente, mais o código de confirmação; guardado só como hash | LinkPaciente | `link_paciente` | briefing, Proteção de dados ("Links pro paciente assinados, de uso único, com expiração, e confirmação por código") |
| Telefone de contato do caso | Telefone informado por quem cria o Encaminhamento; link e código daquele caso vão a ele, não ao telefone do cadastro do Paciente | telefoneContato | `encaminhamento.telefone_contato` | Fase 2, F3: Red Team I-22 (ADR-0038) |
| Flag da clínica | Liga ou desliga uma funcionalidade da rede numa clínica; nasce desligada | FlagClinica | `flag_clinica` | briefing, Mudanças 8 |
| Status de varredura | PENDENTE, LIMPO, INFECTADO para anexo | StatusVarredura | `anexo_encaminhamento.status_varredura` | briefing, Decisões: Arquivos ("varredura de vírus") |
| Contexto da requisição | Variáveis locais à transação lidas pelas políticas: só `app.sessao`, `app.clinica_id` e `app.papel` (rodada 1) | (infra) | `set_config(..., true)` | briefing, Decisões: Multi-tenant (RLS); ADR-0023 |
| Sessão | Identidade verificável no banco de quem age: tipo EQUIPE, PACIENTE ou ENCAMINHADOR, guardada pelo hash do token, com validade | Sessao | `sessao` | Red Team, item 1; ADR-0023 |
| Tipo de sessão | EQUIPE, PACIENTE, ENCAMINHADOR | TipoSessao | `sessao.tipo` | ADR-0023 |
| Desafio do encaminhador | Pedido de código para o médico que encaminha provar posse do telefone cadastrado | DesafioEncaminhador | `desafio_encaminhador` | ADR-0025 |
| Envio de notificação | Registro de uma mensagem a enviar ou enviada, sem o texto | EnvioNotificacao | `envio_notificacao` | ADR-0034; sugestão S2 |
| Finalidade do envio | LINK_PACIENTE, CODIGO_PACIENTE, CODIGO_ENCAMINHADOR, CONFIRMACAO_AGENDAMENTO, AVISO_ORIGEM, LEMBRETE | FinalidadeEnvio | `envio_notificacao.finalidade` | ADR-0034 |
| Status do envio | PENDENTE, PREPARADO, ACEITO, ENTREGUE, FALHOU | StatusEnvio | `envio_notificacao.status` | ADR-0034 |
| Canal | WHATSAPP, SMS, EMAIL (envio); WHATSAPP, SITE, RECEPCAO (consentimento) | Canal | `envio_notificacao.canal`, `consentimento.canal` | Avaliador, critério 8 |
| Status do agendamento | AGENDADO, CONFIRMADO, REALIZADO, FALTOU, CANCELADO. Não confundir com o status AGENDADO do encaminhamento | StatusAgendamento | `agendamento.status` | Avaliador, inconsistências |
| Enviado por (tipo) | PROFISSIONAL, PACIENTE: quem subiu o anexo | EnviadoPorTipo | `anexo_encaminhamento.enviado_por_tipo` | Avaliador, critério 8 |
| Estado do link | Válido, usado (`usado_em`), revogado (`revogado_em`) ou vencido (`expira_em`); derivado das colunas, sem enumeração | (derivado) | `link_paciente` | Avaliador, critério 8 |
| Transição | Identificador T1 a T11 da tabela da máquina de estados | Transicao | `historico_status_encaminhamento.transicao` | ADR-0027 |
| Ator técnico e autor de negócio | Ator técnico: papel de banco que gravou (saas_app, saas_jobs). Autor de negócio: pessoa que causou a mudança na agenda (T5, T7) | (campos) | `historico_status_encaminhamento.ator_tecnico`, `autor_negocio_id` | Red Team, item 12 |
| Papel de banco | saas_owner, saas_funcoes, saas_app, saas_jobs, saas_auth | (infra) | papéis do PostgreSQL | ADR-0024 |
| Rede ligada | Flag REDE_ENCAMINHAMENTO da clínica, conferida no banco | (infra) | `flag_clinica`, `rede_ligada()` | Red Team, item 15 |

## Divergência registrada

- `papel` aparece no briefing como campo de ProfissionalClinica. No v2 ele mora em `usuario_clinica` (D3 em modelo-dados-v2.md). Pendente de aceite do Avaliador; se recusado, volta para `profissional_clinica` e a recepção precisa de outro vínculo.
