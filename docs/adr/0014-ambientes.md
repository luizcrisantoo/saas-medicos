# ADR-0014: Ambientes de desenvolvimento, homologação e produção

Status: Aceito (decisão do briefing)
Data: 2026-11-10
Tarefa: t-fase1-arquitetura

## Contexto
Dado real de paciente nunca sai de produção. O build in public só grava em homologação com dado fictício.

## Decisão
Três ambientes isolados. Homologação só com dado fictício. Varredura dinâmica (OWASP ZAP) em homologação antes de cada release. Feature flags (ADR-0019) separam piloto de outras clínicas dentro de produção, sem ambiente extra.

## Alternativas descartadas
- Só dev e produção: não há onde testar com segurança nem gravar conteúdo público.
- Cópia de produção em homologação: viola a regra de dado real.

## Consequências
- Geração de dado fictício precisa existir desde a Fase 2.
- URLs de homologação e produção nunca aparecem em conteúdo público (briefing, Build in public).

## Fontes
- docs/briefing.md: Decisões de arquitetura, Ambientes; Pipeline; Build in public
