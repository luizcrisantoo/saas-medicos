# Red Team: t-fase1-arquitetura

Data: 2026-11-10. Poder de veto: docs/briefing.md, "Regras do fluxo neste projeto" (autenticação, autorização, tenant, arquivos, links de paciente, dado de saúde). Modelagem completa: docs/seguranca/stride-encaminhamento.md (58 ameaças, 20 ABERTAS com falha reproduzida). Sondas próprias: docs/seguranca/evidencias/red-team-sondas.sql e .log.

## Veredito: VETO

A arquitetura v2 não passa. O desenho toca os seis temas do veto e falha em todos:

1. Tenant e autorização: a RLS só verifica identidade para a equipe (`eh_equipe`). Paciente, encaminhador, SISTEMA e MEDICO na origem são texto de GUC no mesmo papel de banco da web. Prova: RT3, RT4, RT5, RT8. A "segunda barreira" do ADR-0004 não existe para a rede.
2. Dado de saúde: oito falhas reais do Testador seguem abertas (FK simples, paciente alheio por UUID, consentimento forjado, histórico forjado, coluna livre, T8, catálogo, máquina de estados).
3. Links de paciente: o contexto PUBLICO_LINK reescreve o próprio link (zera tentativas, troca código, estende validade). Prova: RT2.
4. Identidade do paciente: uma clínica sequestra o telefone global de paciente de outra clínica e recebe os códigos dele. Prova: RT1 (e RT10 pelo próprio paciente).
5. Arquivos: qualquer conexão vira SISTEMA e aponta um anexo para o objeto de outro encaminhamento marcando LIMPO. Prova: RT3.
6. Autenticação: o médico que encaminha sem conta não tem autenticação decidida (ADR-0006) e, pelo desenho atual, digitar o CRM público de outro médico dá acesso aos casos dele. Prova: RT5.

## O que precisa mudar para eu aprovar

Bloqueiam a aprovação (desenho e `modelo-v2.sql`, com o Testador reexecutando e provando):

1. Contexto verificável no banco para todo ator fora da equipe: sessão de paciente e de encaminhador registrada em tabela (hash do token de sessão, validade curta, origem) e conferida pelas políticas, como `eh_equipe` faz para a equipe. Sem sessão válida, 0 linhas. (E-01, S-03)
2. Papel de banco separado para jobs e listeners, com credencial própria; políticas de SISTEMA por `current_user`, nunca por `app.papel`. O papel da web não consegue agir como SISTEMA. (S-04, T-06)
3. No banco, `app.profissional_id` tem que pertencer a `app.usuario` (MEDICO) ou à sessão verificada (ENCAMINHADOR); MEDICO exige `profissional_clinica` ativo na clínica do contexto, inclusive em `encaminhamento_origem` e `encaminhamento_cria`. (S-05, R-03)
4. ADR de autenticação do médico que encaminha sem conta, com posse de canal verificado do próprio médico. Digitar CRM nunca abre registro existente; registro criado pelo formulário fica isolado até a verificação. Pode ser decisão do Luiz, mas tem que existir antes da Fase 5 e o desenho tem que nascer compatível. (S-01, I-09)
5. FK composta `(clinica_id, id)` ou gatilho de coerência em toda referência entre tabelas com tenant; agendamento com `encaminhamento_id` exige mesma clínica destino e mesmo paciente. (T-04)
6. Vínculo `paciente_clinica` só por fluxo legítimo, nunca por UUID vindo do cliente; `paciente_id` do encaminhamento imutável e nunca aceito do cliente. (I-01, T-07)
7. Telefone global do paciente imutável por clínica e pelo contexto PACIENTE; troca só com confirmação no número antigo ou presencial, auditada. (T-07, T-08)
8. Regra de deduplicação de paciente global (pendência do ADR-0017): busca por CPF ou telefone só acha paciente já vinculado ao ator; fusão só com código confirmado pelo paciente. Registrar em ADR. (I-02)
9. UPDATE por coluna e por ator em `encaminhamento` (GRANT por coluna mais gatilho): `motivo_cifrado`, `paciente_id`, `profissional_origem_id`, `especialidade_destino_id` imutáveis após a criação. (T-01)
10. Gatilho de transições que aplica T1 a T11 com o ator de cada uma; estados finais sem saída. (T-02, sugestão S3)
11. `consentimento_paciente_concede` exige que o encaminhamento seja do paciente e a clínica seja a destino; `consentimento_recepcao_registra` exige vínculo do paciente com a clínica. (T-03, T-14)
12. Histórico sem INSERT direto pela aplicação; auditoria com `ator_papel` e `ator_id` iguais ao contexto. Histórico separa ator técnico de autor de negócio. (R-01, R-02, R-05)
13. `link_paciente` no contexto PUBLICO_LINK: só incremento de tentativas e gravação de `usado_em`; um link ativo por encaminhamento; limite de tentativas por encaminhamento e por paciente, não por link; tamanho e validade do código em ADR. (T-05, T-16, D-03)
14. `anexo_encaminhamento`: worker só altera `status_varredura` de PENDENTE para LIMPO ou INFECTADO; `chave_storage` gerada pelo servidor e imutável. (T-06, I-10)
15. `agendamento_paciente_marca` substituída por caminho que valida modo de recebimento, flag ligada, vaga livre e encaminhamento do próprio paciente em SOLICITADO. Flag da rede imposta também na RLS, não só na aplicação. (T-11, E-07)
16. T8 funcionando com WHERE, sem UPDATE em massa. (D-01)
17. `clinica_especialidade_ver`, `profissional_ver` e `clinica_catalogo_rede` restritos: sem contexto lixo, sem telefone e e-mail de médico, sem `cnpj`, sem clínica de flag desligada. (I-04, I-05, I-06)
18. Contexto SISTEMA dos listeners (S1 do Executor) resolvido por funções estreitas por ação, cada uma revisada pelo Red Team; nenhuma política "SISTEMA vê tudo". (E-08)
19. ADR de Proteção de dados (falta apontada pelo Avaliador) com os requisitos de link e log: GET do link não consome nem mostra nada, token trocado por sessão via POST, `Referrer-Policy: no-referrer`, token e corpo de requisição fora de log e APM. (I-07, I-17)

Obrigatórios antes da fase indicada, sem bloquear a Fase 1 se registrados como requisito no desenho:

20. Antes da Fase 4: regra escrita de que mensagem de entrada pelo WhatsApp nunca autentica, consente nem muda status; webhook de entrada não grava o corpo; lista fechada de variáveis por template, sem nome de paciente, especialidade, conduta ou nome livre de médico; teto de mensagens com corte e alerta. (S-08, I-14, I-08, S-09, D-02)
21. Antes da Fase 4: listener relê o estado na fonte antes de mudar status e é idempotente; `event_publication` com limpeza por prazo e fora do alcance do papel web. (T-10, I-16)
22. Antes da Fase 5: upload de escrita única e objeto imutável, tipo por assinatura de bytes, hash e tamanho calculados no servidor, URL de download com validade em minutos, `attachment` e `no-store`, prazo de retenção decidido. (T-09, I-11, I-13)
23. Antes da Fase 5: decisão do Luiz sobre segundo elemento antes de mostrar dado clínico ao paciente, ou aceite por escrito do risco de posse do celular. (S-06)

Aprovo quando os itens 1 a 19 estiverem no desenho e no SQL, e o Testador reexecutar `teste-rls.sh` mais `red-team-sondas.sql` com todas as sondas ABERTAS falhando como esperado (negado ou erro).
