# Fonte: Claude Doc https://claude.ai/artifact/CL7oYBzSt97poynDyMkZVt (rev 27, lido em 2026-11-10). Texto extraído sem formatação de tabelas: linhas consecutivas de tabela = células.

Briefing: Agenda + Rede de Encaminhamento
 · 
Como usar este briefing
Este é o briefing pro chat do SaaS de agendamento. Cole o documento inteiro lá e peça: "
Usando o time de agentes descrito abaixo, r
evise a arquitetura do Arquify com base neste briefing e siga a linha do tempo a partir da Fase 1."
A agenda continua sendo o núcleo do produto. A rede de encaminhamento é a camada que vem por cima dela. O código da rede só vem depois, mas a arquitetura precisa nascer preparada pra ela, senão vira retrabalho.
Contexto que o chat já deve ter:
Stack: Java 21 com Spring Boot no back-end, React com TypeScript no front-end.
Piloto: as clínicas do Rodrigo (ortopedia), no Recife.
O MVP atual cobre agendamento e painel da recepção, com notificações via Google Calendar.
A arquitetura inicial foi desenhada no Arquify e deve ser reaproveitada, não refeita do zero.
Como trabalhar: o time de agentes
Toda entrega deste projeto passa pelo fluxo de orquestração do Luiz, dentro do Claude Code, seguindo o GSD (Discutir, Planejar, Executar, Verificar). Nada é entregue sem consenso entre os papéis, com no máximo 3 rodadas de revisão por entrega pra não gastar tokens à toa.
Papel
O que faz neste projeto
Orquestrador
Recebe o pedido, quebra em tarefas pequenas da fase atual, distribui e fecha o consenso. Aciona o Claude Design quando houver tela nova.
Pesquisador
Checa regras antes de decidir: LGPD, ética médica do CFM, documentação do Spring, da API do WhatsApp e do provedor de autenticação.
Executor
Escreve o código, um commit por tarefa.
Avaliador
Revisa contra este briefing: fronteiras de módulo, modelo de dados, regras inegociáveis, simplicidade.
Testador
Escreve e roda os testes, incluindo isolamento entre clínicas e matriz de autorização.
Red Team
Ataca a entrega como um invasor: acessar dado de outra clínica, adivinhar IDs, reusar link de paciente, injetar dados, abusar de limites, vazar dado em log.
Painel de Personas
Testa a usabilidade com perfis reais do negócio: secretária com pressa, médico de 60 anos encaminhando, paciente idoso no WhatsApp.
Verificador
Confere se o critério da fase foi cumprido antes de liberar a próxima.
Regras do fluxo neste projeto
O Red Team tem poder de veto em qualquer mudança que mexa em autenticação, autorização, isolamento de tenant, arquivos, links de paciente ou dados de saúde. Sem a aprovação dele, não entra.
Na Fase 1, o Red Team conduz a modelagem de ameaças (STRIDE) do fluxo de encaminhamento, e o resultado vira a lista de ataques testados nas fases seguintes.
O Painel de Personas entra em toda entrega com tela, a partir da Fase 3.
Quando os papéis não chegarem a consenso em 3 rodadas, o Orquestrador para e pergunta ao Luiz, com as opções e o risco de cada uma.
Definição de pronto e registro de decisões
Uma tarefa só está pronta quando cumpre todos os itens abaixo. O Verificador confere antes de fechar.
Testes escritos e passando, incluindo os de isolamento e autorização quando a tarefa mexe em dados.
Aprovada pelo Red Team, se tocar em autenticação, autorização, tenant, arquivos, links de paciente ou dado de saúde.
Migração de banco com caminho de reversão testado.
Nenhum dado pessoal em log, mensagem de erro ou resposta de API que não precise dele.
Atrás de feature flag, se for funcionalidade nova da rede.
Documentação e glossário atualizados quando a tarefa cria um conceito novo.
Registro de decisões (ADR).
 Toda decisão de arquitetura ou segurança vira um arquivo curto na pasta docs/adr do repositório: contexto, decisão, alternativas descartadas e consequências. Antes de rediscutir algo, o Orquestrador consulta os ADRs existentes. Uma decisão registrada só muda com um ADR novo que substitui o antigo.
