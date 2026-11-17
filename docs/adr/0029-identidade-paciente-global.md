# ADR-0029: Identidade do paciente global: deduplicação, vínculo e telefone

Status: Aceito na revisão da Fase 1 (rodada 1); item 2 substituído na rodada 2 pelo ADR-0036 (Red Team T-18)
Data: 2026-11-10
Tarefa: t-fase1-arquitetura
Completa: ADR-0017 (deduplicação que ficou pendente do Red Team)

## Contexto
Paciente é pessoa global. Na rodada 0 uma clínica criava `paciente_clinica` com UUID de paciente de outra clínica, passava a ler o cadastro e trocava o telefone global, recebendo os códigos de todas as clínicas (RT1, RT10; Testador falha 2; Red Team itens 6, 7, 8; STRIDE T-07, T-08, I-01, I-02).

## Decisão
1. `paciente_id` nunca vem do cliente. Paciente nasce ou é localizado só dentro de `encaminhamento_cria` e `paciente_cadastra_na_clinica`. O papel web não tem INSERT em `paciente`, `paciente_clinica` nem `encaminhamento`.
2. Deduplicação (escopo mantido; CRITÉRIO substituído pelo ADR-0036 na rodada 2: telefone é contato, não identidade): a busca só encontra paciente já ligado ao ator (encaminhamentos do mesmo profissional; para a clínica, vínculo de cadastro com ela). Fora disso nasce registro novo. Fusão de registros globais só com código confirmado pelo próprio paciente, auditada [fluxo da Fase 5, fora deste SQL].
3. Vínculo `paciente_clinica` nasce por cadastro da própria clínica ou por `destino_confirma_horario` (T4). O vínculo de encaminhamento guarda `encaminhamento_id` e só dá leitura enquanto o consentimento COMPARTILHAR_CASO estiver ativo (STRIDE I-03).
4. Telefone: sem GRANT de UPDATE para a web. Troca só por `paciente_troca_telefone_presencial`, pela recepção ou admin da clínica que cadastrou o paciente, auditada. Paciente e outras clínicas não trocam. Aviso ao número antigo: requisito da Fase 3 (o registro de envio não guarda contato).
5. Nome e nascimento: UPDATE por coluna só pela clínica que cadastrou (`cadastrado_por_clinica_id`).

## Alternativas descartadas
- UNIQUE no hash do CPF: oráculo de existência entre clínicas (ADR-0017).
- Busca global por CPF com confirmação posterior: o dado de outra clínica já teria sido mostrado.

## Consequências
- Haverá duplicatas do mesmo paciente entre clínicas; a fusão consentida resolve depois.
- Provas: `teste-rls-r1.log` seções r1-6, r1-7, r1-8; `red-team-sondas-r1.log` RT1a a RT1d, RT10a, RT10b.

## Fontes
- docs/agents/red-team-t-fase1-arquitetura.md, itens 6, 7, 8; docs/seguranca/stride-encaminhamento.md, T-07, T-08, I-01, I-02, I-03
- docs/arquitetura/modelo-v2.sql, seção 12
