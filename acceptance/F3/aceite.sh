# shellcheck shell=bash
# F3: gates de identidade do Red Team (T-20 nucleo, I-22, I-23). Sondas: acceptance/F3/sondas-f3.sql.
TITULO="Gates de identidade: T-20, I-22, I-23"
aceite() {
  declara F3.1 "T-20: CPF so identifica a mesma pessoa com nome normalizado e nascimento (quando os dois tem) iguais; caso do filho com CPF do responsavel vira paciente proprio; regras de identidade da Fase 1 mantidas"
  declara F3.2 "T-20: na recepcao, qualquer coincidencia volta como sugestao, nunca como o id de um paciente existente"
  declara F3.3 "I-22: o telefone informado no encaminhamento nunca e descartado em silencio; o link nunca vai ao telefone antigo"
  declara F3.4 "I-23: depois da revogacao do COMPARTILHAR_CASO, busca, agendamento e consentimento da recepcao destino nao usam o vinculo nascido do encaminhamento"
  pg_sobe f3 || { pendentes_vermelhos "PostgreSQL efemero nao subiu"; return 0; }
  trap 'pg_desce' EXIT
  banco_migrado modelo >>"$LOGF" 2>&1 || { pendentes_vermelhos "pre-requisito: bootstrap e migracao (F2) falharam"; return 0; }
  $PSU -d postgres -c "create database f3 template modelo" >/dev/null
  roda_sondas f3 "$ACC/F3/sondas-f3.sql"
  confere F3.1 crit_res f3 F3.1
  confere F3.2 crit_res f3 F3.2
  confere F3.3 crit_res f3 F3.3
  confere F3.4 crit_res f3 F3.4
}
