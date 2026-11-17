# ADR-0018: Plano B de mensagens por SMS ou e-mail

Status: Aceito (decisão do briefing)
Data: 2026-11-10
Tarefa: t-fase1-arquitetura

## Contexto
O módulo de notificações não pode depender só do WhatsApp. Se a API cair ou o número for bloqueado, os avisos críticos precisam sair.

## Decisão
O módulo `notificacoes` tem canais WhatsApp (principal), SMS e e-mail. Avisos críticos (confirmação de agendamento, link de encaminhamento, código de uso único) caem para SMS ou e-mail quando o WhatsApp falha ou o número está bloqueado. A troca de canal é decisão interna do módulo; nenhum outro módulo escolhe canal. O corpo segue sem dado clínico em todos os canais.

## Alternativas descartadas
- Só WhatsApp: ponto único de falha do encaminhamento inteiro.
- Cada módulo com seu fallback: espalha envio de mensagem pelo código, contra o briefing.

## Consequências
- Custo de SMS por mensagem não levantado; entra no teto (ADR-0013).
- Tabela de envios e tentativas não está no modelo v2 (sugestão S2 da tarefa).
- Webhook de status de entrega com assinatura validada.

## Fontes
- docs/briefing.md: Mudanças 4 e 9; Regras inegociáveis, Segurança
- docs/agents/pesquisador-t-fase1-arquitetura.md: seção 1 (custo de SMS)
