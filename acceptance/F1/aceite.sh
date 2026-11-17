# shellcheck shell=bash
# F1: esqueleto Spring Boot 3 + Spring Modulith com os 8 modulos e fronteiras verificadas.
# Tudo roda numa copia do repositorio (a arvore do Executor nao e tocada).
TITULO="Esqueleto Spring Boot 3 + Spring Modulith, 8 modulos e fronteiras verificadas"
aceite() {
  declara F1.1 "Gradle wrapper 8.14.3 no repositorio e bytecode Java 21"
  declara F1.2 "./gradlew build passa (testes do Executor inclusos)"
  declara F1.3 "bootJar executavel com Spring Boot 3.x e Start-Class saasagenda.Aplicacao"
  declara F1.4 "teste de aceite injetado: verify() do Modulith, exatamente os 8 modulos, allowedDependencies iguais ao mapa, nenhum modulo OPEN"
  declara F1.5 "mutante: identidade passa a usar a API de agenda; verify() do aceite e a suite do proprio Executor falham"
  declara F1.6 "mutante: agenda usa tipo interno de clinicas; verify() do aceite falha"
  local C="$TMPA/F1-copia" G="./gradlew --no-daemon -q"
  copia_repo "$C"
  if grep -qs 'gradle-8\.14\.3-' "$C/gradle/wrapper/gradle-wrapper.properties" && [ -x "$C/gradlew" ]; then local w=1; else local w=0; fi
  [ $w = 1 ] || { pendentes_vermelhos "pre-requisito ausente: gradlew com distribuicao 8.14.3"; return 0; }
  ( cd "$C" && timeout 1800 $G build ) >>"$LOGF" 2>&1 && verde F1.2 || vermelho F1.2 "./gradlew build falhou (ver $LOGF)"
  local cls; cls=$(find "$C/build/classes/java/main" -name 'Aplicacao.class' 2>/dev/null | head -1)
  if [ -n "$cls" ] && [ "$(od -An -j6 -N2 -tu1 "$cls" | awk '{print $1*256+$2}')" = 65 ]; then verde F1.1; else vermelho F1.1 "Aplicacao.class ausente ou nao e Java 21 (major 65)"; fi
  local jar; jar=$(app_jar "$C")
  if [ -n "$jar" ] && unzip -p "$jar" META-INF/MANIFEST.MF 2>/dev/null | tr -d '\r' | grep -q '^Spring-Boot-Version: 3\.' \
     && unzip -p "$jar" META-INF/MANIFEST.MF | tr -d '\r' | grep -q '^Start-Class: saasagenda.Aplicacao$'; then verde F1.3
  else vermelho F1.3 "bootJar ausente ou manifesto sem Spring Boot 3 / Start-Class saasagenda.Aplicacao"; fi
  mkdir -p "$C/src/test/java/saasagenda"; cp "$ACC/F1/java/saasagenda/AceiteF1ModulosTest.java" "$C/src/test/java/saasagenda/"
  ( cd "$C" && timeout 1200 $G test --tests saasagenda.AceiteF1ModulosTest ) >>"$LOGF" 2>&1 && verde F1.4 || vermelho F1.4 "teste de modulos falhou (ver $LOGF)"
  # mutante A
  cp -r "$ACC/F1/mutantes/a/saasagenda/." "$C/src/main/java/saasagenda/"
  local a1=0 a2=0
  ( cd "$C" && timeout 1200 $G compileJava ) >>"$LOGF" 2>&1 || { vermelho F1.5 "mutante nao compilou: estrutura de pacotes fora do contrato"; a1=x; }
  if [ "$a1" != x ]; then
    ( cd "$C" && timeout 1200 $G test --tests 'saasagenda.AceiteF1ModulosTest.fronteirasVerificadas' ) >>"$LOGF" 2>&1 || a1=1
    rm -f "$C/src/test/java/saasagenda/AceiteF1ModulosTest.java"
    ( cd "$C" && timeout 1800 $G test ) >>"$LOGF" 2>&1 || a2=1
    cp "$ACC/F1/java/saasagenda/AceiteF1ModulosTest.java" "$C/src/test/java/saasagenda/"
    if [ $a1 = 1 ] && [ $a2 = 1 ]; then verde F1.5
    else vermelho F1.5 "$([ $a1 = 0 ] && echo 'verify() do aceite nao pegou o mutante; ')$([ $a2 = 0 ] && echo 'a suite do Executor passou com o mutante (falta teste de fronteira proprio)')"; fi
  fi
  rm -f "$C/src/main/java/saasagenda/agenda/AceiteAlvoAgenda.java" "$C/src/main/java/saasagenda/identidade/AceiteMutanteIdentidade.java"
  # mutante B
  cp -r "$ACC/F1/mutantes/b/saasagenda/." "$C/src/main/java/saasagenda/"
  if ( cd "$C" && timeout 1200 $G test --tests 'saasagenda.AceiteF1ModulosTest.fronteirasVerificadas' ) >>"$LOGF" 2>&1; then
    vermelho F1.6 "verify() aceitou acesso a tipo interno (modulo aberto ou interno exposto)"
  elif ( cd "$C" && timeout 600 $G compileJava ) >>"$LOGF" 2>&1; then verde F1.6
  else vermelho F1.6 "mutante nao compilou: estrutura de pacotes fora do contrato"; fi
  # um mutante que "quebra" uma suite ja quebrada nao prova nada
  if [ "${CRIT_RES[F1.4]}" != VERDE ]; then
    [ "${CRIT_RES[F1.5]}" = VERDE ] && vermelho F1.5 "depende de F1.4 verde"
    [ "${CRIT_RES[F1.6]}" = VERDE ] && vermelho F1.6 "depende de F1.4 verde"
  fi
  [ "${CRIT_RES[F1.2]}" != VERDE ] && [ "${CRIT_RES[F1.5]}" = VERDE ] && vermelho F1.5 "depende de F1.2 verde (suite do Executor passando sem o mutante)"
  rm -rf "$C"
}
