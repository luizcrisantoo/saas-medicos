# ADR-0030: Link e código do paciente: tamanho, validade e limites

Status: Aceito na revisão da Fase 1 (rodada 1), sujeito ao Red Team
Data: 2026-11-10
Tarefa: t-fase1-arquitetura
Completa: ADR-0008

## Contexto
Na rodada 0 o contexto PUBLICO_LINK reescrevia o próprio link (zerava tentativas, trocava código, estendia validade: RT2), dois links podiam ficar ativos e o limite de tentativas era por link, zerado a cada reemissão (Red Team item 13; T-05, T-16, D-03, D-04).

## Decisão
- Token do link: 64 caracteres hexadecimais (dois `gen_random_uuid`, 244 bits aleatórios); banco guarda `sha256`. Validade de 3 dias, teto de 7 por CHECK.
- Código: 6 dígitos, validade de 10 minutos, gerado pelo `saas_jobs` no envio; banco guarda `sha256(link_id:codigo)`.
- Um link ativo por encaminhamento (índice único parcial); reemitir revoga o anterior.
- Tentativas: 10 por link, 10 somadas por encaminhamento (inclui links revogados), 20 por paciente em 24 horas. Reemitir não zera.
- Pedidos de código: 3 por link e 5 por paciente por hora.
- O papel web não tem privilégio em `link_paciente`: só `link_consulta` (não consome), `paciente_pede_codigo` e `paciente_confirma_codigo`. Gatilho recusa mudar hash, dono e validade, diminuir tentativas ou desfazer uso e revogação.
- Link só vale com encaminhamento aberto (rodada 2, Testador F1): `link_consulta`, `paciente_pede_codigo` e `paciente_confirma_codigo` recusam link de encaminhamento CANCELADO, EXPIRADO ou CONTRARREFERIDO; a transição para esses estados revoga todo link ativo e marca FALHOU todo envio PENDENTE de link ou código; `jobs_envio_prepara` relê o encaminhamento e não entrega token, código nem telefone fora de CRIADO ou ENVIADO_AO_PACIENTE (link) ou de estado aberto (código). Provas: `sondas-r2.log`, R2-1a a R2-1n; `teste-r1-independente-r2.log`, J-link.
- A sessão aberta pelo link vale só para o caso daquele link (ADR-0023, rodada 2).
- Mensagem de entrada pelo WhatsApp nunca autentica, consente nem muda status (registrado aqui e no ADR-0033).

## Alternativas descartadas
- Código de 4 dígitos: 10 tentativas cobrem 0,1% do espaço, contra 0,001% com 6 dígitos.
- Limite só por IP: o atacante troca de IP; o limite precisa estar no recurso.

## Consequências
- Limite por IP continua na borda (briefing, Segurança da aplicação), em adição a estes.
- Provas: `teste-rls-r1.log` r1-13; `red-team-sondas-r1.log` RT2a, RT2b.

## Fontes
- docs/agents/red-team-t-fase1-arquitetura.md, item 13; docs/seguranca/stride-encaminhamento.md, T-05, T-16, D-03, D-04
- docs/arquitetura/modelo-v2.sql: `link_paciente`, `paciente_*`, `jobs_envio_prepara`