Personas do Painel
O Painel de Personas testa toda tela com estes quatro perfis. São perfis do negócio real, não genéricos.
Persona
Quem é
O que precisa funcionar
O que faz desistir
Secretária
Recepção de clínica de ortopedia, atende telefone e balcão ao mesmo tempo
Confirmar um pedido de encaminhamento em 1 clique, achar paciente pelo nome ou telefone
Mais cliques que a planilha, tela que trava, cadastro duplicado
Médico que encaminha
Clínico de 60 anos, pouco paciente com tecnologia, usa mais o celular
Encaminhar em 30 segundos, sem criar conta complicada
Formulário longo, senha pra lembrar, não saber se o paciente chegou
Paciente
Senhora de 70 anos, só usa WhatsApp
Abrir o link, entender pra onde vai e marcar sem ajuda
Letra pequena, termo técnico, ter que baixar app ou criar senha
Admin da clínica
Dono ou gerente, olha resultado no fim do mês
Ver quantos pacientes a rede trouxe e quanto isso rendeu
Número que não bate com a realidade da recepção
Regras de acessibilidade derivadas das personas:
 letra grande e alto contraste nas telas do paciente, linguagem sem termo técnico, fluxo do paciente em no máximo 3 telas, e tudo funcionando bem no celular antes do computador.
Glossário
Os mesmos nomes valem no código, no banco, na tela e nas conversas com os agentes. Termo novo entra aqui antes de entrar no código.
Termo
Significado
No código
Clínica
O cliente que paga e o tenant do sistema
Clinica
Profissional
Médico com CRM, cliente ou não
Profissional
Vínculo
A relação de um profissional com uma clínica onde atende
ProfissionalClinica
Encaminhamento
O pedido de um profissional pra que o paciente seja atendido por outra especialidade
Encaminhamento
Origem
Quem encaminhou
profissionalOrigem
Destino
Clínica ou profissional que recebe
clinicaDestino, profissionalDestino
Contrarreferência
O retorno de quem atendeu pra quem encaminhou
Contrarreferencia
Modo de recebimento
Como a clínica aceita encaminhamentos: pedido, vagas reservadas ou agenda nativa
ModoRecebimento
Vaga de encaminhamento
Horário reservado só pra pacientes encaminhados
VagaEncaminhamento
Taxa de chegada
Encaminhamentos que viraram consulta realizada, dividido pelo total de encaminhamentos
métrica
O negócio
Uma agenda multi-clínica que traz pacientes: médicos da rede encaminham pacientes direto pros horários livres de especialistas, e quem encaminhou recebe o retorno do atendimento.
O problema.
 Hoje o encaminhamento é um papel escrito "procurar ortopedista". O paciente se perde, o especialista recebe sem exames nem motivo, e quem encaminhou nunca sabe o que aconteceu. Nos EUA, mais de 50% dos pacientes encaminhados nunca chegam ao especialista. A Tennr resolveu isso por lá e chegou a US$ 605 milhões de valuation (
Fierce Healthcare
).
A estratégia.
 Venha pela ferramenta, fique pela rede. A agenda traz a clínica, porque resolve um problema desde o primeiro dia. A rede segura a clínica, porque sair significa perder os pacientes que ela recebe.
Ator
Por que entra
Paga?
Clínica ou especialista que recebe
Ganha paciente novo sem anúncio, e o paciente chega com exames e motivo
Sim, mensalidade
Médico que encaminha
Sabe o que aconteceu com o paciente e mantém o vínculo; leva 30 segundos
Não
Paciente
Marca na hora pelo WhatsApp, sem procurar especialista no Google
Não
Secretária
Menos ligação, paciente já chega cadastrado
Não
Receita.
 Só a clínica que recebe paga, numa mensalidade fixa. Nunca cobrar por paciente recebido e nunca beneficiar quem encaminha (ver Regras inegociáveis).
