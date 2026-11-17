# Arquify v1 x v2: o que mantém, muda, sai e entra

Tarefa: t-fase1-arquitetura, critério 1. Fonte da verdade: `docs/briefing.md` (rev 27, lido em 2026-11-10). Desenho v1: `docs/arquitetura/archify-v1-candidate.json` (e `archify-v1.png`). Modelo v2: `docs/arquitetura/modelo-dados-v2.md` e `modelo-v2.sql`.

Legenda: MANTÉM, MUDA, SAI (sai do escopo atual, com a fase em que volta, se volta), ENTRA.

## 1. A divergência central: agenda própria x link do sistema da clínica

| | v1 | Briefing | v2 (decisão) |
|---|---|---|---|
| Papel do produto | "camada de atendimento"; componente `marcacao` com sublabel "não cria agenda"; card "Os 3 caminhos": "Marcação: o SaaS entrega o link do sistema que a clínica já usa" (fonte: archify-v1-candidate.json) | "A agenda continua sendo o núcleo do produto"; "Camada 1: Agenda (o núcleo, MVP atual)"; linha do tempo Fase 3 "Agenda núcleo (MVP do Rodrigo)" (fonte: briefing) | A agenda própria entra como núcleo (módulo `agenda`, entidades Agendamento, HorarioAtendimento, VagaEncaminhamento). O briefing é a fonte da verdade. |
| Sistema de gestão externo (`sistema`, "agenda já existente") | Destino do fluxo de marcação | Camada 3: "Leitura de horários de clínicas que usam outros sistemas (Google Agenda ou APIs de parceiros)"; Fase 9 "Integrações externas ... quando uma clínica grande pedir"; "Fora do escopo: Integrações com outros sistemas de clínica antes da Fase 9" (fonte: briefing) | SAI do fluxo de marcação agora. Volta como integração da Camada 3 (Fase 9), só de LEITURA de horários, atrás de feature flag por clínica. |

O que acontece com o link externo:
- NÃO vira um quarto modo de recebimento. O glossário do briefing fixa `ModoRecebimento` em três valores: PEDIDO, VAGAS, AGENDA_NATIVA (fonte: briefing, Glossário e entidade Clinica). Um quarto valor exigiria mudar o glossário, o que o Orquestrador não faz sozinho.
- Até a Fase 9, uma clínica destino que usa outro sistema recebe encaminhamentos no modo PEDIDO: o paciente indica preferência e a secretária confirma o horário manualmente, olhando o sistema dela (fonte: briefing, Camada 2, modo Pedido). [SUPOSIÇÃO: o modo PEDIDO cobre esse caso sem integração; validar com o Avaliador]
- Na Fase 9, a leitura de horários de sistemas externos alimenta a escolha do paciente; continua sendo integração de leitura, não "entregar link do outro sistema" (fonte: briefing, Camada 3).
- Nenhuma tabela do modelo v2 guarda URL de sistema externo. [SUPOSIÇÃO: um campo assim só entra com o ADR da integração na Fase 9]

Marcado para ADR: "ADR: Agenda própria como núcleo; link do sistema externo substituído por modo PEDIDO até a integração de leitura da Camada 3". Status sugerido: Aceito pelo briefing; o ADR registra que substitui a premissa do v1. Redação do ADR: critério 7 (outra tarefa desta rodada).

## 2. Componentes do v1, um a um

