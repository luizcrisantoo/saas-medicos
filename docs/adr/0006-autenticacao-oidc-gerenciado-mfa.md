# ADR-0006: Autenticação por provedor OIDC gerenciado, com MFA para admin e médico

Status: Aceito (decisão do briefing)
Data: 2026-11-10
Tarefa: t-fase1-arquitetura

## Contexto
Senha e sessão são onde mais se erra. O briefing proíbe login feito em casa e exige MFA para admin e médico.

## Decisão
A equipe da clínica (ADMIN, RECEPCAO, MEDICO) autentica num provedor OIDC gerenciado; a aplicação só valida tokens. MFA obrigatório para ADMIN e MEDICO. Tokens de curta duração com renovação rotativa. `usuario.sub_oidc` liga o token ao Usuário. A escolha do provedor está no ADR-0007.

## Alternativas descartadas
- Login próprio com senha: contraria o briefing.
- MFA opcional para médico: o médico vê dado de saúde de vários pacientes.

## Consequências
- Limite de requisições em login e alerta de falha de login em massa (briefing, Segurança da aplicação e Operação).
- Em aberto, para o Red Team e o Luiz: como o médico que encaminha sem ser cliente (papel ENCAMINHADOR) se autentica sem "senha pra lembrar" e ainda assim com MFA. Opções levantadas: conta no provedor com passkey; ou link e código de uso único como o paciente. Decidido no ADR-0025 (desafio com código no telefone verificado do próprio médico).
- A sessão de equipe aberta após o OIDC é registrada no banco pelo papel `saas_auth` (ADR-0023, ADR-0024).

## Fontes
- docs/briefing.md: Decisões de arquitetura, Autenticação; Segurança da aplicação; Personas (médico que encaminha)
- docs/arquitetura/glossario-adicoes.md (Usuário, Papel)