Onde começa.
 Recife, polo médico, uma especialidade só: ortopedia nas clínicas do Rodrigo recebendo, e a rede de médicos do pai do Luiz encaminhando.
O produto em camadas
São três camadas, construídas nessa ordem. Cada uma funciona sozinha antes da próxima começar.
Camada 1: Agenda (o núcleo, MVP atual)
Cadastro multi-clínica: cada clínica com seus médicos, dias e horários.
Marcação pelo site e pelo WhatsApp.
Painel da recepção.
Lembretes e confirmação pra reduzir falta.
Camada 2: Rede de encaminhamento (o diferencial)
Botão "encaminhar": motivo, urgência, especialidade e exames anexados, em 30 segundos.
O médico que encaminha não precisa ser cliente: usa um formulário web gratuito.
O paciente recebe um link no WhatsApp e escolhe o especialista e o horário.
Três modos de recebimento por clínica:
Pedido: o paciente escolhe uma preferência e a secretária confirma o horário.
Vagas reservadas: a clínica separa alguns horários por semana só pra encaminhados.
Agenda nativa: a clínica usa a agenda da Camada 1 e o paciente vê os horários reais.
Resumo do caso pro especialista que recebe.
Contrarreferência: quem encaminhou recebe "paciente atendido, conduta X".
Painel da clínica: quantos pacientes a rede trouxe.
Camada 3: IA e integrações (depois)
Resumo de consulta por áudio que alimenta o resumo do caso e a contrarreferência.
Leitura de horários de clínicas que usam outros sistemas (Google Agenda ou APIs de parceiros).
Mudanças na arquitetura do Arquify
A rede não precisa ser codada agora, mas o modelo de dados precisa já conhecer estes conceitos. Peça ao chat pra comparar o desenho atual do Arquify com esta lista e apontar o que muda.
1. Identidade global, vínculo por clínica.
 O tenant continua sendo a clínica, mas paciente e médico não podem ficar presos dentro de um tenant só. O mesmo paciente passa por várias clínicas, e o médico atende em várias e encaminha pra outras. Separe a pessoa global do vínculo dela com cada clínica.
2. Entidades novas ou alteradas
Entidade
O que é
Campos principais
Profissional
Médico global, cliente ou não
CRM e UF, especialidades, contato
ProfissionalClinica
Vínculo do médico com uma clínica
Profissional, clínica, agenda, papel
Paciente
Pessoa global
Dados pessoais, telefone, consentimentos
Consentimento
Autorização LGPD do paciente
Finalidade, data, texto aceito, revogação
Clinica
O tenant
Dados, especialidades, modo de recebimento (PEDIDO, VAGAS, AGENDA_NATIVA)
Agendamento
Já existe; ganha campos
Origem (site, WhatsApp, recepção, encaminhamento), encaminhamentoId opcional
Encaminhamento
O pedido de um médico pra outro
Origem, paciente, especialidade destino, clínica ou médico destino opcional, motivo, urgência, status
AnexoEncaminhamento
Exames anexados
Arquivo em storage criptografado, tipo, data
Contrarreferencia
O retorno pra quem encaminhou
Encaminhamento, autor, conduta, data
VagaEncaminhamento
Horário reservado pra encaminhados
Clínica, profissional, início, fim, liberação automática
EventoAuditoria
Registro de acesso a dado de saúde
Quem, o quê, quando, de onde
3. Status do encaminhamento como máquina de estados.
 Criado, enviado ao paciente, solicitado, agendado, atendido, contrarreferido, expirado, cancelado. Toda mudança de status gera um registro com data e autor.
4. Módulo único de notificações.
 WhatsApp e e-mail com templates e fila assíncrona. Serve aos lembretes da agenda e aos avisos da rede. Não espalhe envio de mensagem pelo código.
5. Permissões.
 Papéis por clínica (admin, recepção, médico). Um encaminhamento só é visível pra quem encaminhou, pra clínica destino e pro paciente.
6. Monolito modular, não microsserviços.
 Um projeto Spring com 
