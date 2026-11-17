# ADR-0025: Autenticação do médico que encaminha sem conta

Status: Aceito na revisão da Fase 1 (rodada 1) para o desenho; verificação de titularidade do CRM é Proposto: decisão do Luiz (antes da Fase 5)
Data: 2026-11-10
Tarefa: t-fase1-arquitetura
Completa: ADR-0006 (que deixou o encaminhador em aberto)

## Contexto
O formulário de encaminhamento é gratuito e o médico que encaminha não é cliente. Na rodada 0, digitar o CRM público de outro médico montava `app.profissional_id` dele e dava acesso aos seus casos (RT5; STRIDE S-01, I-09). O Red Team exigiu posse de canal verificado do próprio médico, que digitar CRM nunca abra registro existente e que registro criado pelo formulário fique isolado até a verificação (item 4).

## Decisão
- Sessão ENCAMINHADOR só nasce por `encaminhador_confirma_codigo(desafio, codigo)`: código de 6 dígitos, validade de 10 minutos, 5 tentativas por desafio, enviado pelo papel `saas_jobs` ao telefone já cadastrado do profissional. O navegador recebe só um token de desafio; o código nunca passa pela aplicação web.
- `encaminhador_pede_codigo(crm, uf)` e `encaminhador_cadastra(...)` devolvem sempre um token no mesmo formato, exista ou não o CRM: sem oráculo de cadastro. CRM já existente no formulário de cadastro não cria nada e o token devolvido nunca confirma.
- CRM novo nasce em `profissional` sem `canal_verificado_em` e sem sessão; vira utilizável só depois de confirmar o código no telefone informado.
- Nenhum link sai ao paciente de encaminhamento cuja origem não esteja verificada (`jobs_envio_link_paciente` recusa; STRIDE S-02).
- CRM, UF, telefone e `usuario_id` do profissional não têm GRANT de escrita para a web (T-15). Troca de telefone do médico é operação auditada.
- Limite: 3 desafios por profissional por hora.

## Pergunta para o Luiz (antes da Fase 5)
Posse do telefone prova que a pessoa controla aquele número, não que é dona do CRM. Quem cadastra primeiro um CRM ainda ausente da base, com o próprio telefone, passa a "ser" aquele médico. Opções:
1. Conferência do CRM na consulta pública do CFM e revisão manual antes do primeiro envio ao paciente [SUPOSIÇÃO: o CFM oferece consulta pública por CRM e UF].
2. Aceitar o risco no piloto (rede pequena, médicos conhecidos do Rodrigo) e registrar por escrito.
3. Exigir que o primeiro cadastro de um médico venha de uma clínica cliente que o conhece.

## Alternativas descartadas
- Conta no provedor OIDC com passkey para todo encaminhador: atrito alto para quem não é cliente; fica como evolução se o ADR-0007 escolher provedor com passkey barato.
- Link mágico por e-mail: e-mail de médico costuma ser compartilhado com secretária.

## Consequências
- O aviso "contrarreferência disponível" leva ao login por desafio, nunca a link de portador (I-09).
- Auditoria registra a abertura de sessão com o desafio de origem (R-06).

## Fontes
- docs/agents/red-team-t-fase1-arquitetura.md, item 4; docs/seguranca/stride-encaminhamento.md, S-01, S-02, T-15, I-09, R-06
- docs/arquitetura/modelo-v2.sql: `desafio_encaminhador`, `encaminhador_*`, `jobs_envio_link_paciente`
- docs/arquitetura/evidencias/teste-rls-r1.log, seção r1-4; docs/seguranca/evidencias/red-team-sondas-r1.log, RT5c, RT5d, RT9b
