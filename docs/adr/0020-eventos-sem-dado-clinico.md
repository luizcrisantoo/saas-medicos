# ADR-0020: Eventos de domínio carregam só ids

Status: Aceito na revisão da Fase 1, sujeito ao Avaliador
Data: 2026-11-10
Tarefa: t-fase1-arquitetura

## Contexto
O Event Publication Registry grava o evento inteiro serializado e mantém entradas concluídas até limpeza periódica. Dado clínico num evento ficaria copiado fora das tabelas protegidas por RLS e criptografia.

## Decisão
Payload de evento só com UUIDs, enumerações e o instante do fato. Nunca nome, telefone, CPF, motivo, conduta, nome de arquivo, token de link ou código. O consumidor busca o que precisa pela API do módulo dono, sob autorização. Segredos de uso único são gerados sob demanda na hora do envio.

## Alternativas descartadas
- Evento gordo com os dados: vaza dado sensível para a tabela do outbox e para logs de erro de listener.
- Criptografar o payload: mais uma chave e o mesmo risco em log.

## Consequências
- Consumidores fazem uma leitura a mais; aceitável no volume do piloto [SUPOSIÇÃO].
- Revisão de código e teste checam a lista de campos de cada evento [SUPOSIÇÃO: teste de arquitetura na Fase 2].

## Fontes
- docs/agents/pesquisador-t-fase1-arquitetura.md: Spring Modulith ("Each log entry contains the original event in serialized form")
- docs/briefing.md: Proteção de dados (logs sem dado pessoal)
- docs/arquitetura/modelo-dados-v2.md, D6
- docs/arquitetura/mapa-modulos.md
