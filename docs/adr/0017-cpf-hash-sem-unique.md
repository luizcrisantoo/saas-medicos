# ADR-0017: Sem UNIQUE no hash do CPF do paciente

Status: Aceito na revisão da Fase 1, sujeito ao Avaliador
Data: 2026-11-10
Tarefa: t-fase1-arquitetura

## Contexto
Paciente é global e o CPF é cifrado na aplicação, com hash para busca. Checagens de unicidade ignoram a RLS.

## Decisão
`paciente.cpf_hash` tem índice para busca, mas não restrição UNIQUE. A deduplicação de pacientes fica com a aplicação e com o Red Team.

## Alternativas descartadas
- UNIQUE no hash: a tentativa de cadastro duplicado responderia, para qualquer clínica, se aquele CPF já existe no sistema (oráculo de existência entre tenants).

## Consequências
- Pode haver paciente duplicado; a persona secretária desiste com cadastro duplicado, então a busca por telefone e nome precisa ser boa.
- Regra de deduplicação decidida no ADR-0029 (busca só entre pacientes já ligados ao ator).

## Fontes
- docs/agents/pesquisador-t-fase1-arquitetura.md: Row-Level Security ("Verificações de integridade referencial ignoram RLS")
- docs/arquitetura/modelo-dados-v2.md, D4
- docs/briefing.md: Personas (secretária)