| Elemento v1 (id no JSON) | v2 | Destino no v2 | Fonte |
|---|---|---|---|
| Paciente (`paciente`) | MANTÉM e MUDA | Paciente vira pessoa global com vínculo por clínica (`paciente`, `paciente_clinica`) | briefing, Mudanças 1 |
| WhatsApp Business Cloud API (`whatsapp`), "templates aprovados", "Só API oficial (Meta)" | MANTÉM e MUDA | Fica dentro do módulo `notificacoes`, com plano B por SMS ou e-mail; corpo da mensagem sem dado clínico, só link autenticado com expiração | briefing, Mudanças 4 e 9; Regras inegociáveis, Segurança |
| Chatbot do site (`chatbot`) | MUDA | Vira "marcação pelo site" da Camada 1 (formulário de agendamento, origem `SITE`). Conversa livre com IA sai | briefing, Camada 1; "IA antes da Fase 8" fora do escopo |
| Webhook de entrada (`webhook`), "normaliza os 2 canais" | MANTÉM e MUDA | Entrada de webhooks do WhatsApp no módulo `notificacoes`, com validação de assinatura obrigatória | briefing, Segurança da aplicação |
| Orquestrador (`orquestrador`), "identifica clinic_id e intenção" | MUDA | Deixa de ser componente central; o roteamento por intenção sai com a IA. O contexto de clínica passa a ser montado por requisição (`set_config('app.clinica_id', ..., true)`) e conferido pela RLS | briefing, Mudanças 6; Decisões, Multi-tenant |
| Motor de IA (`motor`) | SAI (volta na Fase 8) | Camada 3: resumo de consulta por áudio, resumo do caso, contrarreferência gerada. Não responde dúvidas no MVP | briefing, Camada 3 e "Fora do escopo: IA antes da Fase 8" |
| Base de conhecimento (`kb`), "convênios, endereço, preparos" | SAI | Só existia para o Motor de IA. [SUPOSIÇÃO: endereço e preparos podem voltar como texto de template de notificação; não é entidade do briefing] | briefing não lista a entidade |
| Fluxo de marcação (`marcacao`), "não cria agenda" | MUDA | Vira o módulo `agenda` (núcleo) | briefing, Camada 1; seção 1 acima |
| Sistema de gestão (`sistema`) | SAI (volta na Fase 9) | Integração de leitura da Camada 3 | seção 1 acima |
| Banco multi-tenant (`db`), "isolado por clinic_id" | MANTÉM e MUDA | Um PostgreSQL gerenciado; coluna `clinica_id` (o tenant) + RLS com FORCE + papel de aplicação sem BYPASSRLS; UUID em todo id | briefing, Decisões: Banco, Multi-tenant, Identificadores |
| Painel da recepção (`painel`), "atendente humano assume" | MANTÉM e MUDA | Painel da recepção da Camada 1 (agenda do dia, confirmar pedidos de encaminhamento). O "handoff da IA" sai com o Motor | briefing, Camada 1 e Personas (secretária) |
| Região "Backend Java / Spring Boot" | MANTÉM e MUDA | Monolito modular com Spring Modulith, 8 módulos | briefing, Mudanças 6 |
| Conexão `marcacao-sistema` "link de agendamento" | SAI | Substituída por Agendamento interno | seção 1 |
| Conexão `resposta` "botão Agende sua consulta" | MUDA | Template de notificação com link para a marcação própria | briefing, Camada 1 |
| Card "Multi-tenant": "Toda leitura e escrita filtrada por clinic_id" | MANTÉM e MUDA | Duas barreiras: filtro no código e RLS no banco. Exceção explícita: Encaminhamento atravessa tenants (visível à origem, clínica destino e paciente) | briefing, Decisões Multi-tenant; Mudanças 5 |
| Card "Multi-tenant": "Cada clínica tem sua própria base de conhecimento" | SAI | Junto com `kb` | idem `kb` |
| Card "WhatsApp sem bloqueio": só API oficial; fora da janela de 24h só template | MANTÉM | Módulo `notificacoes` | briefing, Notificações (Fase 4); Pesquisador, seção WhatsApp |
| Card "LGPD": "Consentimento registrado no primeiro contato" | MUDA | Entidade Consentimento com finalidade, texto aceito, data e revogação; consentimento específico para compartilhar o caso com a clínica destino | briefing, entidade Consentimento e Regras inegociáveis LGPD |
| Card "LGPD": "Dados isolados por clínica, sem cruzamento entre tenants" | MUDA | Isolamento continua, mas paciente e profissional são globais e o encaminhamento cruza tenants sob regra de relacionamento | briefing, Mudanças 1 e 5 |
| Nomenclatura `clinic_id` | MUDA | `clinica_id` (glossário: Clínica = Clinica) | briefing, Glossário |

