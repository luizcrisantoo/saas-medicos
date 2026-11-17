# Red Team final da Fase 2 (iteração 16)

Autor: Red Team da Operação v2. Data: 2026-11-17. Alvo: HEAD f24391e.
Método: leitura de todo o código mais execução real (PostgreSQL 16 efêmero com bootstrap + V1/V3
aplicadas, jar `bootJar` de produção subido com JWKS local instrumentado, guarda de migração contra
15 migrações maliciosas, planos JSON de F10). Sondas e scripts em `/tmp/redteam/` (fora do repo).
Nenhum arquivo do repositório foi alterado além deste relatório.

## 1. Resumo executivo

Veredito: **LIBERA COM CORREÇÕES**. O aceite verde é confiável: não achei reward hacking que derrube
um gate declarado da Fase 2. As defesas centrais (RLS como defesa em profundidade, isolamento de
tenant, trava de privilégio do `saas_app`, guarda de migração, validação de JWT, teste de arquitetura
de I-20, alerta de DDL) resistiram a todos os ataques diretos. Os três achados mais graves são de
endurecimento/disponibilidade, não de vazamento:
1. **RT3-1 (MÉDIO):** refresh da JWKS sem limite de taxa - cada token com `kid` desconhecido força
   1 busca externa à JWKS (amplificação 1:1, pré-autenticação). Confirma e eleva a pendência P7.
2. **RT3-2 (ALTO, condicional/conhecido):** `mfa_configuration` default `OPTIONAL` em prod - um
   `apply` de prod hoje deixa ADMIN/MEDICO sem segundo fator (E-10/ADR-0007). É a BLOQUEANTE B2 e a
   pendência P17a, já registradas; continua um risco vivo até B2 ser decidida.
3. **RT3-3 (BAIXO):** o resource server aceita token assinado com RSA-1024 e com `exp` em futuro
   distante - sem mínimo de tamanho de chave nem teto de validade. Só explorável se o atacante
   controlasse a JWKS (não controla: é a do Cognito).

Nenhum achado CRÍTICO. Nenhuma correção bloqueia o fechamento da Fase 2 por si só, mas RT3-1 e a
tornar-obrigatória do MFA de prod deveriam entrar antes de qualquer `apply` em produção.

## 2. Tabela de achados

| id | sev | feature | gate | título |
|---|---|---|---|---|
| RT3-1 | MÉDIO | F6 | E-10 / P7 | Refresh da JWKS sem rate limit: 1 busca externa por `kid` desconhecido (pré-auth) |
| RT3-2 | ALTO* | F10/F6 | E-10 / B2 / P17a | `mfa_configuration` default `OPTIONAL` em prod (ADMIN/MEDICO sem MFA ao aplicar) |
| RT3-3 | BAIXO | F6 | E-10 | Sem mínimo de tamanho de chave RSA e sem teto de `exp` no resource server |
| RT3-4 | BAIXO | F4 | R-07/R-08 | Alerta de DDL cego a objeto em schema fora de `saas` criado por superusuário |
| RT3-5 | BAIXO | F9 | LGPD / P12 | Consentimento sem índice único: concessões concorrentes duplicam o ativo |
| RT3-6 | INFO | F7 | I-20 | `saas_app` enxerga `query` de backends com `track_activities` ligado em `pg_stat_activity` |

(*) RT3-2 é ALTO em impacto mas já está coberto como BLOQUEANTE B2 (F11 VERMELHO) e pendência P17a;
não é achado novo, é reclassificação do risco residual.

## 3. Achados (reproduzíveis)

### RT3-1 (MÉDIO): JWKS sem rate limit, amplificação 1:1 pré-autenticação

**O que tentei.** JWKS local instrumentado (conta requisições em `/tmp/redteam/jwksdir/contador`).
Enviei 40 POST `/api/sessao/equipe` com `Bearer` válido na assinatura mas `kid` distinto e inexistente
(`unknown-kid-0..39`), medindo tempo e contador da JWKS (`/tmp/redteam/dos.py`).

**O que obtive.**
```
contador JWKS antes: 3
40 tokens com kid desconhecido: tempo total 0.39s, media 9ms, max 23ms
contador JWKS depois: 43        <-- +40: exatamente 1 busca externa por requisição
health apos ataque: 200
```
Cada `kid` desconhecido dispara uma busca à JWKS; não há cache negativo nem janela de taxa. A app
continuou de pé (não é DoS local), mas um atacante não autenticado controla 1 requisição de saída à
JWKS do Cognito por requisição de entrada, sem backoff.

**Por que importa.** Endpoint pré-autenticação. Se o atacante estourar o rate limit da JWKS do
Cognito, as buscas passam a falhar e a validação de **todo** token legítimo cai junto: a equipe inteira
fica sem conseguir abrir sessão (disponibilidade). É a materialização da pendência P7
(`ConfiguracaoAutenticacao`), que estava registrada como não bloqueante.

