# Avaliador: t-fase1-arquitetura

Leitura feita em 2026-11-10 contra docs/briefing.md. Nada foi reescrito.

## Critérios

| # | Veredito | Prova e ressalvas |
|---|---|---|
| 1 | ATENDIDO | diff-v1-v2.md:7-20 (divergência e destino do link externo: não vira 4º modo, PEDIDO até a Fase 9), :24-45 (componentes v1), :49-59 (9 itens). Ressalva: item 9 sem tabela de envios (:59) |
| 2 | PARCIAL | modelo-dados-v2.md + modelo-v2.sql rodam no PG16 (evidencias/modelo-v2-execucao.log, exit 0); UUID, FORCE RLS, cifrados, auditoria só inclusão ok (sql:46-48, 397-412, 471-510). Lacunas: S1 e S2; paciente_clinica sem política para PACIENTE (sql:606) mas AgendaApi.agendar "garante PacienteClinica" no fluxo VAGAS e AGENDA_NATIVA (mapa-modulos.md:52, 67; máquina T4); S3 aberta (RLS permite qualquer par de status, sql:631-644) |
| 3 | PARCIAL | 8 módulos, API, eventos, dependências sem ciclo (mapa-modulos.md:126-139). Falta política SISTEMA para listeners (:173-175) e notificacoes não tem entidade (:99) |
| 4 | PARCIAL | 8 status, T1-T11, finais, expiração, histórico (maquina:5-72). T2, T5, T7 e T10/T11 em AGENDADO não executáveis no SQL atual (S1); sem validação de par (maquina:40) |
| 5 | ATENDIDO com ressalva | Três PNG e HTML existem. Arquitetura e ciclo de vida: finalize pass. ERD: recibos da raiz diagramas/erd-modelo-v2.finalize-summary.json e .finalize.json são do run que FALHOU (legibilidade); o pass está em diagramas/.review/erd-2/ e confere com o hash do HTML. Recibo da raiz está desatualizado e engana |
| 6 | PENDENTE | Red Team (docs/seguranca/ ainda sem stride) |
| 7 | PARCIAL | 22 ADRs com contexto, decisão, alternativas, consequências; 3 Propostos (0007, 0012, 0013), com opções. Falta ADR da linha "Proteção de dados" da tabela do briefing (criptografia no app, KMS, mascarar log, links assinados): só aparece diluído em 0010/0020. Faltam também ADR para D2/D7/D8 (papéis de banco, gatilho de histórico, text+CHECK), citados como decisões em diff-v1-v2.md:61-68 |
| 8 | ATENDIDO | glossario-adicoes.md:5-33; nomes do glossário preservados (profissional_origem_id, clinica_destino_id, modo_recebimento). Divergência D3 explícita (:37). Falta listar status de agendamento, canal, enviado_por_tipo, status de link |
| 9 | PENDENTE | Testador. Só há sanidade do Executor (evidencias/modelo-v2-sanidade.log) |
| 10 | ATENDIDO | regras-inegociaveis-check.md:9-40; sem coluna de benefício (grep documentado :5); retenção marcada como pergunta (sql:373). Ressalva: retenção do encaminhamento em si sem campo |
| 11 | ATENDIDO | Sem Java/React; grep por travessão e meia-risca em arquitetura/adr: vazio. Fontes ou [SUPOSIÇÃO] presentes |
| 12 | PENDENTE | docs/fase1-resumo.md ainda não existe |

## Inconsistências entre artefatos

- Erro real: AgendamentoCriado e EncaminhamentoAgendado são ambos consumidos por notificacoes (mapa:107-108, 150, 160) e T4 emite os dois. Risco de duas confirmações ao paciente. Definir qual vale quando origem = ENCAMINHAMENTO.
- Agendamento.status (AGENDADO, CONFIRMADO, REALIZADO, FALTOU, CANCELADO, sql:329) usa o mesmo vocabulário "AGENDADO" do status do encaminhamento e não está no glossário de adições.
- mapa-modulos.md:111 e modelo-dados-v2.md citam anexo no módulo arquivos; policies de anexo dependem de encaminhamento (sql:669). Aceitável, mas arquivos depende só de identidade; verificar na Fase 2 que a SPI cobre.
- Diagrama de arquitetura: setas de eventos da agenda vão só ao Registry e deste só a notificacoes. encaminhamentos consome agenda (mapa:96) e não aparece. clinicas, pacientes e auditoria quase sem arestas; "Monolito" dentro da caixa de nuvem esconde dependências (identidade só ligada a encaminhamentos).
- ERD: cumpre 21 tabelas, mas legível só ampliado (muitos cruzamentos de aresta). Lifecycle: coerente com T1-T11; T7 aparece como laço no topo, ok.
- Modelo: clinica_catalogo_rede (sql:535) expõe todas as clínicas, inclusive com flag desligada e cnpj, a ENCAMINHADOR e PACIENTE; "flag na aplicação" contradiz o princípio de duas barreiras. profissional telefone e e-mail legíveis a qualquer papel (já registrado).
- D3 (papel em usuario_clinica): aceito, mas nada amarra MEDICO em usuario_clinica a profissional_clinica; app.profissional_id não é conferido contra app.usuario no banco (eh_equipe só confere usuário/papel). Origem por MEDICO depende só do contexto montado pela aplicação.

## Complexidade desnecessária para dev solo

- Sete eventos sem consumidor, mas gravados no outbox (UsuarioVinculado/Desvinculado, FlagClinicaAlterada, ModoRecebimentoAlterado, ConsentimentoConcedido/Revogado, VagaEncaminhamentoLiberada, EncaminhamentoEnviadoAoPaciente, AnexoVarrido). Publicar só quando houver consumidor.
- Sete papéis de contexto de RLS (ENCAMINHADOR, PUBLICO_LINK, SISTEMA, PACIENTE, etc.) e cerca de 60 políticas; tendência a política por papel cada vez que surge um listener (S1). Alternativa: funções SECURITY DEFINER estreitas para SISTEMA.
- Evento CodigoPacienteSolicitado mais gerarCodigo mais notificacoes depender de encaminhamentos: caminho longo para um código; simplificar para chamada direta única.
- Vagas e modo AGENDA_NATIVA (Fase 6) já modelados em detalhe, políticas e T4 variantes; podem esperar.

## Sugestões do Executor

- S1: lacuna real e bloqueante da Fase 2 (listeners não conseguem executar T2, T5, T7, T9-T11 pelo banco). Acrescentar paciente_clinica por PACIENTE e a mudança de status por SISTEMA. Resolver antes de liberar o critério 9, senão o Testador prova isolamento num modelo que o fluxo não consegue usar.
- S2: lacuna real. Idempotência de envio é regra do briefing e ADR-0018 depende da tabela; uma tabela de envio (evento, destinatário id, canal, status, tentativas, chave), sem corpo.
- S3: lacuna real, a mais importante para segurança. Hoje a origem ou o destino podem gravar qualquer status (inclusive ATENDIDO ou CONTRARREFERIDO sem contrarreferência, ou sair de estado final). Gatilho de transições é barato e correto; mesmo um CHECK em gatilho com tabela de pares resolve. Red Team deve ver.

## Resumo

Fase 1 não pode fechar: 1, 5 (com ressalva), 8, 10, 11 atendidos; 2, 3, 4, 7 parciais; 6, 9, 12 pendentes. Próxima rodada: S1+S2+S3 no SQL, ADR de proteção de dados, limpar recibos do ERD, decidir evento duplicado de confirmação.
