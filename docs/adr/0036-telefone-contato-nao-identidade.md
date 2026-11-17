# ADR-0036: Telefone é contato, não identidade do paciente

Status: Aceito na revisão da Fase 1 (rodada 2), sujeito ao Red Team
Data: 2026-11-10
Tarefa: t-fase1-arquitetura
Substitui: o critério de deduplicação do ADR-0029, item 2 (o escopo da busca continua o mesmo)

## Contexto
Na rodada 1, sem CPF, a deduplicação usava só o telefone. O Red Team provou que mãe e filho, ou avó e neto, com o telefone da família viram o MESMO paciente: o caso urgente do filho cai no registro da mãe, e o nome digitado para o neto é descartado (T-18 CRÍTICO; sondas N6a e N6b em `red-team-sondas-r1-novas.log`). No Brasil um único celular por família é comum, sobretudo com idosos e crianças [SUPOSIÇÃO: sem número oficial levantado nesta fase]. O briefing pede link sem atrito para o paciente; exigir CPF do idoso no fluxo do link derruba a taxa de chegada que o produto mede.

## Decisão
1. Telefone é canal de contato. Vários pacientes podem ter o mesmo telefone; o link e o código vão ao telefone do PACIENTE do encaminhamento, e a sessão aberta vale só para aquele caso (ADR-0023, rodada 2), então compartilhar o aparelho não abre o caso de outro membro da família.
2. Critério de "mesma pessoa" (função `mesma_pessoa` em `modelo-v2.sql`), aplicado só dentro do escopo já definido no ADR-0029 (pacientes ligados ao ator):
   - (a) HMAC do CPF igual, quando o CPF foi informado; ou
   - (b) nome normalizado (sem diferença de caixa e de espaços) E data de nascimento E telefone iguais, desde que os dois registros não tenham CPF diferente.
3. Sem CPF e sem data de nascimento: nunca deduplica. Nasce registro novo.
4. CPF do paciente continua opcional no fluxo do link e no encaminhamento (sonda R2-4f). A data de nascimento é o dado pedido ao médico que encaminha para permitir reaproveitar o cadastro; sem ela, o custo é uma duplicata, não uma fusão errada.
5. Nunca há fusão automática por similaridade. Juntar duplicatas é ação humana: na recepção com o paciente presente ou por código confirmado pelo próprio paciente (Fase 3 e Fase 5, auditado).

## Alternativas descartadas
- Telefone sozinho (rodada 1): funde pessoas diferentes e mistura dado de saúde (T-18).
- CPF obrigatório: atrito no link do idoso e do menor sem CPF à mão; o briefing coloca a taxa de chegada como métrica principal.
- Nome + telefone sem data de nascimento: homônimos na mesma casa (pai e filho "Júnior") se fundem.
- Similaridade de nome (trigram, fonética): erro silencioso em dado de saúde; duplicata é recuperável, fusão errada não.

## Consequências
- Mais duplicatas quando faltar data de nascimento; a recepção resolve na Fase 3 (tela de possíveis duplicatas, só dentro da própria clínica).
- O mesmo telefone pode receber links de casos de pessoas diferentes: a mensagem não traz dado clínico (briefing) e cada link abre só o seu caso.
- Limites de pedido de código continuam por paciente e por link; teto por telefone de destino entra com D-09 na Fase 4.
- Provas: `sondas-r2.log`, R2-4a a R2-4i; `red-team-sondas-r1-novas-r2.log`, N6a e N6b NEGADO.

## Fontes
- docs/agents/red-team-t-fase1-arquitetura-r1.md, T-18 (N6a, N6b) e item 8
- docs/briefing.md: Glossário (Paciente), Métricas (taxa de chegada), Regras inegociáveis
- docs/adr/0017-cpf-hash-sem-unique.md, docs/adr/0029-identidade-paciente-global.md
