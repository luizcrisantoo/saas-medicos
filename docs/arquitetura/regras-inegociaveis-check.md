# Regras inegociáveis x desenho v2

Tarefa: t-fase1-arquitetura, critério 10. Regras copiadas de `docs/briefing.md`, seção "Regras inegociáveis". Para cada uma: onde o desenho v2 a garante (arquivo e trecho) e o que ainda depende de outra fase ou pessoa.

Verificação mecânica refeita na rodada 1 (2026-11-10), sobre o `modelo-v2.sql` corrigido: `grep -niE "comiss|descont|bonus|credito|pontu|valor|preco|cobranc|fatur" docs/arquitetura/modelo-v2.sql` retorna só 2 linhas de comentário (21, 22) e nenhuma coluna; o grep restrito a definições de coluna (`^\s+<nome>\s+<tipo>`) retorna vazio (exit 1). As tabelas novas da rodada 1 (`sessao`, `desafio_encaminhador`, `envio_notificacao`) não têm campo de valor.

## Ética médica

| Regra | Onde aparece no desenho | Trecho | Situação |
|---|---|---|---|
| Nunca pagar, dar desconto ou vantagem a quem encaminha | `modelo-v2.sql`, cabeçalho, linhas 20 a 23 (mesmas na rodada 1); `modelo-dados-v2.md`, seção 1 | "NAO existe neste modelo nenhum campo de comissao, desconto, bonus, credito, pontuacao ou valor por paciente, nem tabela de cobranca por paciente" | Atende. Grep acima sem coluna. Nenhum evento de `mapa-modulos.md` alimenta recompensa: o único consumidor de eventos de encaminhamento é `notificacoes` (seção 4; eventos de métrica cortados pelo ADR-0032). Base: CEM art. 59 (Pesquisador, seção 4) |
| Nunca cobrar da clínica por paciente recebido; só mensalidade fixa | `modelo-v2.sql`, linha 22 (rodada 1) | "Cobranca (Fase 7) sera mensalidade fixa por clinica e entra em ADR proprio" | Atende na Fase 1 (não há tabela de cobrança). `MetricasRedeApi` em `mapa-modulos.md` (encaminhamentos) entrega contagem para o painel, não para faturamento. A Fase 7 precisa de ADR que repita a regra |
| Paciente sempre livre para escolher outro especialista | `maquina-estados-encaminhamento.md`, transição T10 e parágrafo seguinte | "T10 \| ENVIADO_AO_PACIENTE, SOLICITADO ou AGENDADO \| CANCELADO \| Paciente escolhe outro especialista, dentro ou fora da rede \| PACIENTE" | Atende. O destino é opcional na criação (`encaminhamento.clinica_destino_id` nulo até o paciente escolher, `modelo-v2.sql`), e quem escolhe em T3 é o paciente. Rodada 1: o gatilho de transições garante T10 por UPDATE direto do paciente em ENVIADO_AO_PACIENTE, SOLICITADO e AGENDADO (matriz de `evidencias/teste-rls-r1.log`) |

## LGPD

