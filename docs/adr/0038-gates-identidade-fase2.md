# ADR-0038: CPF só identifica com nome e nascimento; telefone de contato do caso; vínculo revogado não serve à recepção

Status: Proposto (Fase 2, F3), sujeito à revisão do Red Team
Data: 2026-11-17
Tarefa: Fase 2, F3 (docs/fase2/spec.md)
Substitui: o item 2a do ADR-0036 (critério por CPF). Completa: ADR-0029 (itens 2 e 4), ADR-0036 (itens 2, 4 e 5), ADR-0037

## Contexto
Gates do Red Team da Fase 2 (docs/agents/red-team-t-fase1-arquitetura-r2.md, seção 3; docs/seguranca/stride-encaminhamento.md, seção 16):
- T-20: `mesma_pessoa` casava só pelo HMAC do CPF. O filho encaminhado com o "CPF do responsável" caía no registro da mãe (R2N1a), e a recepção recebia em silêncio o id de outra pessoa (R2N3a).
- I-22: quando o CPF casava, o telefone digitado era descartado e link e código iam ao número antigo do cadastro (R2N2a).
- I-23: depois da revogação do COMPARTILHAR_CASO, o vínculo `paciente_clinica` nascido do encaminhamento ainda servia à recepção destino para achar o id, marcar consulta e gravar consentimento (R2N5b a R2N5d).

## Decisão (migração `V2__gates_identidade.sql`)
1. Critério (a) do ADR-0036 corrigido: HMAC do CPF igual só identifica a mesma pessoa se o nome normalizado também for igual e, quando os dois registros têm data de nascimento, a data for a mesma. CPF igual com nome ou nascimento divergente nunca funde: nasce registro novo. O critério (b) e o escopo da busca (ADR-0029, item 2) não mudam. Isso cumpre o ADR-0037 no núcleo: o menor com o CPF do responsável vira Paciente próprio. A entidade de vínculo responsável-menor fica para F12 (B1).
2. Cadastro pela recepção (`paciente_cadastra_na_clinica`): nunca devolve o id de um paciente existente, nem por vínculo de cadastro nem por vínculo de encaminhamento. Sempre nasce um registro novo da clínica. A sugestão de possível duplicata e a junção com o paciente presente ficam para a Fase 3 (ADR-0036, item 5; spec F3, "Fora").
3. Telefone de contato do caso: `encaminhamento.telefone_contato` guarda o telefone informado em `encaminhamento_cria`. `jobs_envio_prepara` manda link, código e demais envios ao paciente daquele caso para esse telefone. Só usa o telefone do cadastro quando o caso não tem um (linha anterior à V2). O telefone global do cadastro não muda (ADR-0029, item 4). O papel web não tem UPDATE na coluna.
4. Agendamento e consentimento registrados pela recepção (políticas `agendamento_equipe_cria` e `consentimento_recepcao_registra`) exigem vínculo de cadastro (`encaminhamento_id IS NULL`) ou vínculo de encaminhamento com COMPARTILHAR_CASO ativo. É a mesma regra de leitura de `paciente_da_clinica` (I-03).

## Alternativas descartadas
- Bloquear o envio quando o telefone diverge até o encaminhador confirmar: exige o aviso ao encaminhador, que é da Fase 5. O telefone do caso resolve sem atrito e nunca usa o número antigo.
- Trocar o telefone global pelo digitado: um encaminhador mudaria o canal de todos os casos da pessoa (ADR-0029, item 4).
- A recepção recebe erro "possível duplicata": a forma da sugestão é decisão da Fase 3. Um registro novo é recuperável; o id de outra pessoa não é.

## Consequências
- Mais duplicatas na recepção até a tela da Fase 3.
- Reverter a V2 reabre T-20, I-22 e I-23 (a reversão existe só para a Definição de pronto).
- Termo novo no glossário: Telefone de contato do caso.
- Provas: `acceptance/run.sh F3` (F3.1 a F3.4), `src/test/java/saasagenda/GatesIdentidadeTest.java`.

## Fontes
- docs/fase2/spec.md, F3 e seção 5
- docs/seguranca/stride-encaminhamento.md, T-20, I-22, I-23
- docs/adr/0029, 0036, 0037
