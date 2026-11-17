# Registro de decisões (ADR)

Regra do briefing (Definição de pronto, Registro de decisões): toda decisão de arquitetura ou segurança vira um arquivo curto nesta pasta (contexto, decisão, alternativas descartadas, consequências). Antes de rediscutir algo, consultar os ADRs existentes. Uma decisão registrada só muda com um ADR novo que substitui o antigo.

Status usados:
- Aceito (decisão do briefing): está na tabela "Decisões de arquitetura" ou em "Mudanças na arquitetura do Arquify" do briefing.
- Aceito na revisão da Fase 1, sujeito ao Avaliador: decisão nova desta revisão.
- Proposto: decisão do Luiz: pergunta em aberto do briefing; o Orquestrador não decide.

| ADR | Título | Status |
|---|---|---|
| [ADR-0001](0001-monolito-modular-spring-modulith.md) | Monolito modular com Spring Modulith | Aceito (decisão do briefing) |
| [ADR-0002](0002-eventos-dominio-outbox.md) | Eventos de domínio com registro persistente (outbox) | Aceito (decisão do briefing) |
| [ADR-0003](0003-postgresql-gerenciado-flyway.md) | Um PostgreSQL gerenciado com migrações Flyway | Aceito (decisão do briefing) |
| [ADR-0004](0004-multi-tenant-rls.md) | Multi-tenant com schema compartilhado, clinica_id e Row-Level Security | Aceito (decisão do briefing) |
| [ADR-0005](0005-uuid-identificadores.md) | UUID em todo identificador exposto | Aceito (decisão do briefing) |
| [ADR-0006](0006-autenticacao-oidc-gerenciado-mfa.md) | Autenticação por provedor OIDC gerenciado, com MFA para admin e médico | Aceito (decisão do briefing) |
| [ADR-0007](0007-provedor-autenticacao.md) | Escolha do provedor de autenticação | Aceito: AWS Cognito |
| [ADR-0008](0008-paciente-sem-senha-codigo.md) | Paciente sem senha: link de uso único e código pelo WhatsApp | Aceito (decisão do briefing) |
| [ADR-0009](0009-autorizacao-centralizada.md) | Autorização centralizada, nega por padrão | Aceito (decisão do briefing) |
| [ADR-0010](0010-arquivos-bucket-privado.md) | Arquivos em bucket privado criptografado com URL assinada curta | Aceito (decisão do briefing) |
| [ADR-0011](0011-hospedagem-regiao-brasil.md) | Hospedagem em nuvem com região no Brasil e serviços gerenciados | Aceito (decisão do briefing) |
| [ADR-0012](0012-escolha-nuvem.md) | Escolha da nuvem e dos serviços gerenciados | Aceito: AWS sa-east-1 |
| [ADR-0013](0013-teto-custo-piloto.md) | Teto de custo mensal do piloto | Aceito: até R$ 800/mês |
| [ADR-0014](0014-ambientes.md) | Ambientes de desenvolvimento, homologação e produção | Aceito (decisão do briefing) |
| [ADR-0015](0015-agenda-propria-nucleo.md) | Agenda própria como núcleo; link do sistema externo sai até a integração da Camada 3 | Aceito na revisão da Fase 1, sujeito ao Avaliador |
| [ADR-0016](0016-papel-em-usuario-clinica.md) | Papel de acesso em usuario_clinica, não em profissional_clinica | Aceito na revisão da Fase 1, sujeito ao Avaliador |
| [ADR-0017](0017-cpf-hash-sem-unique.md) | Sem UNIQUE no hash do CPF do paciente | Aceito na revisão da Fase 1, sujeito ao Avaliador |
| [ADR-0018](0018-plano-b-mensagens.md) | Plano B de mensagens por SMS ou e-mail | Aceito (decisão do briefing) |
| [ADR-0019](0019-feature-flags-por-clinica.md) | Feature flags por clínica | Aceito (decisão do briefing) |
| [ADR-0020](0020-eventos-sem-dado-clinico.md) | Eventos de domínio carregam só ids | Aceito na revisão da Fase 1, sujeito ao Avaliador |
| [ADR-0021](0021-ia-e-base-conhecimento-fora.md) | Motor de IA e Base de conhecimento do v1 saem até a Fase 8 | Aceito (decisão do briefing) |
| [ADR-0022](0022-destino-ve-caso-com-consentimento.md) | Clínica destino só vê o caso com consentimento COMPARTILHAR_CASO ativo | Aceito na revisão da Fase 1, sujeito ao Avaliador |
| [ADR-0023](0023-sessao-verificavel-por-ator.md) | Sessão verificável no banco para todo ator | Aceito na revisão da Fase 1 (rodada 1), sujeito ao Red Team |
| [ADR-0024](0024-papeis-banco-web-jobs.md) | Papéis de banco separados para web, jobs e login; jobs só por funções estreitas (substitui D2) | Aceito na revisão da Fase 1 (rodada 1), sujeito ao Red Team |
| [ADR-0025](0025-autenticacao-medico-encaminhador.md) | Autenticação do médico que encaminha sem conta | Aceito (desenho); titularidade do CRM: Proposto: decisão do Luiz |
| [ADR-0026](0026-protecao-de-dados.md) | Proteção de dados (cifra na aplicação, chaves, logs e links) | Aceito na revisão da Fase 1 (rodada 1) |
| [ADR-0027](0027-transicoes-e-historico-por-gatilho.md) | Transições de status e histórico impostos por gatilho (substitui D7) | Aceito (rodada 1); texto corrigido e mitigação R-07 na rodada 2 |
| [ADR-0028](0028-enumeracoes-text-check.md) | Enumerações como text com CHECK (D8) | Aceito na revisão da Fase 1 (rodada 1) |
| [ADR-0029](0029-identidade-paciente-global.md) | Identidade do paciente global: deduplicação, vínculo e telefone | Aceito (rodada 1); critério de deduplicação substituído pelo ADR-0036 |
| [ADR-0030](0030-link-e-codigo-do-paciente.md) | Link e código do paciente: tamanho, validade e limites | Aceito na revisão da Fase 1 (rodada 1), sujeito ao Red Team |
| [ADR-0031](0031-vagas-agenda-nativa-fase6.md) | Modos VAGAS e AGENDA_NATIVA adiados para a Fase 6 | Aceito na revisão da Fase 1 (rodada 1) |
| [ADR-0032](0032-eventos-com-consumidor.md) | Só publicar evento com consumidor; uma confirmação por agendamento | Aceito na revisão da Fase 1 (rodada 1) |
| [ADR-0033](0033-requisitos-antes-fases-4-e-5.md) | Requisitos de segurança obrigatórios antes das Fases 4 e 5 | Aceito como requisito |
| [ADR-0034](0034-registro-envio-notificacao.md) | Registro de envio de notificação sem corpo da mensagem | Aceito na revisão da Fase 1 (rodada 1) |
| [ADR-0035](0035-segundo-elemento-paciente.md) | Segundo elemento antes de mostrar dado clínico ao paciente | Proposto: decisão do Luiz |
| [ADR-0036](0036-telefone-contato-nao-identidade.md) | Telefone é contato, não identidade do paciente (critério de deduplicação) | Aceito na revisão da Fase 1 (rodada 2), sujeito ao Red Team |
| [ADR-0037](0037-paciente-menor-responsavel.md) | Paciente menor com cadastro próprio ligado a responsável | Aceito |
| [ADR-0038](0038-gates-identidade-fase2.md) | CPF só identifica com nome e nascimento; telefone de contato do caso; vínculo revogado não serve à recepção (substitui o item 2a do ADR-0036) | Proposto (Fase 2, F3), sujeito ao Red Team |
| [ADR-0039](0039-gates-banco-fase2.md) | Alerta de DDL pela tabela alvo; funções sem sessão; diretório sem cadastro não verificado; envios derrubados no cancelamento; alerta de volume de preparo | Proposto (Fase 2, F4), sujeito ao Red Team |
