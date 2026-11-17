# shellcheck shell=bash
# F7: contexto por transacao, pool seguro, isolamento, I-20 e E-09 (credencial de jobs fora do processo web).
TITULO="Contexto de sessao por transacao, pool seguro, I-20 e credencial de jobs separada (E-09)"
aceite() {
  declara F7.1 "GET /api/auditoria: ADMIN de cada clinica ve so a auditoria da propria clinica"
  declara F7.2 "papel declarado sem vinculo, clinica alheia, sem clinica ou sem sessao: nada de auditoria"
  declara F7.3 "com pool de 1 conexao, requisicoes alternadas e concorrentes nunca herdam contexto de outra"
  declara F7.4 "I-20: nenhum token de sessao no log do PostgreSQL (log_statement=all) nem em pg_stat_statements"
  declara F7.5 "o contexto e gravado por set_config com parametro ligado e local a transacao (nada de SET ou literal)"
  declara F7.6 "I-20: o codigo-fonte nao interpola contexto de sessao em SQL"
  declara F7.7 "I-20: um mutante com token interpolado no SQL faz a suite do proprio Executor falhar"
  declara F7.8 "E-09: o processo web, mesmo com a credencial de jobs no ambiente, nunca conecta como saas_jobs"
  declara F7.9 "E-09: o processo de jobs (SAAS_PROCESSO=jobs) sobe so com a credencial de jobs e conecta como saas_jobs, nunca como saas_app ou saas_auth"
  JOBS_NO_AMBIENTE_WEB=1   # caso escondido de E-09
  app_prepara f7 "$ACC/F7/semente-f7.sql" --spring.datasource.hikari.maximum-pool-size=1 --spring.datasource.hikari.minimum-idle=1 || return 0
  local out; out=$(python3 "$ACC/F7/teste_f7.py" 2>&1); echo "$out" >>"$LOGF"
  agrega_py "$out"
  # F7.6 estatico
  local pad
  pad=$(grep -rniE "set_config\(\s*'app\.[a-z_]+'\s*,\s*'(\"|%s|\\$\{|\{)|\bset\s+(local\s+|session\s+)?app\.[a-z_]+\s*(=|to)\s*'?\s*(\"|%s|\\$\{|\{)" \
        "$RAIZ/src/main" 2>/dev/null | head -3)
  if [ -d "$RAIZ/src/main" ] && [ -z "$pad" ]; then verde F7.6; else vermelho F7.6 "${pad:-sem src/main}"; fi
  # F7.8 web nunca conecta como saas_jobs
  local pgw; pgw=$(tail -n +$((APP_L0+1)) "$PGLOG")
  if ! grep -qE "user=saas_jobs|saas_jobs@|user \"saas_jobs\"" <<<"$pgw"; then verde F7.8; else vermelho F7.8 "processo web abriu ou tentou conexao saas_jobs"; fi
  apps_desce
  # F7.9 processo de jobs
  local l1; l1=$(wc -l <"$PGLOG")
  ( unset SPRING_DATASOURCE_URL SPRING_DATASOURCE_USERNAME SPRING_DATASOURCE_PASSWORD SAAS_DB_AUTH_URL SAAS_DB_AUTH_USERNAME SAAS_DB_AUTH_PASSWORD
    export SAAS_PROCESSO=jobs
    exec java -jar "$APP_JAR" --server.port="$(porta_livre)" ) >"$TMPA/f7-jobs.log" 2>&1 &
  local jp=$!; APP_PIDS+=($jp)
  local i ok=0; for i in $(seq 1 45); do sleep 1; tail -n +$((l1+1)) "$PGLOG" | grep -q "connection authorized: user=saas_jobs" && { ok=1; break; }; kill -0 $jp 2>/dev/null || break; done
  sleep 20
  local pgj; pgj=$(tail -n +$((l1+1)) "$PGLOG")
  if [ $ok = 1 ] && kill -0 $jp 2>/dev/null && ! grep -qE "user=saas_app|user=saas_auth|user \"saas_app\"|user \"saas_auth\"" <<<"$pgj"; then verde F7.9
  else vermelho F7.9 "jobs: conectou_saas_jobs=$ok vivo_apos_20s=$(kill -0 $jp 2>/dev/null && echo s || echo n); ver $TMPA/f7-jobs.log"; fi
  apps_desce
  # F7.7 mutante (I-20) numa copia
  local C="$TMPA/F7-copia"; copia_repo "$C"
  if [ -x "$C/gradlew" ] && ! ( cd "$C" && timeout 1800 ./gradlew --no-daemon -q test ) >>"$LOGF" 2>&1; then
    vermelho F7.7 "a suite do Executor ja falha sem o mutante"
  elif [ -x "$C/gradlew" ]; then
    cp -r "$ACC/F7/mutante/saasagenda/." "$C/src/main/java/saasagenda/"
    if ( cd "$C" && timeout 1800 ./gradlew --no-daemon -q test ) >>"$LOGF" 2>&1; then vermelho F7.7 "suite passou com SQL interpolado (falta teste de arquitetura do ADR-0026, item 7)"
    elif ( cd "$C" && timeout 600 ./gradlew --no-daemon -q compileJava ) >>"$LOGF" 2>&1; then verde F7.7
    else vermelho F7.7 "mutante nao compilou (pacote saasagenda.identidade fora do contrato)"; fi
  else vermelho F7.7 "sem gradlew"; fi
  rm -rf "$C"
  pendentes_vermelhos "teste nao produziu resultado (ver $LOGF)"
}
