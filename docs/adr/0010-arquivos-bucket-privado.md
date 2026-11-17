# ADR-0010: Arquivos em bucket privado criptografado com URL assinada curta

Status: Aceito (decisão do briefing)
Data: 2026-11-10
Tarefa: t-fase1-arquitetura

## Contexto
Exame anexado é o dado mais sensível do sistema. Regra inegociável: anexos sempre em storage criptografado.

## Decisão
Bucket privado com criptografia em repouso; acesso só por URL assinada de poucos minutos, emitida pelo módulo `arquivos` depois da autorização e com EventoAuditoria. Validação de tipo (PDF, JPEG, PNG) e tamanho (até 20 MiB [SUPOSIÇÃO]) antes do upload; varredura de vírus, e download só com `status_varredura = LIMPO`. Chave do objeto opaca; nome original cifrado na aplicação.

## Alternativas descartadas
- Arquivo no banco: infla backup e mistura dado binário com o transacional.
- Bucket com link público ou URL longa: o link vaza e vale por muito tempo.

## Consequências
- Serviço de varredura de vírus a escolher com a hospedagem (ADR-0012).
- Prazo de retenção dos anexos é pergunta aberta (Lei 13.787 fala em 20 anos para prontuário; a qualificação do anexo vai ao advogado). `anexo_encaminhamento.reter_ate` existe para receber o prazo.

## Fontes
- docs/briefing.md: Decisões de arquitetura, Arquivos; Regras inegociáveis, Segurança e LGPD
- docs/agents/pesquisador-t-fase1-arquitetura.md: seção 4, Retenção de prontuário
- docs/arquitetura/modelo-v2.sql (anexo_encaminhamento)