Spring Modulith e 
módulos bem separados: identidade, clínicas, agenda, pacientes, encaminhamentos, notificações, arquivos, auditoria.
7. Eventos internos ligando agenda e rede.
 Exemplos: AgendamentoCriado, ConsultaRealizada, EncaminhamentoAgendado. A rede reage a eventos da agenda em vez de chamar o código dela direto, o que mantém os módulos desacoplados.
8. Feature flags por clínica.
 Cada funcionalidade nova da rede nasce desligada e é ligada clínica por clínica. Assim o piloto com o Rodrigo testa tudo sem expor nada pras outras clínicas, e uma falha se desliga sem novo deploy.
9. Plano B de mensagens.
 O módulo de notificações não pode depender só do WhatsApp. Se a API cair ou o número for bloqueado, os avisos críticos (confirmação, link de encaminhamento) saem por SMS ou e-mail.
Arquitetura e segurança: o cenário ideal
O critério de todas as escolhas: o produto guarda dado de saúde de pacientes de várias clínicas e é construído por uma pessoa só. Então vale o que reduz risco de vazamento e reduz trabalho de operação, nessa ordem. A meta de segurança é o 
OWASP ASVS
 nível 2.
Decisões de arquitetura
Área
Decisão
Por quê
Estilo
Monolito modular com Spring Modulith
Fronteiras entre módulos verificadas em teste, sem o custo de operar microsserviços
Eventos
Eventos de domínio com registro persistente (padrão outbox)
Notificação e encaminhamento não se perdem se o sistema cair no meio
Banco
Um PostgreSQL gerenciado, migrações com Flyway
Uma fonte de verdade, backup automático, histórico de schema versionado
Multi-tenant
Schema compartilhado com tenant_id, mais Row-Level Security do Postgres
Duas barreiras: se o código esquecer um filtro, o banco ainda bloqueia
Identificadores
UUID em tudo que aparece em URL ou API
Impede adivinhar IDs de outros pacientes
Autenticação
Provedor OIDC gerenciado, nunca login feito em casa; MFA obrigatório pra admin e médico
Senha e sessão são onde mais se erra; quem faz isso o dia todo erra menos
Paciente
Sem senha: código de uso único pelo WhatsApp
Paciente idoso não cria conta, e não existe senha pra vazar
Autorização
Papéis por clínica mais regra por relacionamento no encaminhamento, centralizadas num único serviço, nega por padrão
Uma regra espalhada por vários controllers é onde nasce o vazamento entre clínicas
Arquivos
Bucket privado, criptografado, acesso só por URL assinada de poucos minutos, validação de tipo e tamanho, varredura de vírus
Exame anexado é o dado mais sensível do sistema
Hospedagem
Nuvem com região no Brasil, serviços gerenciados (banco, storage, segredos)
Facilita a conversa de LGPD e tira operação das suas costas
Ambientes
Desenvolvimento, homologação e produção; homologação só com dado fictício
Dado real de paciente nunca sai de produção
Proteção de dados
Criptografia em trânsito (TLS) e em repouso em tudo.
Campos mais sensíveis (CPF, motivo do encaminhamento, conduta) com criptografia no nível da aplicação, chaves num serviço de gerenciamento de chaves.
Logs sem dado pessoal: mascarar CPF, telefone e texto clínico antes de logar.
Auditoria só de inclusão, sem update nem delete, registrando todo acesso a dado de saúde.
Links pro paciente assinados, de uso único, com expiração, e confirmação por código antes de mostrar qualquer dado clínico.
Segurança da aplicação
Limite de requisições por IP e por usuário, principalmente em login, código de uso único e links de paciente.
Tokens de curta duração com renovação rotativa.
CORS restrito, cabeçalhos de segurança e Content Security Policy no front-end.
Validação de assinatura em todo webhook recebido (WhatsApp, pagamento).
Idempotência em agendamento e envio de mensagem, pra clique duplo não marcar duas vezes.
Pipeline e cadeia de suprimentos
Branch principal protegida: só entra código por pull request com todas as verificações passando.
A cada pull request: testes, análise estática de segurança, varredura de dependências vulneráveis e de segredos no código.
Antes de cada release: varredura dinâmica (OWASP ZAP) em homologação.
Segredos só no gerenciador de segredos da nuvem, nunca no repositório.
Testes que não podem faltar
Testes de integração com Postgres real via Testcontainers, incluindo as políticas de RLS.
Teste de isolamento: um usuário da clínica A tenta ler, editar e listar dados da clínica B em todos os endpoints, e tem que falhar.
Matriz de autorização: cada endpoint testado com cada papel.
Teste das fronteiras de módulo pelo Spring Modulith.
Operação e resposta a incidente
Backup automático com recuperação a um ponto no tempo, e restauração testada de verdade a cada trimestre.
Monitoramento de erros com remoção de dado pessoal, alertas de falha de login em massa e de acesso fora do padrão.
Plano de incidente escrito antes do lançamento: quem avisa as clínicas, como comunicar a ANPD e os titulares.
LGPD na prática
Mapa de dados: o que se coleta, por quê, onde fica e por quanto tempo.
Contrato de tratamento de dados com cada clínica. Na rede, o papel de cada parte (controlador ou operador) precisa ser definido com o advogado.
Canal do encarregado de dados e rotina pra atender pedido de acesso, correção e exclusão.
Modelagem de ameaças.
 Na Fase 1, antes de codar, fazer um STRIDE do fluxo de encaminhamento: quem pode se passar por quem, o que pode vazar, o que pode ser adulterado. O resultado vira lista de testes do Red Team.