| Regra | Onde aparece no desenho | Trecho | Situação |
|---|---|---|---|
| Consentimento explícito do paciente para compartilhar o caso com a clínica destino | `modelo-v2.sql`, política `encaminhamento_destino` e CHECK de `consentimento`; ADR-0022; máquina de estados T3 | "AND c.finalidade = 'COMPARTILHAR_CASO' AND c.revogado_em IS NULL"; "CHECK (finalidade <> 'COMPARTILHAR_CASO' OR (encaminhamento_id IS NOT NULL AND clinica_id IS NOT NULL))"; rodada 1: FKs compostas `(paciente_id, encaminhamento_id)` e `(clinica_id, encaminhamento_id)` | Atende. Sem consentimento a clínica destino não vê a linha; consentimento forjado para caso alheio ou clínica não destino é recusado pelo banco (`teste-rls-r1.log`, r1-11 e sondas [r1: NEGADO] da seção f). Texto do consentimento e base legal com o advogado |
| Acesso mínimo: só quem participa do encaminhamento vê os dados dele | `modelo-dados-v2.md`, seção 5 (tabela de políticas); ADR-0023 (identidade por sessão verificada); `mapa-modulos.md` (PoliticaEncaminhamento); ADR-0009 | "Não há política para a clínica de origem"; histórico, contrarreferência e anexos "herdam exatamente a mesma visibilidade" | Atende no desenho. Prova: `evidencias/teste-rls-r1.log` (1422 sondas, 0 falhas) e `docs/seguranca/evidencias/red-team-sondas-r1.log` (26 de 26 ataques negados). Rodada 1: telefone e e-mail de profissional sem GRANT para a web |
| Todo acesso a dado de saúde fica registrado na auditoria | `mapa-modulos.md`, módulo auditoria; `arquivos` (`urlDownload` grava EventoAuditoria); `maquina-estados-encaminhamento.md`, seção 5 | "chamada síncrona na mesma transação do acesso, para que acesso sem registro não aconteça"; `evento_auditoria` só inclusão (gatilho `bloqueia_alteracao`) | Atende no desenho, com a ressalva do modelo: leitura é auditada pela aplicação, porque o PostgreSQL não tem gatilho de SELECT (modelo-dados-v2.md, seção 5). Teste na Fase 2 |
| Prazo de retenção definido para anexos e dados de encaminhamento | `modelo-v2.sql`, `anexo_encaminhamento.reter_ate`; ADR-0010; ADR-0033 | "reter_ate timestamptz -- PERGUNTA ABERTA: prazo de retencao (Pesquisador, Lei 13.787; advogado)" | Marcado como pergunta. O campo existe; o prazo depende de o anexo contar ou não como prontuário (Lei 13.787, 20 anos; Pesquisador seção 4). Retenção do encaminhamento em si e de `envio_notificacao` também aberta (ADR-0034). Precisa de decisão antes da Fase 5 (ADR-0033) |

## Segurança

| Regra | Onde aparece no desenho | Trecho | Situação |
|---|---|---|---|
| Anexos sempre em storage criptografado | ADR-0010; ADR-0026; `mapa-modulos.md`, módulo arquivos; `modelo-v2.sql`, `anexo_encaminhamento` | "Bucket privado com criptografia em repouso; acesso só por URL assinada de poucos minutos"; "chave_storage ... gerada pelo servidor; sem GRANT de escrita" (rodada 1, imutável por gatilho); `nome_original_cifrado bytea` | Atende no desenho. Serviço concreto depende do ADR-0012 |
| Nenhum dado clínico no corpo da mensagem de WhatsApp, só link autenticado com expiração | `mapa-modulos.md`, módulo notificacoes e regra "Payload só com ids"; ADR-0008; ADR-0018; ADR-0020; ADR-0033 (lista fechada de variáveis por template); ADR-0034 (`envio_notificacao` sem coluna de texto) | "Corpo de mensagem: só texto de template sem dado clínico mais link autenticado com expiração"; "Nunca nome, telefone, CPF, motivo, conduta, nome de arquivo, token de link ou código de uso único" (evento) | Atende. Como o evento não carrega dado clínico, o módulo que monta a mensagem não recebe motivo nem conduta. Vale também para SMS e e-mail do plano B (ADR-0018). Aviso de contrarreferência ao profissional de origem leva só link |

## Build in public

São regras de processo, não de modelo. O desenho apoia assim:

| Regra | Apoio no desenho |
|---|---|
| Nunca mostrar tela com dado real; gravar só em homologação com dado fictício | ADR-0014: homologação só com dado fictício |
| Nunca mostrar chave, token, configuração, painel da nuvem ou URL de produção e homologação | ADR-0011: segredos só no gerenciador da nuvem; ADR-0014 |
| Revisar cada print e vídeo | Fora do desenho; responsabilidade do Luiz antes de publicar |
| Não detalhar o que ajuda a atacar (ex.: formato dos links de paciente) | Os diagramas em `docs/arquitetura/diagramas/` não mostram formato de token nem URL; ficam no repositório, não em material público [SUPOSIÇÃO: repositório privado] |
