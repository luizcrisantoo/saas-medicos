# shellcheck shell=bash
# F5: guarda de migracao (gates R-07 e R-08 de CI) e pipeline do GitHub Actions validado localmente.
TITULO="CI: guarda de migracao (R-07, R-08) e GitHub Actions com testes, SAST, dependencias e segredos"
aceite() {
  declara F5.1 "scripts/ci/guarda-migracao.sh existe e aceita as migracoes do repositorio com as aprovacoes registradas"
  declara F5.2 "a guarda recusa migracao nao aprovada com DISABLE TRIGGER, NO FORCE/DISABLE RLS, DROP POLICY, DROP TRIGGER, session_replication_role, CREATE/ALTER POLICY ou CREATE TRIGGER"
  declara F5.3 "a guarda nao e enganada por variacoes de escrita do mesmo comando"
  declara F5.4 "a guarda aceita migracao limpa (tabela com RLS, indice, coluna, GRANT)"
  declara F5.5 "aprovacao presa ao sha256 do conteudo e ao nome do arquivo"
  declara F5.6 "workflows passam no actionlint e rodam em pull_request"
  declara F5.7 "pipeline tem testes (./gradlew), SAST, varredura de dependencias e de segredos"
  declara F5.8 "pipeline roda a guarda sobre db/migration e db/reversao, e a guarda aceita as reversoes do repositorio"
  declara F5.9 "pipeline varre segredos; nenhum segredo no repositorio (gitleaks) e a configuracao do repositorio ainda detecta uma chave plantada"
  local G="$RAIZ/scripts/ci/guarda-migracao.sh" out
  out=$(python3 "$ACC/F5/testa_guarda.py" "$G" "$RAIZ" 2>&1); echo "$out" >>"$LOGF"
  _grupo() { local g=$1 id=$2; local f; f=$(echo "$out" | grep -E "^falha $g " | head -3 | tr '\n' ';')
    if [ -z "$f" ] && echo "$out" | grep -qE "^ok $g "; then verde "$id"; else vermelho "$id" "${f:-sem resultado}"; fi; }
  _grupo REPO F5.1; _grupo PROIBIDO F5.2; _grupo VARIANTE F5.3; _grupo LIMPO F5.4; _grupo APROVACAO F5.5
  # recusar tudo nao conta: proibidos e variantes so ficam verdes se a guarda aceita migracao limpa
  if [ "${CRIT_RES[F5.4]}" != VERDE ]; then
    [ "${CRIT_RES[F5.2]}" = VERDE ] && vermelho F5.2 "a guarda tambem recusa migracao limpa (F5.4)"
    [ "${CRIT_RES[F5.3]}" = VERDE ] && vermelho F5.3 "a guarda tambem recusa migracao limpa (F5.4)"
  fi
  local ci; ci=$(python3 "$ACC/F5/confere_ci.py" "$RAIZ" 2>&1); echo "$ci" >>"$LOGF"
  local wfs; wfs=$(ls "$RAIZ"/.github/workflows/*.y*ml 2>/dev/null)
  if [ -n "$wfs" ] && actionlint $wfs >>"$LOGF" 2>&1 && echo "$ci" | grep -q "^ok GATILHO"; then verde F5.6
  else vermelho F5.6 "actionlint falhou, sem workflow ou sem pull_request (ver $LOGF)"; fi
  local f7; f7=$(echo "$ci" | grep -E "^falha (TESTES|SAST|DEPENDENCIAS|SEGREDOS)" | tr '\n' ';')
  if [ -z "$f7" ] && echo "$ci" | grep -q "^ok SEGREDOS"; then verde F5.7; else vermelho F5.7 "${f7:-sem resultado}"; fi
  local f8; f8=$(echo "$ci" | grep -E "^falha GUARDA" | tr '\n' ';')
  if [ -z "$f8" ] && echo "$ci" | grep -q "^ok GUARDA_REVERSAO" && [ -x "$G" ] \
     && "$G" "$RAIZ/src/main/resources/db/reversao" "$RAIZ/src/main/resources/db/aprovacoes.sha256" >>"$LOGF" 2>&1; then verde F5.8
  else vermelho F5.8 "${f8:-guarda recusou db/reversao do repositorio ou ausente}"; fi
  # F5.9 segredos
  local C="$TMPA/F5-copia"; copia_repo "$C"
  local cfg=(); [ -f "$RAIZ/.gitleaks.toml" ] && cfg=(--config "$RAIZ/.gitleaks.toml")
  local limpo=1 detecta=1
  gitleaks detect --no-git --no-banner --redact --exit-code 1 -s "$C" "${cfg[@]}" >>"$LOGF" 2>&1 || limpo=0
  local chave; chave="AKIA$(python3 -c 'import secrets,string;print("".join(secrets.choice(string.ascii_uppercase+"234567") for _ in range(16)))')"
  local seg; seg=$(python3 -c 'import secrets;print(secrets.token_urlsafe(30)[:40])')
  mkdir -p "$C/src/main/resources"
  printf 'aws:\n  access-key-id: %s\n  secret-access-key: %s\n' "$chave" "$seg" >"$C/src/main/resources/application-vazado.yml"
  gitleaks detect --no-git --no-banner --redact --exit-code 1 -s "$C" "${cfg[@]}" >>"$LOGF" 2>&1 && detecta=0
  rm -rf "$C"
  if ! echo "$ci" | grep -q "^ok SEGREDOS"; then vermelho F5.9 "pipeline sem varredura de segredos (o repositorio limpo hoje nao prova nada sem ela)"
  elif [ $limpo = 1 ] && [ $detecta = 1 ]; then verde F5.9
  else vermelho F5.9 "$([ $limpo = 0 ] && echo 'gitleaks achou segredo no repositorio; ')$([ $detecta = 0 ] && echo 'chave plantada nao detectada com a configuracao do repositorio')"; fi
}
