# ADR-0001: Monolito modular com Spring Modulith

Status: Aceito (decisão do briefing)
Data: 2026-11-10
Tarefa: t-fase1-arquitetura

## Contexto
O produto guarda dado de saúde de várias clínicas e é construído por uma pessoa só; o critério do briefing é reduzir risco de vazamento e trabalho de operação, nessa ordem. Microsserviços estão fora do escopo.

## Decisão
Um projeto Spring Boot (Java 21) com Spring Modulith e 8 módulos: identidade, clinicas, agenda, pacientes, encaminhamentos, notificacoes, arquivos, auditoria. Dependências permitidas declaradas por módulo e verificadas em teste com `ApplicationModules.of(...).verify()`. O mapa está em `docs/arquitetura/mapa-modulos.md`.

## Alternativas descartadas
- Microsserviços: custo de operar vários serviços, rede e transações distribuídas; o briefing os põe fora do escopo.
- Monolito sem fronteiras verificadas: nada impede o acoplamento entre agenda e rede que o briefing quer evitar.

## Consequências
- O teste de fronteira de módulos passa a ser obrigatório no CI (briefing, Testes que não podem faltar).
- O grafo de dependências não pode ter ciclo; a direção está fixada no mapa de módulos e só muda com novo ADR.
- Um único deploy; escalar é vertical até prova em contrário [SUPOSIÇÃO].

## Fontes
- docs/briefing.md: Mudanças 6; Decisões de arquitetura, Estilo; Fora do escopo
- docs/agents/pesquisador-t-fase1-arquitetura.md: Spring Modulith, doc de verificação
- docs/arquitetura/mapa-modulos.md