Linha do tempo
A ordem segue uma regra: primeiro o que é caro de mudar depois (dados, segurança, tenant), por último o que é fácil de trocar (IA, integrações). Cada fase só começa quando o critério da anterior for cumprido.
Arquitetura (concluída, revisar agora)
Aplicar as mudanças da seção anterior ao desenho do Arquify.
Entregáveis: modelo de dados v2, mapa de módulos
, máquina de estados do encaminhamento, modelagem de ameaças feita pelo Red Team e as decisões da seção de arquitetura e segurança registradas
.
Critério pra avançar: arquitetura revisada antes de qualquer código novo.
Fundação técnica
Repositório
 com branch protegida, ambientes de desenvolvimento, homologação e produção, CI com varreduras de segurança
, migrações de banco versionadas.
Provedor de autenticação com MFA, papéis por clínica, isolamento de tenant com RLS, auditoria, storage criptografado, gerenciador de segredos
.
Base LGPD: consentimento, termos de uso e política de privacidade.
Por que antes da agenda: segurança e tenant enxertados depois quebram tudo que já existe.
Agenda núcleo (MVP do Rodrigo)
Clínicas, profissionais, horários, agendamento, painel da recepção, marcação pelo site
, importação dos pacientes e da agenda atuais do Rodrigo
.
Critério pra avançar: clínicas do Rodrigo usando em produção por 2 a 4 semanas, sem planilha paralela.
Notificações
API oficial do WhatsApp, lembretes, confirmação de presença.
Por que antes da rede: o encaminhamento inteiro depende de mandar link e aviso pro paciente.
Encaminhamento v1 (modo pedido)
Formulário web pro médico que encaminha, link pro paciente, confirmação pela secretária, contrarreferência simples
, tudo atrás de feature flag e com eventos que medem a taxa de chegada desde o primeiro encaminhamento
.
Antes de lançar: consulta com advogado de direito médico.
Critério pra avançar: 5 a 10 médicos encaminhando e a taxa de chegada medida.
Encaminhamento v2
Vagas reservadas, agenda nativa em tempo real, painel de conversão da clínica.
Monetização e expansão
Planos, cobrança recorrente, cadastro self-service de clínicas.
Segunda especialidade ou segundo bairro só depois de provar ortopedia.
IA
Resumo de consulta por áudio, resumo automático do caso e contrarreferência gerada.
Integrações externas
Google Agenda de clínicas externas e APIs de outros sistemas, quando uma clínica grande pedir.
Regras inegociáveis
Estas regras valem pra todas as fases e não entram em discussão de prazo.
Ética médica
Nunca pagar, dar desconto ou qualquer vantagem a quem encaminha. O Código de Ética Médica proíbe o médico de obter vantagem por encaminhar paciente.
Nunca cobrar da clínica por paciente recebido. Só mensalidade fixa.
O paciente é sempre livre pra escolher outro especialista, dentro ou fora da rede.
LGPD (dado de saúde é dado sensível)
Consentimento explícito do paciente pra compartilhar o caso com a clínica destino.
Acesso mínimo: só quem participa do encaminhamento vê os dados dele.
Todo acesso a dado de saúde fica registrado na auditoria.
Prazo de retenção definido pra anexos e dados de encaminhamento.
Segurança
Anexos sempre em storage criptografado.
Nenhum dado clínico no corpo da mensagem de WhatsApp: só um link autenticado e com prazo de expiração.
Build in public no Instagram
Nunca mostrar tela com dado real de paciente, médico ou clínica. Gravações só em homologação, com dado fictício.
Nunca mostrar chave, token, arquivo de configuração, painel da nuvem ou URL de produção e de homologação.
Antes de publicar, revisar cada print e cada trecho de vídeo procurando esses itens, incluindo abas do navegador e notificações na tela.
Falar de decisões e aprendizados, não de detalhes que ajudem alguém a atacar o sistema (por exemplo, nunca o formato dos links de paciente).
Métricas de validação
O número que prova o negócio é a taxa de chegada: de cada 10 pacientes encaminhados, quantos viraram consulta. Meça a linha de base antes do sistema (perguntando à recepção do Rodrigo) e compare depois.
Fase
Métrica
Sinal pra avançar
Agenda
Agendamentos feitos pelo sistema
100% por 2 semanas, sem planilha paralela
Notificações
Taxa de falta
Menor que a de antes do sistema
Encaminhamento v1
Taxa de chegada
Claramente acima da linha de base
Encaminhamento v1
Tempo do encaminhamento até o agendamento
Medido em dias, não semanas
Encaminhamento v1
Encaminhamentos com contrarreferência
A maioria
Encaminhamento v1
Médicos encaminhando todo mês
5 a 10 ativos
As metas exatas ficam em aberto até a linha de base ser medida.
Perguntas em aberto
Estas decisões ainda não foram tomadas. O Orquestrador não decide nenhuma delas sozinho: o Pesquisador levanta as opções e o Luiz decide.
Provedor de autenticação:
 comparar custo por usuário, suporte a MFA e a código de uso único, e esforço de operação. Decidir na Fase 1.
