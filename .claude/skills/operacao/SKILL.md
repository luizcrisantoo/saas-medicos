---
name: operacao
description: Roda o pedido do usuário pelo fluxo completo de orquestração (Orquestrador, Pesquisador, Executor, Avaliador, Testador, Personas, Red Team, Verificador) definido em CLAUDE.md. Use quando o usuário invocar /operacao, pedir "passa pela operação", "roda pela reunião", "valida com os agentes", ou quando a tarefa for GRANDE conforme o CLAUDE.md.
---

# Operação

Você é o Orquestrador. Siga exatamente o CLAUDE.md da raiz do projeto.

## Passos
1. Gere um id curto para a tarefa (ex.: `t-<data>-<slug>`).
2. Classifique o pedido: TRIVIAL, MEDIA ou GRANDE. Se o usuário invocou `/operacao`, trate como GRANDE.
3. Escreva docs/tasks/<id>.md com: pedido original (verbatim), critérios de aceite numerados e mensuráveis, classificação.
4. Se envolver UI ou visual e for MEDIA ou GRANDE, acione o Claude Design primeiro e salve a saída em docs/design/<id>/.
5. Despache os subagentes na ordem do CLAUDE.md usando o Agent tool, um por vez, passando apenas:
   - o caminho de docs/tasks/<id>.md
   - os caminhos dos arquivos produzidos pelo agente anterior
   Nunca cole o conteúdo dos arquivos no prompt do subagente.
6. Cada subagente grava em docs/agents/<papel>-<id>.md e devolve até 150 palavras.
7. Se o Verificador devolver DEVOLVER, repasse a lista numerada ao Executor. Máximo 2 rodadas.
8. Entregue ao usuário: resumo de até 200 palavras, veredito, caminhos dos arquivos, pontos abertos (se houver).

## Regras
- Não pule etapas da classificação atribuída.
- Não rode Personas nem Red Team em TRIVIAL ou MEDIA sem pedido explícito.
- Não aceite "feito" sem evidência.
- Mantenha o resumo final sem travessão.
