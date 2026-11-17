# Red Team: t-fase1-arquitetura, rodada 1

Data: 2026-11-10. Poder de veto: docs/briefing.md, "Regras do fluxo neste projeto". Alvo: `docs/arquitetura/modelo-v2.sql` r1, ADRs 0023 a 0035, rastreio no fim de `docs/tasks/t-fase1-arquitetura.md`. Ameaças: `docs/seguranca/stride-encaminhamento.md` (status r1 em cada linha; novas na seção 14). Sondas novas: `docs/seguranca/evidencias/red-team-sondas-r1-novas.sql` e `.log` (PostgreSQL 16.15, `.pgrt`, porta 5495, usuário de SO `pgtest`, cada sonda conectada com o papel real).

## Veredito: APROVADO COM RESSALVAS

O achado raiz da rodada 0 caiu: identidade só por sessão em tabela, jobs em papel próprio, histórico só por gatilho, link sem escrita da web. Reexecutei `red-team-sondas-r1.sql` num banco limpo: 26 de 26 sondas RT negadas, 2 controles positivos. As sondas novas não acharam escalada de papel, `search_path` explorável, função aberta a PUBLIC, sombra por `pg_temp` nem token adivinhável. O que sobrou não bloqueia a Fase 2 porque se corrige na primeira migração de cada tabela, e vira teste obrigatório dela. Dois achados novos são CRÍTICO e ALTO em dado de saúde (T-18, I-19): se a migração de `paciente` e `encaminhamento` da Fase 2 sair sem a correção, a aprovação cai e vira veto.

## 1. Itens da rodada 0

| Item | Status | Onde |
|---|---|---|
| 1 Sessão verificável para todo ator | RESOLVIDO | modelo-v2.sql:319-336, 482-530; ADR-0023:11-16. Escopo da sessão de paciente: I-19 |
| 2 Papel separado para jobs | RESOLVIDO | modelo-v2.sql:53-60, 1359-1363; ADR-0024:12-21; N2g. Resíduo de credencial: E-09 |
| 3 Profissional amarrado ao usuário e à clínica | RESOLVIDO | modelo-v2.sql:508-519 |
| 4 Autenticação do encaminhador | PARCIAL | modelo-v2.sql:822-874; ADR-0025:12-17. Oráculo por efeito colateral, squatting sem recuperação e cadastro global por admin de clínica (S-10, N9a, N9c). Fase 5 |
| 5 FK composta | RESOLVIDO | modelo-v2.sql:182, 240-241, 276-277, 296, 352, 374-379, 397 |
| 6 Vínculo e `paciente_id` nunca do cliente | RESOLVIDO | modelo-v2.sql:879-917, 973, 1342-1343; ADR-0029:12 |
| 7 Telefone imutável | RESOLVIDO | modelo-v2.sql:921-930, 1329-1330; ADR-0029:15 (O2 aceita) |
| 8 Deduplicação | PARCIAL | modelo-v2.sql:885-891, 908-910; ADR-0029:13. Escopo certo, critério errado: telefone sozinho funde pessoas (T-18, N6a, N6b). Fase 2 |
| 9 UPDATE por coluna e imutáveis | RESOLVIDO | modelo-v2.sql:619-624, 1331. ADR-0027:15 diz "até superusuário": falso (R-07, N5c) |
| 10 Transições T1 a T11 | RESOLVIDO | modelo-v2.sql:588-654; ADR-0027:12-18; N2i |
| 11 Consentimento | RESOLVIDO | modelo-v2.sql:276-277, 1288-1295 |
| 12 Histórico e auditoria | RESOLVIDO | modelo-v2.sql:659-684, 735-741, 1302-1306. Dono apaga sem rastro: R-07 |
| 13 Link do paciente | RESOLVIDO | modelo-v2.sql:283-301, 722-732, 763-817; ADR-0030:12-17. Bloqueio permanente: D-08 |
| 14 Anexo | RESOLVIDO | modelo-v2.sql:406, 706-719, 1113-1120 |
| 15 Agendamento pelo paciente | RESOLVIDO | modelo-v2.sql:106, 947, 970, 1209-1215; ADR-0031 |
| 16 T8 com WHERE | RESOLVIDO | modelo-v2.sql:1068-1078 |
| 17 Catálogo e profissional | RESOLVIDO | modelo-v2.sql:934-938, 1184-1185, 1325 (O3 aceita com ajuste) |
| 18 Funções estreitas de sistema | RESOLVIDO | modelo-v2.sql:988-1120; mapa-modulos.md:166-179; revisão em stride, seção 15 |
| 19 ADR de Proteção de dados | PARCIAL | ADR-0026:13-15. Falta exigir parâmetro ligado para `app.sessao` (I-20, N4c passa, N4d nega). Fase 2 |
| 20 Requisitos antes da Fase 4 | RESOLVIDO como requisito | ADR-0033:11-15; somar teto por telefone de destino (D-09) |
| 21 Listener e outbox | RESOLVIDO como requisito | modelo-v2.sql:1082-1110; ADR-0033:15 |
| 22 Upload e download | RESOLVIDO como requisito | ADR-0033:17 |
| 23 Segundo elemento | RESOLVIDO como pergunta ao Luiz | ADR-0035; I-19 amplia o que o segundo elemento protege |

