# Testador, t-fase1-arquitetura, rodada 2
Comando: `bash docs/arquitetura/evidencias/teste-r2-independente.sh` (PG16 limpo, `.pgtest3`:5493; log `teste-r2-independente.log`; servidor desligado).

Rodada 1: as 3 falhas negadas na forma original (O.1 a O.3 e B3 do log: ERRO "agendamento ... e final", link_consulta=0, usuario inativo ve 0). Reexecucao do Executor: 0 falhas.

**Ajustes: todos legitimos.** Rodei o `.sql` original contra o modelo r2: so 7 falhas + 3 blocos abortados, todas mapeadas (R2-A/R2-B, A1 a A6). A2, A5, A6 retargetam para o caso da sessao (mais restritivo); A4 e mais restrito. A3 e o mais fraco (captura qualquer erro como n=0), mas o NOTICE mostra a mensagem certa.

**Falha reproduzivel (latente, baixa):** cancelar agendamento nao derruba envios `CONFIRMACAO_AGENDAMENTO`/`LEMBRETE` PENDENTES; `jobs_envio_prepara` devolve o telefone (N3, n=50 e 51). Nenhuma funcao os cria hoje.

Residual inerte: corrida prepara x T9 deixa 1 link vivo, mas `link_consulta` devolve 0 (B6).

N1 (identidade, 14) e N2 (sessao por caso, 22) sem falhas; N3 passa em T6, T8, T9, T10 e T11.
