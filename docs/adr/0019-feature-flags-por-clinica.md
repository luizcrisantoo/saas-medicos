# ADR-0019: Feature flags por clínica

Status: Aceito (decisão do briefing)
Data: 2026-11-10
Tarefa: t-fase1-arquitetura

## Contexto
Cada funcionalidade nova da rede nasce desligada e é ligada clínica por clínica; uma falha se desliga sem novo deploy.

## Decisão
Tabela `flag_clinica` (`chave`, `ligada` com padrão false), dona: módulo `clinicas`, consultada por `FlagsApi.ligada(clinicaId, chave)` em `encaminhamentos` e `notificacoes` antes de agir para uma clínica. Alteração por papel de operação ou ADMIN, com auditoria.

## Alternativas descartadas
- Flag global por propriedade de configuração: exige deploy e não separa o piloto.
- Serviço externo de flags: mais um fornecedor com dado de tenant.

## Consequências
- Toda funcionalidade da rede tem uma chave de flag antes de entrar (briefing, Definição de pronto).
- Listeners precisam conferir a flag no momento do processamento, não só na publicação [SUPOSIÇÃO].

## Fontes
- docs/briefing.md: Mudanças 8; Definição de pronto
- docs/arquitetura/modelo-v2.sql (flag_clinica)
