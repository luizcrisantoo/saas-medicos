# ADR-0008: Paciente sem senha: link de uso único e código pelo WhatsApp

Status: Aceito (decisão do briefing)
Data: 2026-11-10
Tarefa: t-fase1-arquitetura

## Contexto
A paciente persona tem 70 anos e só usa WhatsApp. Não deve criar conta nem ter senha para vazar. Nenhum dado clínico pode aparecer antes da confirmação.

## Decisão
O paciente recebe um link assinado, de uso único e com expiração; ao abrir, recebe um código de uso único pelo WhatsApp (plano B: SMS ou e-mail) e só depois do código vê qualquer dado. Só os hashes do token e do código são gravados (`link_paciente.token_hash`, `codigo_hash`, `tentativas_codigo` limitado a 10). Antes do código o contexto é PUBLICO_LINK e enxerga só a linha do próprio link; depois, PACIENTE com `app.paciente_id`. Rodada 1: o link só é acessível por funções e o código abre uma sessão de paciente registrada no banco (ADR-0023, ADR-0030).

## Alternativas descartadas
- Conta com senha para o paciente: contraria o briefing e a persona.
- Link sem código: quem pegar o celular ou a conversa encaminhada vê o caso.
- Código por e-mail como canal principal: a persona só usa WhatsApp.

## Consequências
- Limite de requisições por IP e por link no código (briefing, Segurança da aplicação).
- Token e código nunca entram em evento, log ou registro do outbox: são gerados sob demanda na hora do envio (mapa-modulos.md, regra "Segredo nunca em evento").
- Se o provedor de autenticação (ADR-0007) atender o paciente, este ADR é revisto.

## Fontes
- docs/briefing.md: Decisões de arquitetura, Paciente; Proteção de dados (links); Personas
- docs/arquitetura/modelo-v2.sql (link_paciente, políticas link_publico)