## 2. Ataques ao desenho novo (N1 a N12)

Negaram: N1a, N1b, N1c, N1d (sem PUBLIC, sem `public`), N1f, N1g, N2a a N2i, N3a, N3b, N3d, N4a, N4b, N4d, N5a, N11b, N11c.
Passaram (detalhe na seção 14 do STRIDE): N6a, N6b (T-18); N7a (I-19); N4c (I-20); N5b, N5c, N5d (R-07); N8 (E-09, resíduo); N3c, N3e (E-10, resíduo); N9a, N9c (S-10); N9b (D-09); N10a, N10b (D-08); N11a (I-21); N11d (O3); N12 (T-19).

## 3. Objeções do Executor

- O1 ACEITA. Sessão de equipe também no banco está certa. Resíduo vira E-10: o callback valida assinatura, `iss`, `aud`, `exp`, `nonce` e MFA, e `sessao_equipe_abre` passa a receber e gravar o fator, recusando ADMIN e MEDICO sem MFA.
- O2 ACEITA para a Fase 3, com dois acréscimos: troca com confirmação no número antigo e aviso a ele; caminho de correção para paciente nascido de encaminhamento (`cadastrado_por_clinica_id` nulo hoje não tem troca possível).
- O3 ACEITA quanto a nome e CRM. Ajuste mantido: profissional sem `canal_verificado_em` e sem `usuario_id` não aparece em `profissional_ver` (N11d: 31 de 32 linhas vistas pelo paciente eram cadastros não verificados, inclusive de squatter). Teste na Fase 2.
- O4 ACEITA. Condição mantida: se a sessão for lida uma vez por transação, o resultado nunca fica em GUC ou tabela que `saas_app` escreva; senão volta o RT4.
- O5 ACEITA. Nota: a RT1d r1 executa `SELECT 1` e só confere estado; a tentativa real está na RT1a. Na regressão da Fase 2, fundir as duas.

## 4. Testes obrigatórios por fase (além da seção 12 do STRIDE)

- Fase 2 (bloqueiam o fechamento da fase): T-18 e I-19 corrigidos na migração de `paciente` e `encaminhamento`, com ADR-0029 corrigido antes; I-20 (parâmetro ligado, sem token em `pg_stat_activity` e `pg_stat_statements`); R-07 (CI recusa migração que desliga gatilho ou RLS; texto do ADR-0027 corrigido; alerta de DDL); E-10; E-09 (credencial de jobs fora do processo web, registrado no ADR-0024); I-21; ajuste de O3; regressão de N1 a N12 e RT1 a RT10; matriz de 392 sondas.
- Fase 3: T-19, O2, T-12.
- Fase 4: D-09 junto do item 20.
- Fase 5: S-10 e D-08, decisões do Luiz nos ADR-0025 e ADR-0035, testes de corrida dos limites (stride, seção 15).
