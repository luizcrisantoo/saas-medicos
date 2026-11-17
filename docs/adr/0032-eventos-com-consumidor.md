# ADR-0032: Só publicar evento que tem consumidor; uma confirmação por agendamento

Status: Aceito na revisão da Fase 1 (rodada 1)
Data: 2026-11-10
Tarefa: t-fase1-arquitetura

## Contexto
O mapa de módulos da rodada 0 publicava no outbox eventos sem consumidor (UsuarioVinculado, UsuarioDesvinculado, FlagClinicaAlterada, ModoRecebimentoAlterado, ConsentimentoConcedido, ConsentimentoRevogado, VagaEncaminhamentoLiberada, EncaminhamentoEnviadoAoPaciente, AnexoVarrido, entre outros), e AgendamentoCriado mais EncaminhamentoAgendado geravam duas confirmações ao paciente (Avaliador).

## Decisão
- Evento só existe se tiver consumidor na fase em que é criado. Saem: UsuarioVinculado, UsuarioDesvinculado, FlagClinicaAlterada, ModoRecebimentoAlterado, ConsentimentoConcedido, ConsentimentoRevogado, VagaEncaminhamentoLiberada, EncaminhamentoEnviadoAoPaciente, EncaminhamentoSolicitado, EncaminhamentoAtendido, EncaminhamentoCancelado, AnexoVarrido e CodigoPacienteSolicitado (o pedido de código vira linha de `envio_notificacao`, ADR-0034).
- Ficam os três do briefing (AgendamentoCriado, ConsultaRealizada, EncaminhamentoAgendado) e os que têm consumidor: AgendamentoConfirmado, AgendamentoCancelado, PacienteFaltou, EncaminhamentoCriado, EncaminhamentoContrarreferido, EncaminhamentoExpirado, AnexoRecebido.
- Confirmação única: `notificacoes` ignora AgendamentoCriado com `origem = ENCAMINHAMENTO`; para esse caso a confirmação ao paciente e o aviso à origem saem de EncaminhamentoAgendado.
- Métricas (taxa de chegada) vêm de consulta ao status e ao histórico, não de evento.

## Alternativas descartadas
- Publicar "para o futuro": cada evento grava o payload no outbox e precisa de limpeza (ADR-0020) sem ninguém ler.

## Consequências
- Evento novo entra junto com o seu consumidor e o teste de fronteira do Spring Modulith.

## Fontes
- docs/agents/avaliador-t-fase1-arquitetura.md (inconsistências e complexidade); docs/arquitetura/mapa-modulos.md, seção 4
