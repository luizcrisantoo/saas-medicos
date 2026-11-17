# ADR-0035: Segundo elemento antes de mostrar dado clínico ao paciente

Status: Proposto: decisão do Luiz (antes da Fase 5)
Data: 2026-11-10
Tarefa: t-fase1-arquitetura

## Contexto
Link e código vão para o mesmo celular. Quem tem o celular desbloqueado, recebeu a conversa num grupo ou é dono de um número digitado errado vê o caso (STRIDE S-06; Red Team item 23).

## Opções
1. Pedir um segundo elemento de conhecimento antes de mostrar motivo e anexos (ex.: data de nascimento informada pelo encaminhador) [SUPOSIÇÃO de opção]. Risco: a persona de 70 anos erra e desiste.
2. Aceitar por escrito o risco de posse do celular, com tela pós-código mínima (só clínica e horário; motivo e anexos atrás de mais um toque explícito).
3. Mostrar dado clínico só na clínica destino; o paciente vê apenas a escolha de clínica e o horário.

## Consequências
- Qualquer opção mantém a sessão de paciente de 30 minutos (ADR-0023) e o limite de tentativas (ADR-0030).

## Fontes
- docs/agents/red-team-t-fase1-arquitetura.md, item 23; docs/seguranca/stride-encaminhamento.md, S-06; docs/briefing.md, Personas (paciente)
