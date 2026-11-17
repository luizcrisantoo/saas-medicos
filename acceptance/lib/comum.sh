# shellcheck shell=bash
# Biblioteca comum dos testes de aceite da Fase 2. Fonte: acceptance/run.sh.
# Nada aqui pertence ao Executor; este diretorio inteiro tem checksum em docs/fase2/progresso.md.

ACC="${ACC:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
RAIZ="${RAIZ:-$(cd "$ACC/.." && pwd)}"
PGBIN="${PGBIN:-/usr/lib/postgresql/16/bin}"
BIN="$ACC/.bin"
export PATH="$BIN:$PATH"
TMPA="${TMPA:-$ACC/.tmp}"
mkdir -p "$TMPA"

# ---------------------------------------------------------------- criterios
declare -a CRIT_IDS=()
declare -A CRIT_DESC=() CRIT_RES=() CRIT_MOT=()

declara() { # id descricao
  CRIT_IDS+=("$1"); CRIT_DESC[$1]="$2"; CRIT_RES[$1]=""; CRIT_MOT[$1]="nao executado"
}
verde()    { CRIT_RES[$1]=VERDE; CRIT_MOT[$1]=""; }
vermelho() { CRIT_RES[$1]=VERMELHO; CRIT_MOT[$1]="${2:-falhou}"; }
# marca id pelo codigo de saida de um comando (stdout/stderr vao para o log da feature)
confere()  { local id=$1; shift; if "$@" >>"$LOGF" 2>&1; then verde "$id"; else vermelho "$id" "${MOTIVO:-comando falhou: $*}"; fi; MOTIVO=""; }
# todos os criterios ainda nao marcados ficam vermelhos com o motivo dado
pendentes_vermelhos() { local id; for id in "${CRIT_IDS[@]}"; do [ -z "${CRIT_RES[$id]}" ] && vermelho "$id" "$1"; done; true; }

imprime_criterios() { # imprime e acumula contadores globais
  local id
  for id in "${CRIT_IDS[@]}"; do
    [ -z "${CRIT_RES[$id]}" ] && CRIT_RES[$id]=VERMELHO
    if [ "${CRIT_RES[$id]}" = VERDE ]; then
      printf 'VERDE     %-8s %s\n' "$id" "${CRIT_DESC[$id]}"; N_VERDE=$((N_VERDE+1))
    else
      printf 'VERMELHO  %-8s %s  [%s]\n' "$id" "${CRIT_DESC[$id]}" "${CRIT_MOT[$id]}"; N_VERMELHO=$((N_VERMELHO+1))
    fi
  done
  CRIT_IDS=(); CRIT_DESC=(); CRIT_RES=(); CRIT_MOT=()
}

# ---------------------------------------------------------------- utilitarios
porta_livre() { python3 -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1]);s.close()'; }
senha() { python3 -c 'import secrets;print(secrets.token_hex(16))'; }
sha256hex() { printf '%s' "$1" | sha256sum | cut -d' ' -f1; }

# copia o repositorio do Executor para um diretorio temporario (nunca altera a arvore dele)
copia_repo() { # destino
  local d=$1; rm -rf "$d"; mkdir -p "$d"
  ( cd "$RAIZ" && tar --exclude=./.git --exclude=./acceptance/.bin --exclude=./acceptance/.tmp \
      --exclude='./build' --exclude='./.gradle' --exclude='*/build' -cf - . ) | ( cd "$d" && tar -xf - )
}

