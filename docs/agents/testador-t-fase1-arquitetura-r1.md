# Testador, t-fase1-arquitetura, rodada 1

Comando: `bash docs/arquitetura/evidencias/teste-r1-independente.sh` (PG16 limpo, porta 5496, `.pgtest2`; log em `teste-r1-independente.log`). Reexecução do Executor passou: 1422/0 falhas e RT 26/26 negadas; nenhuma sonda removida (só reclassificadas). Meus casos: 3595, 8 falhas, 3 achados.

1. **Link vivo de encaminhamento CANCELADO.** `J-link` (n=3585, 3586): `jobs_envio_prepara` de envio PENDENTE antigo devolve token e telefone e cria link ativo após T9 (`token_entregue=true links_ativos=1`); `link_consulta` segue válido após cancelar (`OK n=1`, esperado 0).
2. **Invariante AGENDADO violada por UPDATE de agendamento.** `B-agenda` (n=3547, 3548): REC_A faz `update agendamento set status='AGENDADO'` e reativa CANCELADO com encaminhamento SOLICITADO, e REALIZADO com ATENDIDO.
3. **Usuário inativo com sessão viva.** `S-inativo` (n=1764, 1766): `profissional` devolve 6 linhas e `catalogo_rede` 2 (esperado 0).

Servidor desligado.
