# ADR-0040: Guarda de migração no CI por análise léxica do SQL, aprovação presa a sha256 e nome

Status: Proposto (Fase 2, F5), sujeito à revisão do Red Team
Data: 2026-11-17
Tarefa: Fase 2, F5 (docs/fase2/spec.md, seções 3.5 e 4)
Completa: ADR-0027 (mitigação operacional de R-07), ADR-0039 (R-08)

## Contexto
O ADR-0027 exige que o CI recuse migração com `DISABLE TRIGGER`, `NO FORCE ROW LEVEL SECURITY`, `DISABLE ROW LEVEL SECURITY`, `DROP POLICY`, `DROP TRIGGER` ou `session_replication_role` sem aprovação explícita; o R-08 acrescenta `CREATE POLICY`, `ALTER POLICY` e `CREATE TRIGGER`. Busca literal de texto é contornada por caixa, quebra de linha, comentário entre as palavras, aspas, escapes em `E''` e `U&''`, literais adjacentes e comandos dentro de `DO` e `EXECUTE`.

## Decisão
1. `scripts/ci/guarda-migracao.sh DIR APROVACOES` chama `scripts/ci/guarda_migracao.py` (Python 3 da biblioteca padrão, sem dependência). Um analisador léxico do SQL do PostgreSQL 16 remove comentários (inclusive aninhados), decodifica literais (`''`, `E''`, `U&''` e `U&""` com `UESCAPE`, dollar quoting com etiqueta), junta literais adjacentes e compara sequências de palavras em minúsculas. Todo literal e todo corpo `$$...$$` (DO, CREATE FUNCTION, EXECUTE) é analisado de novo como SQL, até 16 níveis.
2. Exigem aprovação: as nove construções acima em qualquer grafia; `CREATE [OR REPLACE] [CONSTRAINT] TRIGGER`, `CREATE/ALTER/DROP EVENT TRIGGER`, `CREATE/ALTER/DROP RULE`, `ALTER TRIGGER`, `DISABLE RULE`, `ENABLE REPLICA|ALWAYS TRIGGER|RULE`, `ALTER SYSTEM`, `DROP OWNED`, qualquer `DROP ... CASCADE` (leva gatilho e política dependentes), `CREATE FUNCTION ... RETURNS trigger|event_trigger` (trocar o corpo desliga o gatilho sem tocar nele), `BYPASSRLS` e `SUPERUSER`, escrita direta em tabela `pg_*` ou `pg_catalog`.
3. Na dúvida, recusa: SQL que o analisador não entende (comentário ou literal sem fechamento), `EXECUTE` de expressão não literal (concatenação, `format`, variável), `set_config` com nome não literal, funções que executam texto (`dblink*`, `query_to_xml*`, `ts_stat`, `ts_rewrite`), meta-comando de cliente (`\gexec`), placeholder do Flyway (`${...}`), arquivo que não é `.sql` e link simbólico. O diretório é lido recursivamente porque o Flyway executa callbacks (`beforeMigrate.sql`) da mesma pasta.
4. Aprovação em `src/main/resources/db/aprovacoes.sha256`, formato do `sha256sum` (`<sha256>  <arquivo>`), par (conteúdo exato, nome do arquivo); comentário `#` acima de cada linha com a justificativa. Quem aprova é a revisão do Red Team no PR. Migração e reversão têm o mesmo nome e conteúdos diferentes: cada uma tem a sua linha. Arquivo de aprovações mal formado faz a guarda sair 2.
5. Workflow `.github/workflows/ci.yml` em `pull_request` (e push na principal): `./gradlew build` (inclui `GuardaMigracaoTest`), guarda sobre `db/migration` e `db/reversao`, SAST com CodeQL (`security-extended`), varredura de dependências (grafo do Gradle e `dependency-review-action`, falha a partir de moderada) e gitleaks 8.21.2 baixado com sha256 conferido, sobre o histórico e a árvore, com `.gitleaks.toml` do repositório (regras padrão, sem allowlist; exceção só por fingerprint em `.gitleaksignore`, justificada no PR).

## Alternativas descartadas
- Busca por expressão regular no texto cru: contornada por comentário entre as palavras, escapes e literais adjacentes.
- Parser completo (libpg_query): dependência nativa no CI; o léxico basta porque as regras são sequências de palavras e o SQL dinâmico é recusado em vez de interpretado.
- Aprovação por nome ou por versão do Flyway: o conteúdo podia mudar depois da revisão.

## Consequências
- V1, V2, V3 e as três reversões estão aprovadas (revisadas em F2, F3 e F4).
- Falso positivo aceito: literal de texto que cite uma construção perigosa (por exemplo, `COMMENT ... IS 'DROP POLICY'`) exige aprovação.
- Resíduos: `CREATE OR REPLACE FUNCTION` de função usada por política (não de gatilho) que passa a devolver verdadeiro não é detectado pela guarda (a revisão do PR e o alerta `ALERTA_DDL_SAAS` cobrem); extensão que cria gatilho ao ser instalada; ações do GitHub fixadas por etiqueta de versão, não por sha do commit (trocar por sha quando houver acesso ao GitHub).
- Proteção da branch principal e execução real do pipeline: passo manual do Luiz (spec, seção 7, P6).

## Fontes
- docs/fase2/spec.md, 3.5 e F5; docs/briefing.md, "Pipeline e cadeia de suprimentos"
- docs/seguranca/stride-encaminhamento.md, R-07 e R-08; docs/adr/0027, 0039
- PostgreSQL 16, Lexical Structure (4.1): https://www.postgresql.org/docs/16/sql-syntax-lexical.html
