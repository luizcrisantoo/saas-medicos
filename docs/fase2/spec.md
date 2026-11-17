# Fase 2: Fundação técnica. Spec da Operação v2

Autor: Arquiteto. Data: 2026-11-17. Fontes: `docs/briefing.md` (Linha do tempo, Fundação técnica; Definição de pronto; Arquitetura e segurança; Regras inegociáveis), `docs/fase1-resumo.md` (seção 5), `docs/adr/` (inclusive ADR-0007, 0012, 0013 e 0037 aceitos em 2026-11-17), `docs/arquitetura/` (modelo v2, mapa de módulos, máquina de estados), `docs/seguranca/stride-encaminhamento.md` (seção 12) e as baterias -r2.

Testes de aceite: `acceptance/` (runner `acceptance/run.sh F<n>|regressao|all`). Linha de base: `docs/fase2/aceite-baseline.log`. Memória entre iterações: `docs/fase2/progresso.md`.

## 1. Objetivo

Entregar a fundação técnica da Fase 2 do briefing: repositório com build e CI com varreduras, banco versionado com o modelo v2 e os gates do Red Team, autenticação no Cognito como resource server com sessão verificável no banco, contexto por transação, credencial de jobs separada, auditoria de acesso a dado de saúde, storage S3 cifrado testável sem nuvem, infraestrutura AWS sa-east-1 como código validado localmente e a base LGPD. Nada é provisionado nem publicado nesta fase (sem conta AWS, sem GitHub remoto). Não há tela.

## 2. As seis perguntas da Operação

| Pergunta | Resposta |
|---|---|
| Objetivo verificável por máquina | `acceptance/run.sh all` sai com código 0 (todo critério VERDE). Por feature: `acceptance/run.sh F<n>` sai 0. |
| Memória entre iterações | `docs/fase2/progresso.md` (status por feature, tentativas, último resultado do runner, checksums) mais o histórico do git (um commit por iteração). |
| Unidade de trabalho | Uma feature por iteração, na ordem da seção 4. |
| Quem verifica | O Orquestrador roda o script de aceite (`run.sh F<n>` e `run.sh regressao`) e confere os checksums; um Revisor diferente do Executor revisa o diff contra este spec, os ADRs e as regras inegociáveis. O Red Team revisa toda feature que toca autenticação, autorização, tenant, arquivos ou dado de saúde (briefing, Regras do fluxo). |
| Paradas | (1) Sucesso: `run.sh all` sai 0 com as BLOQUEANTES decididas e testadas. (2) Limite: 14 iterações no total ou 3 tentativas na mesma feature. (3) Bloqueio: a próxima feature depende de decisão BLOQUEANTE (seção 7) ou de recurso ausente. (4) Violação: checksum de `acceptance/**` ou das baterias de regressão diferente do registrado, ou alteração de arquivo proibido (seção 8). (5) Estagnação: 3 voltas seguidas sem aumentar o número de critérios VERDE. (6) Falha: o runner ou o ambiente quebra de forma que a iteração não pode ser avaliada. Em qualquer parada que não seja sucesso, o Orquestrador para e pergunta ao Luiz com as opções e o risco de cada uma. |
| O que o Executor não pode tocar | Seção 8. |

## 3. Contrato de aceite (interfaces fixas)

Os testes são caixa-preta e dependem só destas interfaces. Mudar qualquer uma delas é decisão do Arquiteto, com novo spec e novos checksums.

### 3.1 Repositório e build
- Projeto Gradle único na raiz, com wrapper (`gradlew`, `gradle/wrapper/gradle-wrapper.properties` apontando para `gradle-8.14.3`), Java 21 (bytecode major 65).
- Spring Boot 3.x e Spring Modulith 1.x (linha compatível com Boot 3, com `ApplicationModule.Type`). `./gradlew build` passa e `./gradlew bootJar` gera um único jar executável em `build/libs/` (o `-plain.jar` é ignorado).
- Pacote raiz `saasagenda`, classe principal `saasagenda.Aplicacao`. Os 8 módulos são `saasagenda.<modulo>` com `package-info.java` anotado com `@ApplicationModule(allowedDependencies = ...)` exatamente como a tabela da seção 3 de `docs/arquitetura/mapa-modulos.md`. Nenhum módulo `OPEN`.
- Testes do Executor que usam Testcontainers puxam imagens de `mirror.gcr.io/...` ou `public.ecr.aws/...` (Docker Hub dá 429) e rodam com `TESTCONTAINERS_RYUK_DISABLED=true`.

