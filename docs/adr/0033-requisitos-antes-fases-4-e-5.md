# ADR-0033: Requisitos de segurança obrigatórios antes das Fases 4 e 5

Status: Aceito na revisão da Fase 1 (rodada 1) como requisito; implementação nas fases indicadas
Data: 2026-11-10
Tarefa: t-fase1-arquitetura

## Contexto
O Red Team listou requisitos que não bloqueiam a Fase 1 se ficarem registrados no desenho (itens 20 a 22).

## Decisão
Antes da Fase 4 (notificações):
- Mensagem de entrada pelo WhatsApp nunca autentica, consente nem muda status; o webhook de entrada grava só id, tipo e horário, nunca o corpo (S-08, I-14).
- Lista fechada de variáveis por template, revisada pelo Red Team: sem nome de paciente, especialidade, conduta ou nome livre de médico (I-08, S-09). `profissional.nome` já tem CHECK de tamanho e sem URL.
- Teto de mensagens por encaminhador, por clínica e global, com corte e alerta; SMS do plano B com teto próprio (D-02).
- Listener relê o estado na fonte e é idempotente (já no desenho: funções `jobs_*`); `event_publication` com limpeza por prazo e sem GRANT ao papel web (T-10, I-16).
Antes da Fase 5 (encaminhamento v1):
- Upload de escrita única, objeto imutável, tipo por assinatura de bytes, hash e tamanho calculados no servidor, URL de download de minutos com `attachment` e `no-store`, prazo de retenção decidido (T-09, I-11, I-13). `chave_storage` já é gerada pelo servidor e imutável.
- Decisões do Luiz: ADR-0025 (titularidade do CRM) e ADR-0035 (segundo elemento do paciente).

## Consequências
- Cada item vira teste na lista de ataques da fase (docs/seguranca/stride-encaminhamento.md, seção 12).

## Fontes
- docs/agents/red-team-t-fase1-arquitetura.md, itens 20 a 23
