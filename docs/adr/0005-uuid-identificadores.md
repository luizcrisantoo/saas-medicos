# ADR-0005: UUID em todo identificador exposto

Status: Aceito (decisão do briefing)
Data: 2026-11-10
Tarefa: t-fase1-arquitetura

## Contexto
Id sequencial em URL ou API permite adivinhar ids de outros pacientes.

## Decisão
Toda chave primária é `uuid DEFAULT gen_random_uuid()`. Nenhuma sequência aparece em URL, API, evento ou mensagem.

## Alternativas descartadas
- Inteiro sequencial com checagem de acesso: a checagem continua necessária, mas o id ainda revela volume e facilita enumeração.
- Id sequencial interno e UUID público em coluna separada: duas chaves para manter sem ganho no volume do piloto.

## Consequências
- UUID não substitui autorização: a RLS e o serviço de autorização continuam obrigatórios.
- Token do link do paciente não é UUID: é segredo aleatório guardado só como hash (`link_paciente.token_hash`).

## Fontes
- docs/briefing.md: Decisões de arquitetura, Identificadores
- docs/arquitetura/modelo-v2.sql