# ---------------------------------------------------------------- PostgreSQL efemero
# Cluster novo por chamada, dono pgtest (nao-root), socket proprio, TCP so em 127.0.0.1.
# local = trust (baterias usam \c com papeis reais); TCP = scram (credenciais separadas valem).
pg_sobe() { # nome [opcoes extras do postgres]
  local nome=$1; shift || true
  getent passwd pgtest >/dev/null || useradd --system --no-create-home --shell /usr/sbin/nologin pgtest
  PGDIR=$(mktemp -d "/tmp/aceite-pg-$nome-XXXX"); chown pgtest:pgtest "$PGDIR"; chmod 700 "$PGDIR"
  PGPORTA=$(porta_livre)
  runuser -u pgtest -- "$PGBIN/initdb" -D "$PGDIR/data" -U pgtest --auth-local=trust --auth-host=scram-sha-256 \
      -E UTF8 --locale=C.UTF-8 >/dev/null || return 1
  PGLOG="$PGDIR/pg.log"
  runuser -u pgtest -- "$PGBIN/pg_ctl" -D "$PGDIR/data" -w -l "$PGLOG" -o \
    "-p $PGPORTA -k $PGDIR -c listen_addresses=127.0.0.1 -c shared_preload_libraries=pg_stat_statements -c pg_stat_statements.track_utility=on -c log_connections=on -c log_statement=all -c log_line_prefix='%m [%p] %u@%d ' $*" \
    start >/dev/null || return 1
  PSU="psql -X -q -h $PGDIR -p $PGPORTA -U pgtest"
  export PGDIR PGPORTA PGLOG PSU
}
pg_desce() {
  [ -n "${PGDIR:-}" ] && [ -f "$PGDIR/data/postmaster.pid" ] && \
    runuser -u pgtest -- "$PGBIN/pg_ctl" -D "$PGDIR/data" -m fast -w stop >/dev/null 2>&1
  [ -n "${PGDIR:-}" ] && { cp -f "$PGLOG" "$TMPA/ultimo-pg-${PGPORTA}.log" 2>/dev/null; rm -rf "$PGDIR"; }
  PGDIR=""; true
}

# ---------------------------------------------------------------- migracao (contrato do spec, secao 3)
MIGRA="$ACC/harness/migra/build/install/migra/bin/migra"
harness_migra() {
  if [ ! -x "$MIGRA" ]; then ( cd "$ACC/harness/migra" && gradle -q installDist --no-daemon ) >>"${LOGF:-/dev/null}" 2>&1 || return 1; fi
}
BOOT="$RAIZ/infra/db/bootstrap.sql"
MIGDIR="$RAIZ/src/main/resources/db/migration"
REVDIR="$RAIZ/src/main/resources/db/reversao"

# cria banco, roda bootstrap como superusuario, define senhas dos papeis de login (o bootstrap nao tem senha)
banco_bootstrap() { # db
  local db=$1
  [ -f "$BOOT" ] || { echo "falta $BOOT"; return 1; }
  $PSU -d postgres -c "create database $db" || return 1
  $PSU -d "$db" -v ON_ERROR_STOP=1 -f "$BOOT" || return 1
  : "${PW_APP:=$(senha)}" "${PW_JOBS:=$(senha)}" "${PW_AUTH:=$(senha)}" "${PW_MIGRA:=$(senha)}"
  export PW_APP PW_JOBS PW_AUTH PW_MIGRA
  $PSU -d "$db" -v ON_ERROR_STOP=1 \
    -c "alter role saas_app password '$PW_APP'" -c "alter role saas_jobs password '$PW_JOBS'" \
    -c "alter role saas_auth password '$PW_AUTH'" -c "alter role saas_migracao password '$PW_MIGRA'" >/dev/null 2>&1 || return 1
}
jdbc() { echo "jdbc:postgresql://127.0.0.1:$PGPORTA/$1"; }
flyway_migra() { # db [alvo|info|validate]
  harness_migra || return 1
  "$MIGRA" "$(jdbc "$1")" saas_migracao "$PW_MIGRA" "$MIGDIR" "${2:-latest}"
}
banco_migrado() { # db : bootstrap + flyway ate a ultima versao
  banco_bootstrap "$1" && flyway_migra "$1"
}