Hospedagem:
 qual nuvem e quais serviços gerenciados, com região no Brasil. Decidir na Fase 1.
Teto de custo mensal do piloto:
 o Luiz define um valor máximo pra infraestrutura e WhatsApp somados. Os agentes escolhem a solução mais simples que caiba nele. Decidir na Fase 1.
Migração dos dados do Rodrigo:
 de onde vêm os pacientes e a agenda atual (planilha, outro sistema, papel) e como entram sem recadastro manual. Decidir antes da Fase 3.
Papéis na LGPD:
 quem é controlador e quem é operador na rede de encaminhamento. Com o advogado, antes da Fase 5.
Termos de uso e contrato com a clínica:
 responsabilidades, disponibilidade prometida, suporte. Antes da Fase 7.
Preço:
 valor da mensalidade e como varia (por clínica ou por especialista). Antes da Fase 7.
Nome do produto e domínio:
 antes do primeiro material público.
Fora do escopo por agora
Nada disto entra antes da fase indicada na linha do tempo, mesmo que pareça rápido de fazer:
Microsserviços e infraestrutura complexa.
App nativo (iOS e Android): web responsiva e WhatsApp bastam.
Prontuário eletrônico completo e telemedicina.
IA antes da Fase 8.
Integrações com outros sistemas de clínica antes da Fase 9.
Outras especialidades antes de provar ortopedia.
Qualquer cobrança ou benefício ligado a quem encaminha.