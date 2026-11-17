# ADR-0011: Hospedagem em nuvem com região no Brasil e serviços gerenciados

Status: Aceito (decisão do briefing)
Data: 2026-11-10
Tarefa: t-fase1-arquitetura

## Contexto
Facilita a conversa de LGPD e tira operação de quem constrói sozinho. Qual nuvem é pergunta aberta (ADR-0012).

## Decisão
Banco, storage, segredos e gerenciamento de chaves em serviços gerenciados numa região do Brasil. Segredos só no gerenciador da nuvem, nunca no repositório. Chaves da criptografia na aplicação num serviço de gerenciamento de chaves.

## Alternativas descartadas
- Servidor próprio ou VPS sem serviços gerenciados: backup, segredos e chaves viram trabalho manual.
- Região fora do Brasil: transferência internacional complica a LGPD.

## Consequências
- Railway e Render saem da lista por não terem região no Brasil (Pesquisador).
- A escolha concreta fica no ADR-0012.

## Fontes
- docs/briefing.md: Decisões de arquitetura, Hospedagem; Pipeline (segredos)
- docs/agents/pesquisador-t-fase1-arquitetura.md: seção 2
