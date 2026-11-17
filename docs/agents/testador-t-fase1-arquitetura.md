# Testador: t-fase1-arquitetura, criterio 9

Comando: `bash docs/arquitetura/evidencias/teste-rls.sh` (PostgreSQL 16.15, porta 5498, usuario pgtest, papel de teste saas_app: NOSUPERUSER, NOBYPASSRLS, nao dono). Saida: `docs/arquitetura/evidencias/teste-rls.log`. Cada falha abaixo se reproduz pela linha `n` da secao "FALHAS" do log (sonda em teste-rls.sql, secao indicada). Servidor desligado ao fim.

Passou (710 sondas): (a) 261/261, sem leitura, listagem, UPDATE, DELETE ou INSERT cruzando A para B nas 20 tabelas RLS; (b) visibilidade do encaminhamento so origem, destino com consentimento e paciente; (d) contexto local nao vaza; (e) auditoria e historico imutaveis; NULL, UUID inexistente, mover clinica_id e FK composta barrados.

## Falhas reproduzidas
1. FK simples ignora RLS: agendamento(A) aceita `paciente_id` de paciente so de B e `encaminhamento_id` de E2 (sondas 676, 678).
2. Leitura de paciente alheio por UUID: `paciente_clinica(pacB, A)` pela recepcao, INSERT de encaminhamento com `paciente_id` alheio (ENCAMINHADOR ou MEDICO) ou UPDATE de `paciente_id` fazem `paciente` de B ficar legivel (nome, telefone, cpf_cifrado) via `paciente_da_clinica`/`paciente_via_encaminhamento` (679 a 682).
3. Consentimento forjado: PACIENTE insere `COMPARTILHAR_CASO` para encaminhamento de outro paciente e a clinica destino passa a ler o caso (683).
4. Historico forjado: PACIENTE ou ENCAMINHADOR insere linha em `historico_status_encaminhamento` com autor e papel livres (685, 686).
5. Sem restricao por coluna: PACIENTE e clinica destino alteram `motivo_cifrado`; PACIENTE troca `profissional_origem_id` (687 a 689).
6. T8 quebrada: SISTEMA nao consegue gravar EXPIRADO com `WHERE id=...` nem `WHERE expira_em<now()` (erro 42501, politica SELECT exige status antigo no novo registro); so UPDATE sem WHERE passa (705, 707).
7. Menor: `clinica_especialidade` legivel com so `app.clinica_id` setado, sem usuario nem papel (50).

## Maquina de estados (so reporte)
Nao imposta no banco: so CHECK dos 8 valores e gatilhos de historico. Aceitos: CRIADO para ATENDIDO ou CONTRARREFERIDO, e estado final CANCELADO para CRIADO ou AGENDADO (697 a 703), por origem, paciente ou destino.
