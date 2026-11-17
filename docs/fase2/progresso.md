# Fase 2: progresso da Operação v2

Memória entre iterações (spec: `docs/fase2/spec.md`, seção 2). O Orquestrador atualiza esta tabela a cada iteração; o Executor não edita a seção de checksums.

Limites: 14 iterações no total, 3 tentativas por feature, estagnação de 3 voltas. Iterações usadas: 10 de 14.

## Features

| Feature | Título | Status | Tentativas | Critérios VERDE | Último resultado |
|---|---|---|---|---|---|
| F1 | Esqueleto Spring Boot 3 + Spring Modulith, 8 módulos e fronteiras | PRONTA (saída 0) | 1 | 6 de 6 | Verificador 6/6 VERDE; Revisor APROVADO |
| F2 | Migrações Flyway do modelo v2, dono sem login, reversão e regressão | PRONTA (saída 0) | 1 | 9 de 9 | Verificador 9/9 VERDE; Revisor APROVADO com ressalvas não bloqueantes |
| F3 | Gates de identidade: T-20, I-22, I-23 | PRONTA (saída 0, tentativa 2) | 2 | 4 de 4 | Verificador 4/4; Revisor APROVADO; nascimento NULL sobe ao Negócio |
| F4 | Gates de banco: R-08, I-21, O3, envios após cancelamento, volume (E-09) | PRONTA (saída 0, tentativa 2) | 2 | 5 de 5 | Verificador 5/5; Revisor APROVADO com ressalvas (ruído de GRANT na migração; telefone sem DDD contorna volume; custo quadrático do preparo) |
| F5 | CI: guarda de migração (R-07, R-08) e GitHub Actions | PRONTA (saída 0, tentativa 3) | 3 | 9 de 9 | Verificador 9/9; Revisor APROVADO com ressalvas |
| F6 | Autenticação Cognito (resource server) e sessão de equipe no banco | PRONTA (saída 0) | 1 | 7 de 7 | Verificador 7/7; Revisor APROVADO com ressalvas |
| F7 | Contexto por transação, pool seguro, I-20, credencial de jobs separada (E-09) | PENDENTE | 0 | 0 de 9 | baseline |
| F8 | Storage S3 com SSE-KMS e URL assinada curta, auditoria de acesso | PENDENTE | 0 | 0 de 9 | baseline |
| F9 | Base LGPD: consentimento pela API, termos e política em rascunho | PENDENTE | 0 | 0 de 7 | baseline |
| F10 | Terraform AWS sa-east-1, 3 ambientes, orçamento coerente com R$ 800 | PENDENTE | 0 | 0 de 10 | baseline |
| F11 | MFA obrigatório para ADMIN e MEDICO | BLOQUEADA (B2) | 0 | 0 de 3 | baseline |
| F12 | Menor com cadastro próprio ligado a responsável (ADR-0037) | BLOQUEADA (B1) | 0 | 0 de 4 | baseline |

Linha de base: `docs/fase2/aceite-baseline.log` (0 VERDE, 82 VERMELHO).

## Registro de iterações

| # | Data | Feature | Executor | Revisor | run.sh F<n> | run.sh regressao | Decisão |
|---|---|---|---|---|---|---|---|

## Checksums (detecção de violação)

Arquivos protegidos: `acceptance/**` (menos `.bin`, `.tmp`, `__pycache__` e o build do harness, ignorados pelo git), `docs/arquitetura/modelo-v2.sql`, `docs/arquitetura/evidencias/*.sql` e `*.sh`, `docs/seguranca/evidencias/*.sql`.

- sha256 agregado: substituído pelo Orquestrador. A conferência oficial usa uma cópia da lista guardada fora do repositório (fora do alcance do Executor); o agregado antigo `f176327d…` incluía NOTAS-ANTI-HACK.md, que saiu do repo.
- `docs/fase2/spec.md`: `0e2cd90c0165a5e818321945c7e1fe2baed83994add545cf31d35872ba4eb25f`
- `docs/fase2/aceite-baseline.log`: `ee28a9c8a125acfbf60ce5cc4abc75d3d0badb17d405e282ecace2206ed6dc43`

Conferência (tem que imprimir o agregado acima):