**Correção (1-3 linhas).** Construir o `JwtDecoder` com um `JWKSource` com cache + rate limit
explícitos (Nimbus `JWKSourceBuilder.create(uri).rateLimited(Duration).cache(...)`) e repassá-lo ao
`NimbusJwtDecoder.withJwkSource(...)`, em vez de `withJwkSetUri(...)` cru; ou pôr um limitador por IP
no `/api/sessao/equipe`.

**Aceite pega?** Não. F6.3 testa `kid desconhecido` e exige 401 (que a app devolve corretamente), mas
não exercita volume. Reward hacking na dimensão de disponibilidade: passa no aceite, falha no ataque.

### RT3-2 (ALTO, condicional): MFA `OPTIONAL` default em prod

**O que tentei.** Li `infra/terraform/ambientes/prod/variaveis.tf` e os planos JSON gerados.

**O que obtive.**
```
prod/variaveis.tf: variable "mfa_configuration" { ... default = "OPTIONAL" }
ambientes_prod-5.0.json: "mfa_configuration": "OPTIONAL"  (x2)
```
`terraform apply` de prod sem `-var mfa_configuration=ON` sobe o user pool com MFA opcional. O
resource server (F6) não confere MFA (F11 bloqueada), então ADMIN e MEDICO autenticam só com senha.

**Por que importa.** Contraria ADR-0007 ("MFA obrigatório para ADMIN e MEDICO") e deixa E-10 aberto em
prod. O Cognito aplica senha de 12+ (ASVS 2), mas o segundo fator não é forçado.

**Correção.** Em prod, remover o default (tornar `mfa_configuration` obrigatória) ou forçar `"ON"`
quando `local.prod`, até B2 ser decidida. O próprio Executor sugeriu isso em P17a.

**Aceite pega?** Não, e corretamente: F11 está VERMELHO/BLOQUEADO e a Fase 2 não reivindica MFA. É
risco residual conhecido (B2/P17a), reafirmado aqui porque um `apply` de prod hoje já o materializa.

### RT3-3 (BAIXO): Sem mínimo de chave RSA e sem teto de `exp`

**O que tentei.** JWKS servindo uma chave RSA-1024 (`kid=rt-1024`, publicada) além da k1 2048.
Tokens assinados com a chave de 1024 bits e um token válido com `exp` ~74 anos no futuro
(`/tmp/redteam/jwtatk.py`).

**O que obtive.**
```
!!!! assinado com RSA-1024 (kid publicado): status=204 (esperado rejeita)
OK   exp ano ~2100 (aceita?): status=204
```
O resource server aceita assinatura RSA-1024 e `exp` arbitrariamente distante.

**Por que importa.** Defesa em profundidade: o Nimbus/Spring não impõe tamanho mínimo de chave nem
teto de validade. Só explorável se a JWKS fosse controlada pelo atacante - não é, é a URI fixa do
Cognito (que emite RSA-2048 e tokens de ≤60 min, F10.7). Risco prático baixo.

**Correção.** Opcional: validar `exp - iat ≤ 65 min` num `OAuth2TokenValidator` e, se o SDK permitir,
recusar chave < 2048 bits.

**Aceite pega?** Não exercita esses casos (fora da matriz F6.3), mas também não são atacáveis na
topologia real. Hardening, não reward hacking.

### RT3-4 (BAIXO): Alerta de DDL cego a objeto fora de `saas` por superusuário

**O que tentei.** Com os gatilhos de evento do `bootstrap.sql` ativos, rodei DDL variado e conferi o
log do servidor (`/tmp/redteam/` sobre o PGLOG do cluster efêmero).

**O que obtive.** Todos os casos escondidos de F4 **alertam**, inclusive com ROLLBACK:
```
1 ALERTA_DDL_SAAS: ALTER TABLE saas.encaminhamento       (ENABLE TRIGGER)
1 ALERTA_DDL_SAAS: ALTER TABLE saas.paciente             (SET (fillfactor=...))
1 ALERTA_DDL_SAAS: COMMENT saas.paciente
1 ALERTA_DDL_SAAS: CREATE INDEX saas.rt_idx_fn           (expressao com funcao)
1 ALERTA_DDL_SAAS: CREATE POLICY rt_tmp on saas.paciente (em transacao com ROLLBACK)
```
Mas o controle de exfiltração **não** alertou:
```
8) superuser: CREATE VIEW public.rt_leak AS SELECT * FROM saas.paciente;
   -> (nenhuma linha de alerta)
```
Uma visão em `public` que lê `saas.paciente`, criada pelo superusuário, escapa do alerta
(`schema_name='public'`, dono não é `saas_owner`/`saas_funcoes`, `pelo_papel` falso). Como a visão roda
com os privilégios do dono superusuário, exporia todas as linhas de paciente a quem tivesse SELECT nela.