### 3.2 Banco
- `infra/db/bootstrap.sql`: roda uma vez por banco como superusuário do cluster (no RDS, o administrador). Cria os papéis `saas_owner` (NOLOGIN, dono das tabelas), `saas_funcoes` (NOLOGIN, BYPASSRLS, dono das funções SECURITY DEFINER), `saas_app`, `saas_jobs`, `saas_auth` (LOGIN, ADR-0024) e o papel de pipeline `saas_migracao` (LOGIN, sem superusuário, membro de `saas_owner` e `saas_funcoes` sem herança e sem admin: só assume esses papéis com SET ROLE durante a migração, ADR-0027). Cria o schema `saas` (dono `saas_owner`), o schema `migracao` (histórico do Flyway, dono `saas_migracao`), a extensão `btree_gist`, os parâmetros por papel (`track_activities = off`, `log_parameter_max_length = 0` e `log_parameter_max_length_on_error = 0`, ADR-0026 item 7) e os gatilhos de evento de alerta de DDL. Sem senha no arquivo: a senha vem do gerenciador de segredos (o runner define senhas aleatórias).
- Migrações Flyway em `src/main/resources/db/migration/V<n>__<descricao>.sql`, aplicadas pelo Flyway real como `saas_migracao`, histórico em `migracao.flyway_schema_history`. Cada migração assume o papel dono com `SET ROLE` e termina com `RESET ROLE`. A aplicação não migra o banco (`SPRING_FLYWAY_ENABLED=false`); migração só pelo pipeline (ADR-0027).
- Reversão: para cada `V<n>__x.sql` existe `src/main/resources/db/reversao/V<n>__x.sql` (mesmo nome), executado por `saas_migracao`, que devolve o schema `saas` exatamente ao estado da versão anterior (comparado por `pg_dump`). Fonte: Definição de pronto, "Migração de banco com caminho de reversão testado".
- O schema contém o modelo v2 inteiro (`docs/arquitetura/modelo-v2.sql`): tabelas, colunas e tipos, gatilhos. Pode ganhar objetos; não perde. As assinaturas das funções do modelo v2 usadas pelas baterias de regressão e pelas sondas de aceite continuam existindo (função nova pode ser sobrecarga ou outra função).
- Tabela nova: RLS ENABLE+FORCE; se não tiver política, nenhum papel de login tem privilégio nela. Função nova: nada para PUBLIC; SECURITY DEFINER com `search_path` fixo; `jobs_*` só para `saas_jobs`.
- Alertas no log do servidor (linhas que o CloudWatch transforma em alarme, F10): `ALERTA_DDL_SAAS` (R-07, R-08) e `ALERTA_PREPARO_VOLUME` (E-09). A linha nunca traz contato, token ou código.

