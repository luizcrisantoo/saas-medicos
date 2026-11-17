# Red Team: t-fase1-arquitetura, rodada 2

Data: 2026-11-10. Poder de veto: docs/briefing.md, "Regras do fluxo neste projeto". Alvo: `docs/arquitetura/modelo-v2.sql` r2, ADR-0036 novo, ADRs 0023, 0026, 0027, 0029, 0030 alterados, rodada 2 no fim de `docs/tasks/t-fase1-arquitetura.md`. Ameaças: `docs/seguranca/stride-encaminhamento.md` (status r2 na seção 14, novas na seção 16, lista por fase na seção 12).

Evidência própria (PostgreSQL 16.15, cluster `.pgrt2`, porta 5492, usuário de SO `pgtest`, cluster novo, papéis reais por `\c`):
- `docs/seguranca/evidencias/red-team-sondas-r1-novas-pgrt2.log`: minhas sondas da r1 contra o modelo r2. N4c, N6a, N6b, N7a NEGADO; N5b e N5c passam com `ALERTA_DDL_SAAS` no log.
- `docs/seguranca/evidencias/red-team-sondas-r2.sql` e `.log`: sondas novas R2N1 a R2N9, `modelo-v2.sql` exit 0, runner copiado no fim do log.

## Veredito final da Fase 1: APROVADO COM RESSALVAS

Os quatro itens que exigi na r1 caíram ou foram mitigados no desenho. A sessão por caso aguentou todos os caminhos que tentei. Os achados novos ficam no mesmo lugar dos da r1: se corrigem na primeira migração de `paciente`, `encaminhamento` e `paciente_clinica` e no gatilho de evento. Viram gate da Fase 2. Se a migração sair sem eles, a aprovação cai e vira veto.

## 1. Itens exigidos na r1

| Item | Status r2 | Prova |
|---|---|---|
| T-18 telefone funde pessoas | RESOLVIDO para o telefone | N6a, N6b NEGADO; R2N1b controle; R2N1c escopo. A fusão volta pelo CPF: T-20 |
| I-19 sessão vale para a pessoa | RESOLVIDO | N7a NEGADO; R2N4a a R2N4l: o caso do filho, no mesmo aparelho, fica fora de alcance por encaminhamento, paciente, histórico, anexo, agendamento, consentimento, contrarreferência, UPDATE de status, revogação, INSERT de consentimento e auditoria |
| I-20 token em `pg_stat_activity` | MITIGADO | ADR-0026, item 7; N4c NEGADO; R2N7a a R2N7g: SET, ALTER ROLE e opção de arranque negados. Falta o teste de código (Fase 2) |
| R-07 dono contorna gatilho e RLS | PARCIAL | ADR-0027 corrigido; alerta pega ALTER TABLE e DROP; é cego a CREATE POLICY, ALTER POLICY e CREATE TRIGGER (R-08) |

## 2. As regras novas abrem ataque?

- Paciente duplicado como canal de vazamento: não para leitura entre pessoas. Cada duplicata só aparece para quem a criou ou para a clínica com consentimento ativo. Abre um canal de escrita depois da revogação (I-23, MÉDIO).
- Caso do filho por outro caminho: pela sessão, não. Pelo cadastro, sim. Com o "CPF do responsável", o caso do filho cai no registro da mãe (T-20, ALTO, R2N1a). A recepção recebe o id de outra pessoa sem nenhum aviso (R2N3a).
- Telefone de contato: se o CPF bate, o número digitado agora é descartado, e link e código vão ao número antigo (I-22, ALTO, R2N2a). Paciente nascido de encaminhamento não tem quem corrija o telefone (R2N6a).

## 3. Gates da Fase 2 (sem eles, veto)

1. T-20: ADR-0036, item 2a, corrigido antes da migração. CPF só funde quando nome e nascimento também batem. Na recepção, uma coincidência volta como sugestão e nunca como id.
2. I-22: o telefone informado não é descartado em silêncio.
3. R-08: gatilho de evento filtrado pela tabela alvo, não por `schema_name`. O CI também recusa CREATE/ALTER POLICY e CREATE TRIGGER fora de migração revisada.
4. I-23: busca e escrita da recepção só por vínculo de cadastro ou com consentimento ativo.
5. Pendências da r1 continuam como gate: E-09, E-10, I-21, O3, CI de R-07, teste de código de I-20. Regressão: N1 a N12, RT1 a RT10, R2N1 a R2N9, R2-1 a R2-7 e a matriz de 392 sondas.

Fase 3: T-19, O2 (inclui R2N6a), T-12 e a tela de duplicatas do ADR-0036. Fase 4: D-09. Fase 5: S-10, D-08 e as decisões do Luiz nos ADR-0025 e ADR-0035.
