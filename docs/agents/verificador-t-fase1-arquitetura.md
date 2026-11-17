# Verificador: t-fase1-arquitetura (rodada 3 de 3 permitidas, 2 usadas)

Veredito: APROVADO.

## Critérios 1 a 12
1. diff-v1-v2.md: tabela dos 9 itens (seção 3) com ENTRA/MUDA; divergência agenda própria vs link externo decidida (ADR-0015; link vira leitura na Fase 9, PEDIDO até lá). OK.
2. modelo-dados-v2.md e modelo-v2.sql: execução r2 com exit 0 em PostgreSQL 16.15 limpo (modelo-v2-execucao-r2.log). OK.
3. mapa-modulos.md: 8 módulos, outbox, eventos. OK (não reauditei ciclos linha a linha).
4. maquina-estados-encaminhamento.md: T1 a T11 impostas por gatilho. OK.
5. Três diagramas: HTML e PNG presentes; os 3 finalize-summary com validate, deliver, check e browser-check em pass. OK (revisão perceptual não feita, declarado).
6. stride-encaminhamento.md: ameaças com mitigação e caso de teste. OK.
7. 36 ADRs; 0007, 0012 e 0013 com "Proposto: decisão do Luiz". OK.
8. glossario-adicoes.md existe. OK.
9. Logs conferidos por tail: RLS r2 exit 0; sondas-r2 70/70; Red Team r1 26/26; independente do Testador sem falha de ataque. OK.
10. regras-inegociaveis-check.md presente; retenção marcada como pergunta (ADR-0010). OK.
11. Nenhum .java/.jsx/.tsx/pom/package.json no repositório. Travessão: 0 em .md, .sql e .json; 31 por HTML nos diagramas, todos em comentários da biblioteca do viewer gerada pela skill (exemplo: "Default (opts.autoTheme=false) — locks..."), não em texto nosso. Aceito. [SUPOSIÇÃO] presente nas afirmações de custo; a Lei 13.787 tem fonte no Pesquisador.
12. fase1-resumo.md cobre mudanças, decisões, pendências do Luiz, aprovação do Red Team com ressalvas e critério de avanço. OK.

## Divergências decididas
- Falha latente do Testador vs aprovação do Red Team: não bloqueia. Nenhuma função cria envios CONFIRMACAO ou LEMBRETE hoje. Fica como gate da Fase 2 (já no resumo, seção 5).
- T-19: fica na Fase 3 (Red Team r2 e STRIDE seção 12), mas o gate vale antes da migração de agendamento com tela. O resumo o lista entre os gates da Fase 2 com nota de divergência. Ressalva leve: harmonizar o rótulo na Fase 2.

## Ressalvas
Aprovação do Red Team é "com ressalvas" e vira veto se os gates da Fase 2 saírem sem correção. Decisões do Luiz (auth, nuvem, teto de custo) bloqueiam a Fase 2.