**Por que importa.** R-07/R-08 querem detectar adulteração de schema, inclusive por admin comprometido.
Este caminho de exfiltração entre schemas não é detectado.

**Ressalva de severidade (BAIXO).** Exige superusuário (o admin do RDS), que está fora do modelo de
ameaça do `saas_app`: um superusuário também pode `SELECT` direto (ignora RLS) ou desligar o próprio
gatilho de evento. O alerta nunca defende contra o superusuário por construção. Fica como caso a
acrescentar ao aceite, não como bloqueio.

**Correção.** Ampliar `saas_alerta_ddl()` para alertar quando um objeto novo (visão, função,
matview) referencia `pg_class`/`pg_depend` de `saas`, mesmo fora do schema `saas`.

**Aceite pega?** Não - F4 só verifica DDL com alvo/dono em `saas`; o caso entre schemas não é testado.

### RT3-5 (BAIXO): Consentimento sem índice único: duplicata sob concorrência

**O que tentei.** Leitura de `V1__modelo_v2.sql` (tabela `consentimento` e índices) e de
`ConsentimentoServico.conceder` (padrão SELECT `EXISTENTE` seguido de INSERT).

**O que obtive.** Só existe `consentimento_enc_idx` (não único). `conceder` faz check-then-act sem
trava: dois `POST /api/consentimentos` concorrentes para o mesmo (paciente, encaminhamento,
finalidade, versão) passam ambos pelo `EXISTENTE` vazio e inserem dois ativos.

**Por que importa.** Idempotência da concessão derrotada; registros LGPD duplicados. Não é escalada de
acesso (a visibilidade usa EXISTS, duplicata não amplia). Confirma P12.

**Correção.** `CREATE UNIQUE INDEX ... ON consentimento (paciente_id, encaminhamento_id, finalidade)
WHERE revogado_em IS NULL` (migração aprovada pela guarda).

**Aceite pega?** F9.5 testa revogação/idempotência serial, não o INSERT concorrente.

### RT3-6 (INFO): `pg_stat_activity` visível ao `saas_app`

`saas_app` lê `query` de backends em `pg_stat_activity`. Os papéis da aplicação têm
`track_activities=off` (bootstrap), então **as próprias** consultas não aparecem; só apareceriam
backends com rastreio ligado (ex.: `saas_migracao`, que não desligou `track_activities`). Como tokens
vão como parâmetros ligados (não no texto) e os papéis de app têm rastreio off, não há vazamento de
token comprovado. Hardening: ligar `track_activities=off` também em `saas_migracao` ou restringir
`pg_stat_activity`.

## 4. Ataques que FALHARAM (a defesa segurou)

- **Isolamento de tenant por HTTP:** adminA com `X-Clinica-Id` da clínica B → `200 []` (0 eventos); RLS
  bloqueia mesmo a app repassando o cabeçalho (`tenant.py`: cross-tenant=0, papel forjado=0, papel
  inválido=403, cookie desconhecido=401). Cabeçalho do cliente NÃO é confiado.
- **Escalada de privilégio como `saas_app`:** `SET ROLE` (owner/funcoes/migracao), ler
  `sessao`/`link_paciente`, `jobs_*`, `sessao_equipe_abre`, `sessao_valida`, CREATE em `saas`/`public`,
  COPY PROGRAM, `pg_read_file`, `pg_authid`, self-GRANT, DELETE/UPDATE em tabelas - **todos negados**.
- **Defesa em profundidade RLS:** com `app.clinica_id`/`app.papel` forjados e sem sessão válida,
  `paciente`/`evento_auditoria`/`encaminhamento` = 0 linhas; `eh_equipe` = falso.
- **Guarda de migração (15 migrações maliciosas):** `ALTER TABLE OF`/`INHERIT`, CREATE OR REPLACE de
  função de política, `ALTER FUNCTION SECURITY DEFINER`, `ALTER DEFAULT PRIVILEGES`, GRANT via
  `DO/format`, `\i`, `OWNER TO`, `CREATE EXTENSION`, `ALTER ROLE BYPASSRLS`, `CREATE PUBLICATION`,
  `ALTER SYSTEM`, `ENABLE TRIGGER`, `SECURITY LABEL` - **todas RECUSADAS**. (`COMMENT ON TABLE` passa,
  intencional e inócuo.)
- **Matriz de JWT (além de F6.3):** `nbf` futuro, `token_use=id` com `client_id`, `aud` estrangeiro,
  `aud` mista, `iss` com host maiúsculo, sem `sub` - **todos 401**. (A matriz do aceite já cobre `alg
  none`, HS256 com chave pública, `kid` de outra chave, `iss` com sufixo, expirado, malformado.)