# ---------------------------------------------------------------- aplicacao (contrato do spec, secao 3)
app_jar() { # imprime o jar executavel gerado por ./gradlew bootJar na copia indicada
  ls "$1"/build/libs/*.jar 2>/dev/null | grep -v -- '-plain.jar' | head -1
}
APP_PIDS=()
app_sobe() { # jar porta log [args...] ; ambiente ja exportado pelo chamador
  local jar=$1 porta=$2 log=$3; shift 3
  java -jar "$jar" --server.port="$porta" "$@" >"$log" 2>&1 &
  APP_PIDS+=($!)
  local i; for i in $(seq 1 120); do
    if curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$porta/actuator/health" 2>/dev/null | grep -q 200; then return 0; fi
    kill -0 "${APP_PIDS[-1]}" 2>/dev/null || return 1
    sleep 1
  done
  return 1
}
apps_desce() { local p; for p in "${APP_PIDS[@]:-}"; do [ -n "$p" ] && kill "$p" 2>/dev/null; done; sleep 1
  for p in "${APP_PIDS[@]:-}"; do [ -n "$p" ] && kill -9 "$p" 2>/dev/null; done; APP_PIDS=(); true; }

# ---------------------------------------------------------------- sondas SQL com tabela aceite.res
# roda_sondas db arquivo : executa as sondas (como superusuario do cluster efemero)
roda_sondas() { PGHOST=$PGDIR PGPORT=$PGPORTA $PSU -d "$1" -f "$2" >"$TMPA/$(basename "$2").out" 2>&1; }
# crit_res db crit : verde se ha linhas do criterio e todas ok; MOTIVO lista as que falharam
crit_res() {
  local n f
  n=$($PSU -d "$1" -Atc "select count(*) from aceite.res where crit = '$2'" 2>/dev/null || echo 0)
  f=$($PSU -d "$1" -Atc "select descricao||' (esperado '||esperado||', obtido '||left(obtido,60)||')' from aceite.res where crit = '$2' and ok is not true order by n" 2>/dev/null)
  if [ "${n:-0}" -gt 0 ] && [ -z "$f" ]; then return 0; fi
  if [ "${n:-0}" -eq 0 ]; then MOTIVO="nenhuma sonda do criterio rodou (ver $TMPA/*.sql.out)"; else MOTIVO="$(echo "$f" | head -2 | tr '\n' ';' | cut -c1-300)"; fi
  return 1
}

# ---------------------------------------------------------------- aplicacao HTTP (F6 a F9)
AUTH_ISSUER="https://cognito-idp.sa-east-1.amazonaws.com/sa-east-1_AceiteFase2"
AUTH_CLIENTES="aceite-cliente-web,aceite-cliente-2"
app_build() { # gera o bootJar numa copia (cache pelo hash da arvore do Executor) -> APP_JAR
  local h
  h=$(cd "$RAIZ" && find . \( -path ./acceptance -o -path ./.git -o -path ./docs -o -name build -o -name .gradle \) -prune -o -type f -print0 \
      | sort -z | xargs -0 sha256sum 2>/dev/null | sha256sum | cut -c1-16)
  APP_JAR="$TMPA/app-$h.jar"; [ -f "$APP_JAR" ] && return 0
  local C="$TMPA/app-copia-$$"; copia_repo "$C"
  [ -x "$C/gradlew" ] || { echo "sem gradlew"; return 1; }
  ( cd "$C" && timeout 1800 ./gradlew --no-daemon -q bootJar ) >>"$LOGF" 2>&1 || { rm -rf "$C"; return 1; }
  local j; j=$(app_jar "$C"); [ -n "$j" ] || { rm -rf "$C"; return 1; }
  cp "$j" "$APP_JAR"; rm -rf "$C"
}
jwks_sobe() {
  JWKS_PORTA=$(porta_livre); JWKS_DIR="$TMPA/jwks-$$"; rm -rf "$JWKS_DIR"
  python3 "$ACC/lib/jwks_servidor.py" "$JWKS_PORTA" "$JWKS_DIR" >>"$LOGF" 2>&1 &
  JWKS_PID=$!
  local i; for i in $(seq 1 50); do [ -f "$JWKS_DIR/pronto" ] && break; sleep 0.2; done
  export JWKS_PORTA JWKS_DIR AUTH_ISSUER AUTH_CLIENTES
  [ -f "$JWKS_DIR/pronto" ]
}
jwks_desce() { [ -n "${JWKS_PID:-}" ] && kill "$JWKS_PID" 2>/dev/null; true; }
app_env_web() { # db : ambiente do processo web (contrato do spec, secao 3.3). Sem credencial de jobs.
  export SAAS_PROCESSO=web
  export SPRING_DATASOURCE_URL="$(jdbc "$1")" SPRING_DATASOURCE_USERNAME=saas_app SPRING_DATASOURCE_PASSWORD="$PW_APP"
  export SAAS_DB_AUTH_URL="$(jdbc "$1")" SAAS_DB_AUTH_USERNAME=saas_auth SAAS_DB_AUTH_PASSWORD="$PW_AUTH"
  export SAAS_AUTH_ISSUER="$AUTH_ISSUER" SAAS_AUTH_JWKS_URI="http://127.0.0.1:$JWKS_PORTA/jwks.json" SAAS_AUTH_CLIENT_IDS="$AUTH_CLIENTES"
  export SAAS_S3_BUCKET=aceite-anexos-homolog SAAS_S3_KMS_KEY_ID="arn:aws:kms:sa-east-1:111122223333:key/0b0b0b0b-aaaa-4bbb-8ccc-0d0d0d0d0d0d"
  export AWS_REGION=sa-east-1 AWS_ACCESS_KEY_ID=AKIAACEITEFASE2TESTE AWS_SECRET_ACCESS_KEY=aceite-segredo-falso-nao-e-real-0000000000
  export SPRING_FLYWAY_ENABLED=false
  unset SAAS_DB_JOBS_URL SAAS_DB_JOBS_USERNAME SAAS_DB_JOBS_PASSWORD
  # F7 (E-09, caso escondido): a credencial de jobs fica no ambiente do web e o web nao pode usa-la
  if [ "${JOBS_NO_AMBIENTE_WEB:-}" = 1 ]; then
    export SAAS_DB_JOBS_URL="$(jdbc "$1")" SAAS_DB_JOBS_USERNAME=saas_jobs SAAS_DB_JOBS_PASSWORD="$PW_JOBS"
  fi
}
# prepara banco + jar + jwks + app web; uso nas features HTTP. Args: nome_feature arquivo_semente [args extras da app]
app_prepara() {
  local nome=$1 semente=$2; shift 2
  pg_sobe "$nome" || { pendentes_vermelhos "PostgreSQL efemero nao subiu"; return 1; }
  trap 'apps_desce; jwks_desce; pg_desce' EXIT
  banco_migrado modelo >>"$LOGF" 2>&1 || { pendentes_vermelhos "pre-requisito: bootstrap e migracao (F2) falharam"; return 1; }
  $PSU -d postgres -c "create database app template modelo" >/dev/null
  export APP_DB=app
  if [ -n "$semente" ]; then $PSU -d app -v ON_ERROR_STOP=1 -f "$semente" >>"$LOGF" 2>&1 || { pendentes_vermelhos "semente de aceite falhou (contrato do banco mudou? ver $LOGF)"; return 1; }; fi
  app_build || { pendentes_vermelhos "pre-requisito: ./gradlew bootJar falhou ou sem jar"; return 1; }
  jwks_sobe || { pendentes_vermelhos "JWKS local nao subiu"; return 1; }
  app_env_web app
  APP_PORTA=$(porta_livre); APP_LOG="$TMPA/$nome-app.log"
  export APP_URL="http://127.0.0.1:$APP_PORTA"
  APP_L0=$(wc -l <"$PGLOG"); export APP_LOG APP_L0 APP_PORTA
  app_sobe "$APP_JAR" "$APP_PORTA" "$APP_LOG" "$@" || { pendentes_vermelhos "aplicacao nao respondeu 200 em /actuator/health (ver $APP_LOG)"; return 1; }
}
# agrega as linhas 'ok|falha CRIT descricao' de um teste python nos criterios declarados
agrega_py() { # saida
  local id f
  for id in "${CRIT_IDS[@]}"; do
    [ -n "${CRIT_RES[$id]}" ] && continue
    grep -qE "^(ok|falha) $id " <<<"$1" || continue
    f=$(grep -E "^falha $id " <<<"$1" | head -2 | sed "s/^falha $id //" | tr '\n' ';' | cut -c1-300)
    if [ -z "$f" ]; then verde "$id"; else vermelho "$id" "$f"; fi
  done
}