```
{ find acceptance -type f -not -path 'acceptance/.bin/*' -not -path 'acceptance/.tmp/*' -not -path 'acceptance/harness/migra/build/*' -not -path 'acceptance/harness/migra/.gradle/*' -not -path '*/__pycache__/*'; ls docs/arquitetura/modelo-v2.sql docs/arquitetura/evidencias/*.sql docs/arquitetura/evidencias/*.sh docs/seguranca/evidencias/*.sql; } | LC_ALL=C sort | xargs sha256sum | sha256sum
```

Lista por arquivo:

```
faa40d17de9e1c1086141e16d86216efee70b977115dd2eeda5da947a73311dc  acceptance/F1/aceite.sh
5118c4a001c931f373f6ef6d5767ec26c7b085850eb2b3f377f5f4fb1ea88d87  acceptance/F1/java/saasagenda/AceiteF1ModulosTest.java
2560fa3423c9bf55778cb6480b1268576809dfb94e890b83c711309b69ea32d6  acceptance/F1/mutantes/a/saasagenda/agenda/AceiteAlvoAgenda.java
cf630b55f8ea8a0bf1d74192dd3fc4d6c9ea1fd2cc44fcb7c57387faea13e4a6  acceptance/F1/mutantes/a/saasagenda/identidade/AceiteMutanteIdentidade.java
53ea0947d9d37a97d662b8214906d6b33988f9dcde5158ce2cdcc266fdcd4dfe  acceptance/F1/mutantes/b/saasagenda/agenda/AceiteUsaInterno.java
b1cc7e6a7c28b8f9161ad18f989c86a9329eec9d4b359d6d5b1f9f529a0e7636  acceptance/F1/mutantes/b/saasagenda/clinicas/aceiteinterno/AceiteInterno.java
cec838381c3221abc2e311acd0738a92e3315000c4a69bec1a09823c1b60981a  acceptance/F10/aceite.sh
e37b8358233e7af038d898f9e3f561bd8703304bc250a01dc9ecb99233b0535d  acceptance/F10/confere_plano.py
2912dffc42dec346ae9502de5b2385b706aea028c267e45558e44d9d82214f30  acceptance/F11/aceite.sh
7e0b40be0cb8aaa3323c70ec3c660ce0068f2b369eb3a679a31c7bcdf37af01a  acceptance/F12/aceite.sh
2d03faac9112335d29a50b2f4e502849d6346aedb569310bedbdd9647adcbd29  acceptance/F2/aceite.sh
00d7d6b0b14d706fe2495d6599e9ff5f1f07a144136799a01290a7b0083d0a06  acceptance/F3/aceite.sh
4af1bcc1cd4fe1caa49407c03027a2c403876f8fd9f8549be5109ebbe80a2147  acceptance/F3/sondas-f3.sql
06b4c786a2e1db66209ada6a86a94c119f354e558a17552646dc365c62dd3a3d  acceptance/F4/aceite.sh
f535951ca83e4c6206ee289f94c3ffac103ced1b964cc5a128babd53497b6921  acceptance/F4/confere_log.py
b2341d49fa2ee415700e9add22a15b62eb11a5c2e5cf718148ee7ab4142d12ec  acceptance/F4/sondas-f4.sql
c1c54283b5ab0ea970e2ef093af5fe77117e9978fea058855dc51da4c4529bd3  acceptance/F5/aceite.sh
7f1878970fc6e1d25cebd72723b40442c49d6b939b262e19158d015df642f2c6  acceptance/F5/confere_ci.py
cfd31e15c0398903df1d1580fbb9869eee00338571fc625fde653a508aeae15f  acceptance/F5/testa_guarda.py
4515ede52fe02015af594f209e66fc9ebf09207d0a5cea7326102448828668b9  acceptance/F6/aceite.sh
94260b3e8a56725b36a88e59136c1fdd5d16628b2ca16d051e5685d27c8a4e3b  acceptance/F6/semente-f6.sql
27cbf750cfd32b137efdc10881223421648be29666e0f0ee9642830f6115d845  acceptance/F6/teste_f6.py
cfd94ee211cf1d81a481c91d0ddbf1d2d4a109d87aae6de3b07317a2c2a69fbd  acceptance/F7/aceite.sh
5ce304ed69c5cd9567a3fa18f3cb66bb89baf9a3f9532ba40506cb8c45111aad  acceptance/F7/mutante/saasagenda/identidade/AceiteContextoInseguro.java
10c20d9f3d043dc288d100f5c016455d23a378eb7106bb59d58c4612a7068d64  acceptance/F7/semente-f7.sql
7150cd7b9181428bffd7637c25fd98c15c5a93f458687db2041cc9cb0be073e2  acceptance/F7/teste_f7.py
d3f5b906440c6b19c78bdbe5c0cea1920eb1d310427bb7b160652c662b9220f1  acceptance/F8/aceite.sh
14794bcae757e21b30d1bd014474d8cfd92dfa1ad5e2b3efdc5f7ddf663c7849  acceptance/F8/semente-f8.sql
aab1d5087e4280cb5883ed6cd526e22dbf0e22c852ec6644544f198373b08998  acceptance/F8/teste_f8.py
46141f225cc84e9dbec856cc39ff3d3adf713a4818478a4356e0fb44c511c8c3  acceptance/F9/aceite.sh
6e1431e109b72ec001036bf5e06b9c904f659539ef571e7b2ad2eb4af3a721d0  acceptance/F9/confere_docs.py
7d2a92b897078d849fcd6f7be24fa8e13c861b26c5a8a74b8f44383fe77baa4f  acceptance/F9/semente-f9.sql
375f77c55565f54c07976c7748c772cc7cfea1eecf8014c28a9a58e36fdb2306  acceptance/F9/teste_f9.py
d842825b13e12f0207b2786e0a708867aeff3c83781315792fc2eac5d44b9429  (movido pelo Orquestrador para fora do repo, fora do alcance do Executor) NOTAS-ANTI-HACK.md
cf4d6e498846da04994f22b6c362ad47953fc873880095041063d7ea844e2876  acceptance/ferramentas.sh
d53f5b4ff227635c5889a467f1af006b628bb4ed73e956e52c0420d44fd7a26d  acceptance/harness/migra/build.gradle.kts
bfc5f56a56bb26905372b5f1c0912a8e727ba6162d87d5185847cce2b269557f  acceptance/harness/migra/settings.gradle.kts
8434f93cedf6c67f0624664a94aa3385875fa54e7921355b9652bda99e42d436  acceptance/harness/migra/src/main/java/aceite/Migra.java
085f8e402a20ff18bce4f2e781f28415a48f70ed3a44f94ead39653ffe2a1523  acceptance/lib/aceite_http.py
a6b285f7200136ebf287db86fa3ff0225a15d107b84329135ae37d7c6ce2f7a0  acceptance/lib/comum.sh
79c8a10ff6789f2df99858caf9a7344dd2ca39bc3f181e52bfc576951bffb73e  acceptance/lib/jwks_servidor.py
2523f2b4709477e36367d52faab93438952ec866291f82b67634d5c19acac745  acceptance/regressao/gera-golden.sh
c6e14e4549b56579687f4c31edaabf568377e765378267d4e6d37e65fd5237f7  acceptance/regressao/golden/colunas-modelo-v2.txt
fffe5b22a3e5f67c72006a2039342a6906b20a3a344aa177aeafefe401891da5  acceptance/regressao/golden/funcoes-modelo-v2.txt
d746f2aa5f17b7d3b2cbfd3740759ce75c4e228e6b8aa952eda71f860cebdb21  acceptance/regressao/golden/gatilhos-modelo-v2.txt
d703cb0072418672405992c99d0d9e0f5c2fc48af76c2c6e086b2387e4329227  acceptance/regressao/golden/indep1.neutras
a5dceb1af8e5a6501e3930f66f9bb0b29a582c233b7dd3bf7811cd4c5dfd7507  acceptance/regressao/golden/indep1.sondas
d4565791bf080e9efdc45bac0990f95ef4021ed49a463167200b85cf56b39063  acceptance/regressao/golden/indep2.neutras
e1b5a7fa74242f0d42cd079ed67fffd55a8cede0bbb15a470dd9ca222787a698  acceptance/regressao/golden/indep2.sondas
ded289791f0ba170de44161e1e7477ba8578eb119b137f7c2ed14f81562597a0  acceptance/regressao/golden/rls.neutras
dc768cf8de3ba6541de604da2112c2d6d761577e7ea5c6cd6b8dc5529e793b9d  acceptance/regressao/golden/rls.sondas
ae4b10efc7863255435340ec1af13ca96199b449eb79562453eab9f20690cf23  acceptance/regressao/golden/rt1.sondas
0231e3dcbc62a1cf3ce1825495d39efb7712e36d3fcaed00155478b001023456  acceptance/regressao/golden/rt2.norm
6da525348b05a901f1dbb4715ee26cce906a2e1dc828d5d49bd25da48efe439e  acceptance/regressao/golden/rtn.norm
6f76b1a3ff7f21cc1268f9a74263ddc5112e658807b1bc1bce78a5bb13520759  acceptance/regressao/golden/sondas_r2.neutras
0e96fb54afe5aeb9bb8b7256fe3378821212b8fde3a72ef512ca3019f5c04139  acceptance/regressao/golden/sondas_r2.sondas
e14fed6b4b1e07504ca3de06a1b7e559498cd6529f65c524aff6a01d10988b2b  acceptance/regressao/regressao.py
c09325b78d0ceea05f66696b5d0d5818d6359a233d1688ddb7b3ef89c099192b  acceptance/regressao/regressao.sh
0785a6a01e408d938c2f0ad824d965012233757547145791837deef4e946962e  acceptance/run.sh
d0a5450ca5ebc5b053a2f4b0f9682f3e46d744d2eb8ffddc4dbac246a857a8e0  docs/arquitetura/evidencias/sondas-r2.sql
cc5247b06ecd5465b0bb73514373239c8d386a56c2a74c38aa9aed8853798710  docs/arquitetura/evidencias/teste-r1-independente-r2.sql
c9357487796f3cb7d5f2094703c62dcffcdea5341a1ea24abe913223b6d2478a  docs/arquitetura/evidencias/teste-r1-independente.sh
349bc6dddf4f9b836f85f343e17febe5e3694873e34011d6a9bf2a1fceb07f0d  docs/arquitetura/evidencias/teste-r1-independente.sql
0c074932120be031e3607e3bdd9ce4851cb191d4117d0ac6a4fa0a85fc911f69  docs/arquitetura/evidencias/teste-r2-independente.sh
e767ef4b41045a1016a6661e3696d5cbd68af2930bb0a025e63c471ef979b886  docs/arquitetura/evidencias/teste-r2-independente.sql
c81e871ab3bf30d2f9cfd46d21f2ffc86c299f40683f315c39d321ce1dd4a30a  docs/arquitetura/evidencias/teste-r2.sh
2e723055141af4bd3286e53c82a80b777fbbf834b9a7b5c8114e0d8822f800ed  docs/arquitetura/evidencias/teste-rls-r1.sh
6de6e06b973cec1cb7122829a2a613d886f35c63e501f20ec85091cd81ecf436  docs/arquitetura/evidencias/teste-rls-r1.sql
7f59b0c28a4409819f9dc5e5bc5874c6cd5e4498441c27c6a74693d2f8773af0  docs/arquitetura/evidencias/teste-rls-r2.sql
d5b4c761d86333747e9f80ca4e4b881ae2cd0977de66358981ab11a2a1d5dfce  docs/arquitetura/evidencias/teste-rls.sh
51d9bab255b238a577eb893139c08d22a876dd0a85545c3874b86fc23b63c796  docs/arquitetura/evidencias/teste-rls.sql
4a6f4966378f15294455234e88c131af3481b9fbd14751ab90776e2286dded14  docs/arquitetura/modelo-v2.sql
74d6f7a10f0df9cf91940e191d5ef785af8b74c143ee73f6705bf16c51d44cd3  docs/seguranca/evidencias/red-team-sondas-r1-novas.sql
fc1aba9b9b83fb4fbbe801f664d94cd193a54770abfc4c55fe767d8a907c3578  docs/seguranca/evidencias/red-team-sondas-r1.sql
1c9e9b69d0b949aea7dc79c39a8e9e57b227c224dcad48347a3a90a081dab3fa  docs/seguranca/evidencias/red-team-sondas-r2.sql
e9435795fbdc0d3971cef04546a20d9c725d9d45a3ef9ec103c4f6851d293c6e  docs/seguranca/evidencias/red-team-sondas.sql
```
| 1 | 2026-11-17 | F1 | 61df927 | APROVADO | 6 VERDE 0 VERMELHO | n/a (sem banco ainda) | Sucesso F1 |
| 2 | 2026-11-17 | F2 | 180e31a | APROVADO (ressalvas: DELETE no histórico Flyway na reversão; filtro de funções só saas_funcoes) | 9 VERDE 0 VERMELHO; F1 6/6 | F2.9 verde | Sucesso F2 |
| 3 | 2026-11-17 | F3 | f9c7c3b | REPROVADO: fusão com nascimento NULL, coalesce I-22, I-23 aberto em leitura/reagendamento, telefone_contato legível | 4 VERDE; F2 9/9; F1 6/6 | F2.9 verde | Devolver ao Executor (aceite verde não basta) |
| 4 | 2026-11-17 | F3 | 80e057e (após bloqueio resolvido: Arquiteto 00e1faa adaptou só a semente da regressão) | APROVADO (obs.: ramo PACIENTE sem encaminhamento_id usa paciente.telefone, cuidar em F4) | 4 VERDE; F2 9/9; F1 6/6 | F2.9 verde | Sucesso F3 |
| 5 | 2026-11-17 | F4 | b719945 | REPROVADO: alerta DDL cego a GRANT/SET SCHEMA/RENAME; envio PREPARADO sai após cancelamento; volume contornável por vários destinatários com o mesmo telefone | 5 VERDE; F3 4/4; F2 9/9; F1 6/6 | F2.9 verde | Devolver ao Executor |
| 6 | 2026-11-17 | F4 | 9580ae9 | APROVADO com ressalvas não bloqueantes | 5 VERDE; F3 4/4; F2 9/9; F1 6/6 | F2.9 verde | Sucesso F4; ressalvas b e c viram pendência |