## 3. Os 9 itens de "Mudanças na arquitetura do Arquify"

| # | Item do briefing | Situação no v1 | v2 | Onde está no v2 |
|---|---|---|---|---|
| 1 | Identidade global, vínculo por clínica | Não existe: "pacientes" dentro do banco por `clinic_id` | ENTRA | `profissional` + `profissional_clinica`; `paciente` + `paciente_clinica`; `usuario` + `usuario_clinica` (modelo-dados-v2.md, seção 2) |
| 2 | Entidades novas ou alteradas (11 entidades) | Nenhuma modelada (só "conversas, pacientes, configs") | ENTRA | Todas as 11 em modelo-v2.sql, mais termos novos listados em glossario-adicoes.md |
| 3 | Status do encaminhamento como máquina de estados, registro com data e autor | Não existe | ENTRA | Coluna `encaminhamento.status` com os 8 valores; transições T1 a T11 impostas por gatilho e histórico gravado só por gatilho, com ator verificado (ADR-0027) |
| 4 | Módulo único de notificações, templates, fila assíncrona | Envio espalhado: orquestrador responde direto ao WhatsApp (conexão `resposta`) | MUDA | Módulo `notificacoes`; eventos via outbox do Spring Modulith (mapa-modulos.md, critério 3) |
| 5 | Permissões: papéis por clínica; encaminhamento só para origem, destino e paciente | Não existe | ENTRA | `usuario_clinica.papel` (ADMIN, RECEPCAO, MEDICO); identidade de todo ator por sessão verificada no banco (ADR-0023); políticas `encaminhamento_origem`, `encaminhamento_destino`, `encaminhamento_paciente` |
| 6 | Monolito modular com Spring Modulith, 8 módulos | "Backend Java / Spring Boot" sem módulos | MUDA | mapa-modulos.md (critério 3) |
| 7 | Eventos internos AgendamentoCriado, ConsultaRealizada, EncaminhamentoAgendado | Não existe | ENTRA | mapa-modulos.md; evento só com ids (ADR-0020) e só com consumidor (ADR-0032) |
| 8 | Feature flags por clínica | Não existe | ENTRA | `flag_clinica` (nasce `ligada = false`); a flag REDE_ENCAMINHAMENTO é conferida também no banco (`rede_ligada`) |
| 9 | Plano B de mensagens (SMS ou e-mail) | Só WhatsApp | ENTRA | Módulo `notificacoes` com `envio_notificacao` (canal, status, tentativas, chave de idempotência, sem corpo; ADR-0034). Custo de SMS ainda não levantado (Pesquisador) |

## 4. Decisões desta revisão que viram ADR (insumo do critério 7)

Rodada 0:
1. Agenda própria como núcleo; sistema externo vira integração de leitura na Fase 9 (ADR-0015).
2. Motor de IA e Base de conhecimento saem até a Fase 8 (ADR-0021).
3. Papel de acesso em `usuario_clinica` (ADR-0016).
4. Contexto por `set_config(..., true)` (ADR-0004). Papéis de banco: ADR-0024 (substitui D2).
5. Visibilidade da clínica destino condicionada a consentimento (ADR-0022).
6. Eventos só com ids (ADR-0020).
7. Histórico por gatilho: ADR-0027 (substitui D7). Enumerações `text` com CHECK: ADR-0028 (D8).

Rodada 1 (veto do Red Team e Avaliador):
8. Sessão verificável no banco para todo ator (ADR-0023).
9. Autenticação do médico que encaminha sem conta (ADR-0025).
10. Proteção de dados (ADR-0026).
11. Identidade do paciente global: deduplicação, vínculo e telefone (ADR-0029).
12. Link e código do paciente (ADR-0030).
13. VAGAS e AGENDA_NATIVA adiados para a Fase 6 (ADR-0031).
14. Só evento com consumidor; confirmação única (ADR-0032).
15. Requisitos antes das Fases 4 e 5 (ADR-0033); registro de envio (ADR-0034); segundo elemento do paciente (ADR-0035, decisão do Luiz).