### 3.3 Ambiente da aplicação
Processo web (`SAAS_PROCESSO=web`): `SPRING_DATASOURCE_URL`, `SPRING_DATASOURCE_USERNAME` (`saas_app`), `SPRING_DATASOURCE_PASSWORD` (pool Hikari padrão do Spring Boot); `SAAS_DB_AUTH_URL`, `SAAS_DB_AUTH_USERNAME` (`saas_auth`), `SAAS_DB_AUTH_PASSWORD`; `SAAS_AUTH_ISSUER`, `SAAS_AUTH_JWKS_URI`, `SAAS_AUTH_CLIENT_IDS` (lista separada por vírgula); `SAAS_S3_BUCKET`, `SAAS_S3_KMS_KEY_ID`, `AWS_REGION`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`; `--server.port`. O processo web não usa `SAAS_DB_JOBS_*` mesmo que estejam no ambiente (E-09).
Processo de jobs (`SAAS_PROCESSO=jobs`): só `SAAS_DB_JOBS_URL`, `SAAS_DB_JOBS_USERNAME` (`saas_jobs`), `SAAS_DB_JOBS_PASSWORD`; sobe sem as credenciais web e auth e abre ao menos uma conexão `saas_jobs` nos primeiros 45 s. As chaves e a URL do issuer não são consultados na partida (nada de descoberta OIDC pela rede: as chaves vêm de `SAAS_AUTH_JWKS_URI`).

### 3.4 API HTTP da Fase 2 (sem tela)
| Método e rota | Quem | Contrato |
|---|---|---|
| `GET /actuator/health` | público | 200 |
| `POST /api/sessao/equipe` | `Authorization: Bearer <access token do Cognito>` | Valida RS256 pela JWKS, `iss` igual a `SAAS_AUTH_ISSUER`, `client_id` na lista, `token_use=access`, `exp`. Abre sessão por `saas_auth` (`sessao_equipe_abre`) e devolve 200/201/204 com `Set-Cookie: SESSAO=<token hexadecimal da sessão>; HttpOnly; Secure; SameSite=...; Path=/`. Recusa com 401 (403 aceito para usuário inexistente ou inativo). |
| `GET /api/sessao` | cookie `SESSAO` | 200 `{"tipo": "EQUIPE"\|"PACIENTE"\|"ENCAMINHADOR"}`; 401 sem sessão válida, sem detalhe interno. |
| `DELETE /api/sessao` | cookie | Encerra a sessão no banco (200/204). |
| `GET /api/auditoria` | cookie de equipe, `X-Clinica-Id`, `X-Papel` | 200 lista `[{"id": ...}]` dos eventos da clínica para ADMIN; caso contrário 401/403 ou lista sem eventos (ADR-0009, mapa: `AuditoriaApi.consultar`). |
| `POST /api/encaminhamentos/{id}/anexos` | cookie de quem pode anexar | Corpo `{"tipoMime","tamanhoBytes","sha256"}`; 200/201 `{"anexoId","url","cabecalhos","expiraEm"}`; tipo e tamanho inválidos: 4xx. |
| `GET /api/anexos/{id}/download` | cookie de quem vê o caso | 200 `{"url","expiraEm"}` só com anexo LIMPO; grava EventoAuditoria na mesma transação. |
| `GET /api/termos/consentimento/{finalidade}` | qualquer | 200 `{"finalidade","versao","texto"}`. |
| `POST /api/consentimentos` | cookie de PACIENTE | Corpo `{"finalidade","encaminhamentoId","clinicaId","versao"}`; 200/201 `{"id"}`. Texto, paciente e canal saem do servidor, nunca do corpo. |
| `GET /api/consentimentos` | cookie de PACIENTE | 200 lista `[{"id",...}]` do caso da sessão. |
| `DELETE /api/consentimentos/{id}` | cookie de PACIENTE titular | 200/204; de novo: 404/409/410. |

Erros não trazem exceção, SQL nem nome de objeto do banco (ADR-0026, item 3).

### 3.5 CI e guarda de migração
- `scripts/ci/guarda-migracao.sh DIR_MIGRACOES ARQUIVO_APROVACOES`: sai 0 se toda migração do diretório é limpa ou aprovada, diferente de 0 caso contrário. Construções que exigem aprovação (ADR-0027 e R-08): `DISABLE TRIGGER`, `NO FORCE ROW LEVEL SECURITY`, `DISABLE ROW LEVEL SECURITY`, `DROP POLICY`, `DROP TRIGGER`, `session_replication_role`, `CREATE POLICY`, `ALTER POLICY`, `CREATE TRIGGER`, em qualquer grafia.
- Aprovação registrada: `src/main/resources/db/aprovacoes.sha256`, linhas no formato do `sha256sum` (`<sha256>  <nome do arquivo>`), presas ao conteúdo exato e ao nome. Quem aprova é a revisão do Red Team (registrada no PR).
- `.github/workflows/*.yml` válidos no actionlint, em `pull_request`, com `./gradlew build|test|check`, SAST, varredura de dependências, varredura de segredos e a guarda sobre `db/migration` e `db/reversao`. Proteção da branch principal: fora (sem acesso ao GitHub; passo manual do Luiz, seção 7).

### 3.6 Terraform
- `infra/terraform/ambientes/{dev,homolog,prod}/` (raízes) e, se o Executor quiser, `infra/terraform/conta/` (recursos da conta, como o orçamento). Cada raiz aceita `-var cotacao_usd_brl=<R$ por US$>` e `-var email_alerta=<e-mail>`; demais variáveis com padrão. `teto_mensal_brl` com padrão 800 (ADR-0013).
- Planeja sem credenciais com o override do runner (`skip_credentials_validation`, `skip_requesting_account_id`, `skip_metadata_api_check`, backend local): nada de data source que chame API da AWS (`aws_caller_identity`, `aws_availability_zones` etc.) nem `assume_role` no provider padrão.

### 3.7 Documentos legais
`docs/legal/termos-de-uso.md` e `docs/legal/politica-de-privacidade.md`, com a marca `RASCUNHO PARA REVISÃO DE ADVOGADO` no início, sem nome de pessoa real do negócio.

## 4. Features (ordem de execução)

Cada feature cabe numa iteração. Critérios: os ids `F<n>.<m>` impressos pelo runner. Todo critério negativo tem controle positivo no mesmo critério (recusar tudo não passa).

### F1. Esqueleto Spring Boot 3 + Spring Modulith
- Critérios: F1.1 wrapper 8.14.3 e Java 21; F1.2 `./gradlew build` passa; F1.3 bootJar com Spring Boot 3.x e `Start-Class: saasagenda.Aplicacao`; F1.4 teste injetado: `verify()`, exatamente os 8 módulos, `allowedDependencies` iguais ao mapa, nenhum OPEN; F1.5 mutante de dependência ilegal derruba o `verify()` e a suíte do próprio Executor; F1.6 mutante de acesso a tipo interno derruba o `verify()`.
- Teste: `acceptance/F1/aceite.sh` numa cópia do repositório, com `acceptance/F1/java/` injetado e os mutantes de `acceptance/F1/mutantes/`.
- Fora: endpoints de negócio, eventos (nenhum evento tem consumidor na Fase 2, ADR-0032), `event_publication` (seção 7, P4).

### F2. Migrações Flyway do modelo v2 com dono sem login
- Critérios: F2.1 bootstrap sem senha roda num PostgreSQL 16 limpo; F2.2 Flyway real aplica como `saas_migracao`, `validate` ok, idempotente; F2.3 atributos dos papéis; F2.4 todo objeto de `saas` com dono `saas_owner` (funções: `saas_owner` ou `saas_funcoes`); F2.5 só `saas_migracao` assume os papéis donos, sem herança; F2.6 regras gerais (RLS forçada, jobs e auth sem tabela, web sem DELETE/TRUNCATE, nada para PUBLIC, SECURITY DEFINER com `search_path`, rastreio desligado, tabela sem política só por função, gatilhos de evento ativos); F2.7 superconjunto do modelo v2; F2.8 reversão testada versão a versão; F2.9 regressão das baterias -r2 (seção 6).
- Teste: `acceptance/F2/aceite.sh` (PostgreSQL efêmero, harness Flyway em `acceptance/harness/migra`).
- Fora: os gates (F3, F4); cifra de CPF, motivo e conduta na aplicação (entra com os fluxos que gravam esses campos, Fases 3 e 5).

### F3. Gates de identidade: T-20, I-22, I-23
- Critérios: F3.1 T-20: CPF só identifica com nome normalizado e nascimento (quando os dois têm) iguais; filho com CPF do responsável vira paciente próprio; regras de identidade da Fase 1 mantidas; F3.2 recepção nunca recebe o id de paciente existente por coincidência; F3.3 I-22: o link nunca vai ao telefone antigo em silêncio (vai ao telefone informado ou não sai); F3.4 I-23: depois da revogação, cadastro, agendamento e consentimento da recepção destino não usam o vínculo nascido do encaminhamento.
- Teste: `acceptance/F3/sondas-f3.sql` (sondas novas, fluxo real de link e código, papéis reais).
- Fora: forma da sugestão de duplicata e tela de duplicatas (Fase 3, ADR-0036 item 5); aviso ao encaminhador quando o envio não sai (Fase 5); entidade de vínculo do menor (F12, B1). A exigência do Red Team de corrigir "na primeira migração" se cumpre porque nenhuma migração é aplicada em ambiente algum antes do fechamento da fase (nada é provisionado); o Executor pode corrigir na V1 ou numa V2.

### F4. Gates de banco: R-08, I-21, O3, envios após cancelamento, volume (E-09)
- Critérios: F4.1 R-08: alerta `ALERTA_DDL_SAAS` para política, gatilho, regra, desligamento de gatilho e de RLS em tabela de `saas`, mesmo com ROLLBACK; F4.2 I-21: funções SECURITY DEFINER sem sessão não respondem; F4.3 O3: profissional sem canal verificado e sem usuário fora da visão de paciente e encaminhador; F4.4 cancelar agendamento (direto ou em cascata por T11) derruba CONFIRMACAO_AGENDAMENTO e LEMBRETE pendentes; F4.5 E-09: 20 ou mais preparos para o mesmo destinatário em 1 hora geram `ALERTA_PREPARO_VOLUME` sem o contato.
- Teste: `acceptance/F4/sondas-f4.sql` e `acceptance/F4/confere_log.py` (log do servidor entre marcas).
- Fora: T-19 (Fase 3, decisão do Verificador); roteamento do alerta para fora do banco (F10).

### F5. CI: guarda de migração e GitHub Actions
- Critérios: F5.1 guarda aceita as migrações do repositório com as aprovações; F5.2 recusa as nove construções sem aprovação; F5.3 não é enganada por variações de escrita; F5.4 aceita migração limpa; F5.5 aprovação presa a sha256 e nome; F5.6 actionlint e `pull_request`; F5.7 testes, SAST, dependências e segredos no pipeline; F5.8 guarda sobre `db/migration` e `db/reversao`; F5.9 pipeline varre segredos, repositório limpo, chave plantada detectada com a configuração do repositório.
- Teste: `acceptance/F5/testa_guarda.py` (migrações maliciosas), `acceptance/F5/confere_ci.py`, actionlint e gitleaks fixados em `acceptance/ferramentas.sh`.
- Fora: execução real no GitHub, proteção de branch, ZAP em homologação (antes de cada release, sem homologação provisionada).

### F6. Autenticação Cognito como resource server
- Critérios: F6.1 sobe com o ambiente do contrato; F6.2 token válido abre sessão no banco com cookie seguro; F6.3 matriz de tokens inválidos recusada sem sessão criada; F6.4 cookie inválido dá 401 sem detalhe interno; F6.5 logout encerra no banco; F6.6 nenhum JWT nem cookie em log; F6.7 sessão aberta por `saas_auth`, consultas por `saas_app`.
- Teste: `acceptance/F6/teste_f6.py` com JWKS local (`acceptance/lib/jwks_servidor.py`) e JWT RS256 assinado por chave local.
- Fora: MFA obrigatório para ADMIN e MEDICO (F11, B2); renovação rotativa (é do Cognito, configurada em F10); sessão de paciente e de encaminhador por código (Fases 4 e 5).

### F7. Contexto por transação, pool seguro, I-20 e credencial de jobs separada
- Critérios: F7.1 ADMIN vê só a auditoria da própria clínica; F7.2 papel sem vínculo, clínica alheia ou sem sessão não veem nada; F7.3 pool de 1 conexão com requisições alternadas e concorrentes nunca herda contexto; F7.4 nenhum token em log do PostgreSQL com `log_statement=all` nem em `pg_stat_statements`; F7.5 contexto por `set_config` parametrizado e local; F7.6 código-fonte sem interpolação; F7.7 mutante com SQL interpolado derruba a suíte do Executor (teste de arquitetura do ADR-0026, item 7); F7.8 processo web nunca conecta como `saas_jobs`; F7.9 processo de jobs só com a credencial de jobs.
- Teste: `acceptance/F7/teste_f7.py` e `acceptance/F7/aceite.sh`.
- Fora: listeners e jobs de negócio (Fases 4 e 5); escalonamento real do processo de jobs (computação, seção 7, P3).

### F8. Storage S3 e auditoria de acesso a dado de saúde
- Critérios: F8.1 upload válido registra o anexo e devolve URL PUT SigV4 de até 5 min em sa-east-1, no bucket do ambiente, na chave opaca, com SSE-KMS assinado; F8.2 tipo fora de PDF, JPEG e PNG recusado; F8.3 tamanho acima de 20 MiB, zero ou negativo recusado; F8.4 upload em caso que o ator não vê recusado; F8.5 download de anexo LIMPO com URL GET de até 5 min; F8.6 PENDENTE, INFECTADO, alheio ou sem sessão recusado; F8.7 um EventoAuditoria por download concedido; F8.8 auditoria falhando, nenhuma URL; F8.9 nenhuma URL assinada em log.
- Teste: `acceptance/F8/teste_f8.py` (URL assinada conferida sem nuvem).
- Fora: varredura de vírus real (o serviço é escolha da Fase 5 com a hospedagem; `jobs_anexo_varredura` já existe); prazo de retenção (pergunta aberta); envio do arquivo ao S3 (é do cliente, com a URL).

### F9. Base LGPD
- Critérios: F9.1 texto versionado do consentimento; F9.2 concessão pela API com dados do servidor; F9.3 recusas e campos forjados ignorados; F9.4 listagem do caso; F9.5 revogação idempotente e consentimento alheio intocado; F9.6 clínica destino só vê o caso com consentimento ativo; F9.7 termos e política em rascunho marcado, com dado de saúde, direitos do titular, encarregado, retenção e papéis LGPD marcados como A DEFINIR, cobrança só por mensalidade, nenhuma vantagem a quem encaminha e livre escolha do paciente.
- Teste: `acceptance/F9/teste_f9.py` e `acceptance/F9/confere_docs.py`.
- Fora: texto final (advogado); papéis controlador e operador (advogado, antes da Fase 5); atendimento a pedido do titular (rotina operacional, antes do lançamento).

### F10. Terraform AWS sa-east-1
- Critérios: F10.1 fmt e validate; F10.2 plan sem credenciais em todas as raízes, com duas cotações; F10.3 sa-east-1; F10.4 RDS PostgreSQL 16 cifrado, privado, PITR, `rds.force_ssl=1`, logs exportados, proteção contra exclusão em prod, senha fora do código; F10.5 bucket de anexos com SSE-KMS de chave própria rotacionada, bloqueio público e política que exige TLS e SSE-KMS; F10.6 segredos separados de `saas_app`, `saas_jobs`, `saas_auth` e `saas_migracao`, cifrados com KMS, sem valor no código; F10.7 Cognito com MFA TOTP habilitado, senha com 12 ou mais caracteres (ASVS nível 2), access token de até 60 min e revogação; F10.8 alarmes para `ALERTA_DDL_SAAS` e `ALERTA_PREPARO_VOLUME`; F10.9 nomes distintos por ambiente; F10.10 orçamento mensal em USD igual ao teto dividido pela cotação (entre R$ 400 e R$ 800), alerta real até 100% e previsto.
- Teste: `acceptance/F10/aceite.sh` (terraform 1.9.8 fixado) e `acceptance/F10/confere_plano.py`.
- Fora: `terraform apply`, computação da aplicação (seção 7, P3), conta única ou múltipla (P5), CloudTrail e alerta de login em massa (operação, antes do lançamento).

### F11. MFA obrigatório para ADMIN e MEDICO (BLOQUEADA, B2)
- Critérios a escrever depois de B2: token de ADMIN ou MEDICO sem prova de MFA recusado sem sessão; com prova, aceito; `sessao_equipe_abre` recebe e grava o fator e recusa ADMIN e MEDICO sem MFA (E-10). O runner imprime VERMELHO "BLOQUEADO".

### F12. Menor com cadastro próprio ligado a responsável (BLOQUEADA, B1)
- Critérios a escrever depois de B1: menor como Paciente próprio com vínculo explícito a responsável; CPF "do responsável" gravado no responsável; link e código ao WhatsApp do responsável; sessão do responsável vale só para o caso do menor; nunca há fusão. O runner imprime VERMELHO "BLOQUEADO".

Dependências: F1 antes de F6 a F9 (jar); F2 antes de F3, F4 e F6 a F9 (banco); F5 pode correr depois de F2; F10 é independente. F11 depois de F6 e de B2; F12 depois de F3 e de B1.

## 5. Gates do Red Team da Fase 2 (rastreio)

| Gate (`docs/fase1-resumo.md`, seção 5) | Feature e critério |
|---|---|
| T-20 (via ADR-0037) | F3.1, F3.2; vínculo do menor em F12 (B1) |
| I-22 | F3.3 |
| R-08 (gatilho por tabela alvo; CI recusa CREATE/ALTER POLICY e CREATE TRIGGER) | F4.1; F5.2, F5.3 |
| I-23 | F3.4 |
| E-09 | F7.8, F7.9; F4.5 (alerta de volume); F10.6 (segredos separados) |
| E-10 | F6.2, F6.3 (assinatura, iss, client_id, exp, token_use); MFA em F11 (B2); nonce: seção 7, P1 |
| I-21 | F4.2 |
| O3 | F4.3 |
| T-19 | Fase 3 (decisão do Verificador) |
| Gate de CI de R-07 | F5.1 a F5.5, F5.8 |
| Teste de código de I-20 | F7.4 a F7.7 |
| Envios pendentes após cancelamento (Testador r2) | F4.4 |
| Regressão N1 a N12, RT1 a RT10, R2N1 a R2N9, R2-1 a R2-7 e matriz de 392 sondas | F2.9 (`run.sh regressao`) |

## 6. Regressão

`acceptance/regressao/regressao.sh` roda as baterias -r2 atuais contra o banco migrado pelo Flyway: `teste-rls-r2.sql` (inclui a matriz de 392 sondas), `teste-r1-independente-r2.sql`, `teste-r2-independente.sql`, `sondas-r2.sql`, `red-team-sondas-r1.sql`, `red-team-sondas-r1-novas.sql` e `red-team-sondas-r2.sql`. Nenhuma é alterada; adaptações só de infraestrutura (socket, porta, nome do banco, `ON_ERROR_STOP` desligado para que uma sonda que muda por gate não derrube as outras).
- Baterias com tabela de resultado: toda sonda do golden (gerado contra `modelo-v2.sql` por `acceptance/regressao/gera-golden.sh`) tem que estar presente e ok.
- Baterias impressas do Red Team: a saída normalizada tem que ser idêntica à do `modelo-v2.sql` fora dos blocos de gate.
- Sondas neutras (o gate inverte o esperado; o gate é exigido nas sondas novas): `acceptance/regressao/golden/*.neutras` e as listas `NEUTROS_*` de `regressao.sh`, cada uma com o motivo. Resumo: controles de deduplicação por CPF e de reaproveitamento na recepção (T-20), `EXECUTE rede_ligada` (I-21), falha latente dos envios após cancelamento (F4.4), N1e, N1f (papel de pipeline do ADR-0027), N3c e N3e (E-10), N11a, N11c, N11d, R2N1, R2N2, R2N3, R2N5 e R2N9.
- Objetos novos (tabela, função) não quebram a matriz do Testador: seguem as regras gerais de F2.6.

## 7. BLOQUEANTES e pendências

### BLOQUEANTES (decisão do Luiz; sem elas a fase não fecha)
- **B1. Contrato do menor ligado a responsável (ADR-0037).** O ADR decide o modelo, mas não: o nome da entidade de vínculo no glossário (regra do briefing: termo novo entra no glossário antes do código), quais dados o médico informa no encaminhamento do menor (dados do responsável, CPF de quem), o critério de menoridade (menor de 18 pela data de nascimento? e o relativamente incapaz de 16 e 17 anos [SUPOSIÇÃO: questão para o advogado]) e se o responsável precisa de cadastro com telefone próprio. Sem isso não há teste de aceite possível para F12. O núcleo do T-20 (F3) não depende de B1.
- **B2. Como o token do Cognito prova MFA para ADMIN e MEDICO (ADR-0007, E-10).** O ADR diz "user pool com MFA obrigatório para ADMIN e MEDICO", mas o Cognito não tem MFA obrigatório por grupo e o E-10 pede validar `amr`, claim que o user pool não emite [SUPOSIÇÃO: conferir com o Pesquisador na documentação do Cognito]. Opções: (a) MFA obrigatório para todo usuário do pool, recepção inclusive; (b) pools separados (equipe com MFA obrigatório e recepção sem); (c) gatilho de pré-geração de token que grava uma claim própria a partir da configuração de MFA do usuário (exige o plano Essentials). Cada opção muda a claim que a aplicação confere e o parâmetro que `sessao_equipe_abre` recebe. Sem a decisão, F11 fica VERMELHO e N3c e N3e continuam residuais.

### Pendências não bloqueantes (registradas para o Orquestrador e o Red Team)
- P1. Nonce (E-10): não se aplica a access token de resource server. Se o desenho virar callback com id_token, entra teste de nonce. Revisão do Red Team (veto em autenticação).
- P2. "URL assinada de poucos minutos" (ADR-0010) foi lida como até 5 minutos [SUPOSIÇÃO de interpretação]; o orçamento "coerente com R$ 800" foi lido como limite entre R$ 400 e R$ 800 na cotação informada, porque o teto inclui WhatsApp e a divisão não foi decidida [SUPOSIÇÃO].
- P3. Computação da aplicação na AWS (ECS, App Runner, EC2, Lightsail) não está decidida no ADR-0012; fica fora de F10. Decidir antes do primeiro deploy (Fase 3), com o teto do ADR-0013. A separação do processo de jobs (E-09) já é exigida no código (F7.8, F7.9).
- P4. `event_publication` do Spring Modulith sem GRANT ao papel web (ADR-0033) contradiz a gravação do outbox na transação do negócio pelo próprio `saas_app`. Nenhum evento tem consumidor na Fase 2 (ADR-0032), então o registro de publicações fica desligado nesta fase; ADR novo antes da Fase 4.
- P5. Isolamento dos ambientes por conta AWS separada ou por nomes na mesma conta não está decidido (ADR-0014 diz "isolados"); F10 exige só nomes e recursos distintos.
- P6. Proteção da branch principal e execução real do pipeline dependem do GitHub remoto: passo manual do Luiz quando houver acesso.
- P7. Abertas do briefing que não entram aqui: retenção de anexos, papéis LGPD (advogado), migração dos dados do Rodrigo (antes da Fase 3).

## 8. O que o Executor não pode tocar

- `docs/briefing.md`.
- ADRs aceitos em `docs/adr/` (decisão nova só por ADR novo que substitui o antigo, briefing "Registro de decisões").
- `acceptance/**` (checksum em `docs/fase2/progresso.md`).
- Baterias de regressão e o modelo de referência: `docs/arquitetura/modelo-v2.sql`, `docs/arquitetura/evidencias/*.sql` e `*.sh`, `docs/seguranca/evidencias/*.sql` (checksum em `docs/fase2/progresso.md`).
- `docs/fase2/spec.md` e `docs/fase2/aceite-baseline.log`.
- Nenhum dado real de paciente, médico ou clínica em código, teste, semente ou log (dado fictício sempre; build in public).
- Nada de `git push`, deploy, `terraform apply` ou chamada a conta de nuvem.

## 9. Protocolo de cada iteração (Orquestrador)

1. Conferir os checksums de `docs/fase2/progresso.md`; divergência é parada por violação.
2. Despachar ao Executor a próxima feature PENDENTE (ou a que voltou), com este spec e o último resultado do runner.
3. Rodar `acceptance/run.sh F<n>` e `acceptance/run.sh regressao` (a partir de F2); colar o resumo em `progresso.md`.
4. Revisor diferente do Executor revisa o diff; Red Team quando a feature tocar autenticação, autorização, tenant, arquivos ou dado de saúde.
5. Feature fica PRONTA só com o runner verde, revisão aprovada e commit. Atualizar tentativas e contagem de VERDE; aplicar as paradas da seção 2.
