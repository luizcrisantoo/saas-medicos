# ADR-0034: Registro de envio de notificação sem corpo da mensagem

Status: Aceito na revisão da Fase 1 (rodada 1)
Data: 2026-11-10
Tarefa: t-fase1-arquitetura

## Contexto
O módulo `notificacoes` não tinha tabela (sugestão S2; Avaliador, critérios 2 e 3). Idempotência de envio é regra do briefing e o plano B (ADR-0018) precisa saber o que falhou.

## Decisão
Tabela `envio_notificacao`: finalidade, canal, destinatário por tipo e id, referências (encaminhamento, agendamento, link, desafio), `chave_idempotencia` única, status (PENDENTE, PREPARADO, ACEITO, ENTREGUE, FALHOU), tentativas (até 5) e id do provedor. Sem coluna de texto da mensagem, sem contato gravado. Sem GRANT para nenhum papel de login: a web cria linha só por funções (pedido de código), o `saas_jobs` lê e atualiza só pelas funções `jobs_envio_*`, que devolvem o contato daquele envio e o segredo gerado na hora.

## Alternativas descartadas
- Guardar o texto enviado para auditoria: copiaria dado pessoal para fora das tabelas protegidas.

## Consequências
- O painel da recepção mostra status de entrega por consulta a uma função que ainda não existe (Fase 4).
- Retenção da tabela: mesmo prazo do encaminhamento [pergunta aberta junto com a retenção, regras-inegociaveis-check.md].

## Fontes
- docs/tasks/t-fase1-arquitetura.md, sugestão S2; docs/briefing.md, Segurança da aplicação (idempotência); ADR-0018