- **Teste de arquitetura de I-20:** `ContextoArquiteturaTest.verificaJava` varre TODO `src/main/java` e
  os `.sql`; o controle negativo embutido reprova concatenação em `jdbc.queryForList`, variável local
  montada, `String.format`, `.formatted`, text block montado, `StringBuilder`, `.concat`, constante não
  literal, repasse não declarado e `leitor.ids("..."+n)` - cobre o mutante alternativo pedido (não só
  `set_config`).
- **Alerta de DDL:** dispara para política/gatilho/regra/ENABLE TRIGGER/COMMENT/CREATE INDEX com
  função, **mesmo com ROLLBACK** (RAISE LOG não participa do rollback e LOG ≥ WARNING no log do
  servidor).
- **Arquivos (F8):** chave S3 opaca (UUID, sem id de paciente/caso); MIME por conjunto exato (params,
  caixa, espaço, `\u0000`, `svg+xml` reprovados); tamanho 0/negativo/>20 MiB reprovado; `UrlAssinada`
  e os serviços nunca logam a URL; download de anexo alheio barrado por RLS (`anexo_ver`); auditoria na
  mesma transação (falha → sem URL).
- **LGPD:** revogar consentimento alheio → 0 linhas → NAO_ENCONTRADO (IDOR barrado por RLS); corpo com
  `pacienteId`/`textoAceito`/`canal` forjados ignorado (servidor manda); versão antiga → recusada.
- **Meta:** nenhum `@Disabled`/`assumeTrue`, catch vazio, detecção de ambiente (porta/variável/
  user-agent) ou propriedade que mude comportamento em produção. Perfis `web`/`jobs` limpos.
- **Terraform:** RDS privado/cifrado/PITR/force_ssl/deletion_protection; S3 com block público total,
  SSE-KMS de chave própria, política que nega sem TLS/sem SSE-KMS/chave errada; KMS com rotação; sem
  IAM `*`; sem segredo em claro; filtro de métrica casa o log group real
  `/aws/rds/instance/<id>/postgresql`; token de 60 min com revogação.

## 5. Ressalvas P1–P17 reclassificadas

- **P7 (F6) → RT3-1 (MÉDIO), exploitável.** Sobe de pendência a achado: amplificação 1:1 pré-auth
  medida.
- **P12 (F9) → RT3-5 (BAIXO), exploitável como duplicata.** Não é escalada; integridade de dado.
- **P17a (F10, MFA prod) → RT3-2 (ALTO condicional).** Risco vivo ao aplicar prod; dentro de B2.
- **P1 (F4, telefone sem DDD no volume): MITIGADA na V3.** `telefone_normalizado` soma variações de
  grafia/DDD (`+55 (81)...`, `081...`, `81...`). Residual mínimo: números com menos de 10 dígitos (sem
  DDD real) ainda não ganham o `55` e contam à parte - irrelevante para WhatsApp, que exige número
  completo. Baixíssimo.
- **P13 (F10, `s3:DeleteObject` no web): mantida (BAIXO).** Sem caso de uso em F8; remover.
- **P2, P3, P5, P6, P8, P9, P10, P11, P14, P15, P16, P17b/c:** não exploráveis como falha de segurança
  nesta fase (custo, performance, infra a definir, IP atrás de balanceador, retenção). Sem mudança.

## 6. Novos casos escondidos recomendados ao Arquiteto

- **F6:** flood de `kid` desconhecido não deve gerar N buscas à JWKS (teste de taxa/contador externo).
- **F6:** token com `exp - iat` acima do teto do Cognito (ex.: 24 h) e chave RSA < 2048 devem ser
  recusados (defesa em profundidade).
- **F4:** objeto em schema fora de `saas` (visão/função/matview) que referencia tabela de `saas`,
  criado por papel não-`saas`, deve gerar `ALERTA_DDL_SAAS`.
- **F9:** dois `POST /api/consentimentos` concorrentes para o mesmo (paciente, caso, finalidade,
  versão) não podem resultar em dois consentimentos ativos (exige índice único parcial).
- **F10:** `apply` de prod sem `-var mfa_configuration` deve falhar (variável obrigatória) enquanto B2
  não for decidida; aceite poderia exigir que o plano de prod não traga `OPTIONAL`.

## 7. Notas de execução

- Tudo acima foi executado contra o cluster efêmero e o jar de produção, salvo onde marcado
  **[SUPOSIÇÃO]** - e não houve nenhuma: todos os achados têm saída real. A única limitação técnica foi
  o `cryptography` local recusar chave RSA < 1024 bits, então o teste de "chave fraca" usou 1024 em vez
  de 512; a conclusão (sem mínimo de tamanho de chave) vale igual.
- Dados usados nas sondas são fictícios (`f6-sub-recepcao`, clínicas A/B com UUID de teste); nenhum
  dado real de pessoa.
