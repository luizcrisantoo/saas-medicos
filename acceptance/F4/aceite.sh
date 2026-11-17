# shellcheck shell=bash
# F4: gates de banco do Red Team (R-08, I-21, O3, envios apos cancelamento, volume de preparos de E-09).
TITULO="Gates de banco: R-08, I-21, O3, envios pendentes apos cancelamento, alerta de volume (E-09)"
aceite() {
  declara F4.1 "R-08: CREATE/ALTER/RENAME POLICY, CREATE TRIGGER, CREATE RULE, DISABLE TRIGGER, NO FORCE RLS e DROP POLICY em tabela de saas geram ALERTA_DDL_SAAS no log, mesmo com ROLLBACK"
  declara F4.2 "I-21: funcoes SECURITY DEFINER nao respondem sem sessao (rede_ligada, transicao_cancelamento, auxiliares); catalogo com sessao continua"
  declara F4.3 "O3: profissional sem canal verificado e sem usuario fica fora da visao de paciente e encaminhador; verificados e com conta continuam visiveis"
  declara F4.4 "cancelar agendamento (direto ou em cascata por T11) derruba envios CONFIRMACAO_AGENDAMENTO e LEMBRETE pendentes; agendamento ativo continua"
  declara F4.5 "E-09: a partir de 20 preparos para o mesmo destinatario em 1 hora, jobs_envio_prepara grava ALERTA_PREPARO_VOLUME no log, sem o contato"
  pg_sobe f4 || { pendentes_vermelhos "PostgreSQL efemero nao subiu"; return 0; }
  trap 'pg_desce' EXIT
  banco_migrado modelo >>"$LOGF" 2>&1 || { pendentes_vermelhos "pre-requisito: bootstrap e migracao (F2) falharam"; return 0; }
  $PSU -d postgres -c "create database f4 template modelo" >/dev/null
  local l0; l0=$(wc -l <"$PGLOG")
  roda_sondas f4 "$ACC/F4/sondas-f4.sql"
  tail -n +$((l0+1)) "$PGLOG" >"$TMPA/F4-pg.log"
  local chk; chk=$(python3 "$ACC/F4/confere_log.py" "$TMPA/F4-pg.log"); echo "$chk" >>"$LOGF"
  local r08; r08=$(echo "$chk" | grep -E '^falha R08' || true)
  if [ -z "$r08" ] && echo "$chk" | grep -q '^ok R08_H'; then verde F4.1; else vermelho F4.1 "$(echo "$r08" | head -3 | tr '\n' ';' | cut -c1-300)"; fi
  confere F4.2 crit_res f4 F4.2
  confere F4.3 crit_res f4 F4.3
  confere F4.4 crit_res f4 F4.4
  local vol; vol=$(echo "$chk" | grep -E '^falha VOL' || true)
  if [ -z "$vol" ] && echo "$chk" | grep -q '^ok VOL_ACIMA' && crit_res f4 F4.5; then verde F4.5
  else vermelho F4.5 "${MOTIVO:-$(echo "$vol" | head -2 | tr '\n' ';')}"; fi
  MOTIVO=""
}
