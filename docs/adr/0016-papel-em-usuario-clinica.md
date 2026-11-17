# ADR-0016: Papel de acesso em usuario_clinica, não em profissional_clinica

Status: Aceito na revisão da Fase 1, sujeito ao Avaliador
Data: 2026-11-10
Tarefa: t-fase1-arquitetura

## Contexto
O briefing lista "papel" entre os campos de ProfissionalClinica. Mas a recepção não tem CRM e não é Profissional (glossário: Profissional = "Médico com CRM"), e a autorização precisa de uma fonte única de papel.

## Decisão
O papel por clínica (ADMIN, RECEPCAO, MEDICO) mora em `usuario_clinica`, que liga o Usuário autenticado à Clínica. `profissional_clinica` guarda só o vínculo clínico (agenda, duração da consulta, se recebe encaminhamento). Termos novos em `glossario-adicoes.md`.

## Alternativas descartadas
- Papel em `profissional_clinica`: obrigaria cadastrar a secretária como Profissional sem CRM.
- Papel nos dois lugares: duas fontes de verdade para a autorização.

## Consequências
- Divergência de campo com o briefing; se o Avaliador recusar, o papel volta para `profissional_clinica` e a recepção precisa de outro vínculo.
- Médico que atende e tem conta tem as duas linhas (Usuario e Profissional, ligados por `profissional.usuario_id`).

## Fontes
- docs/briefing.md: Glossário; Mudanças 2 (ProfissionalClinica) e 5
- docs/arquitetura/modelo-dados-v2.md, D3