## Pendências registradas pelo Orquestrador (não bloqueiam feature já aprovada)

- P1 (F4, Revisor): normalizar telefone sem DDD/8 dígitos antes da contagem de volume (V3:61).
- P2 (F4, Revisor): contagem de volume chama envio_contato por envio da última hora (custo quadrático) (V3:209-212).
- P3 (F4, Revisor): todo GRANT/REVOKE gera ALERTA_DDL_SAAS, inclusive das migrações legítimas; o alarme precisa correlacionar com execução do pipeline (ADR-0039).
- P4 (F3, Negócio): nascimento presente em só um dos registros com CPF e nome iguais funde as pessoas (spec F3.1). Decisão do Luiz se quer endurecer.
| 7 | 2026-11-17 | F5 | d78abbc | REPROVADO: guarda não pega função de política trocada, SECURITY DEFINER, GRANT PUBLIC, COPY PROGRAM, SET ROLE, row_security, dblink, OWNER TO; sem CODEOWNERS; job com write; actions por tag | 9 VERDE; F1-F4 verdes | F2.9 verde | Devolver ao Executor |
| 8 | 2026-11-17 | F5 | 1b309cf (após bloqueio: GRANT restrito conforme F5.4) | REPROVADO: GRANT restrito vale para tabela sensível; DROP INDEX único passa; CREATE TABLE sem RLS passa; DEFAULT em coluna de tenant passa; guarda roda a versão do próprio PR | 9 VERDE; F1-F4 verdes | F2.9 verde | Devolver ao Executor (última tentativa) |
| 9 | 2026-11-17 | F5 | 1b934f7 (após Arquiteto 6400035 endurecer F5) | APROVADO (ressalvas: DEFAULT em tenant via ADD COLUMN/CREATE TABLE; aprovacoes depende do CODEOWNERS) | 9 VERDE; F1-F4 verdes | F2.9 verde | Sucesso F5 |
- P5 (F5, Revisor): ADD COLUMN clinica_id DEFAULT x e CREATE TABLE com DEFAULT em tenant passam na guarda (ADR-0040).
- P6 (F5, Negócio): usuário do GitHub do Luiz para o CODEOWNERS e proteção de branch com code owners ligada; até lá aprovacoes.sha256 pode ser autoaprovado no PR.
| 10 | 2026-11-17 | F6 | 19d7241 | APROVADO (ressalvas: refresh de JWKS sem limite por kid desconhecido; 12 h duplicado cookie/banco; SAAS_PROCESSO=jobs para F7) | 7 VERDE; F1-F5 verdes | F2.9 verde | Sucesso F6 |
- P7 (F6, Revisor): refresh da JWKS a cada kid desconhecido sem limite de taxa (ConfiguracaoAutenticacao.java:98).
- P8 (F6, Revisor): duração de 12 h da sessão duplicada no cookie e no banco.
