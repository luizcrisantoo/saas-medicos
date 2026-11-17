RASCUNHO PARA REVISÃO DE ADVOGADO

# Política de Privacidade

> **RASCUNHO PARA REVISÃO DE ADVOGADO.** Este texto não está em vigor. Foi escrito pela equipe técnica para servir de ponto de partida e precisa ser revisado, completado e aprovado por advogado com experiência em direito médico e proteção de dados (LGPD, Lei 13.709/2018) antes de qualquer publicação. Tudo o que está entre colchetes é marcador a preencher. Os trechos marcados **A DEFINIR** dependem de decisão jurídica ainda não tomada.

Versão: rascunho 0.1. Última atualização: [DATA].

## 1. Quem somos

[NOME DA EMPRESA], inscrita no CNPJ sob o nº [CNPJ], com sede em [ENDEREÇO] ("Plataforma", "nós"), oferece um sistema de agenda para clínicas e uma rede de encaminhamento entre médicos e clínicas de especialidade.

Nesta política, "paciente" é a pessoa atendida ou encaminhada; "clínica" é a clínica ou o especialista que usa a agenda e recebe pacientes; "médico que encaminha" é o profissional que indica o paciente a uma clínica de especialidade.

## 2. Papéis na LGPD (controlador e operador)

**A DEFINIR com o advogado.** Ainda não está decidido quem é controlador e quem é operador em cada tratamento. A hipótese de trabalho, que **não** vale como decisão, é:

| Tratamento | Controlador | Operador |
|---|---|---|
| Agenda e cadastro de pacientes de cada clínica | A DEFINIR (hipótese: a clínica) | A DEFINIR (hipótese: a Plataforma) |
| Encaminhamento entre o médico que encaminha e a clínica destino | A DEFINIR (hipótese: controladoria conjunta ou papéis separados por etapa) | A DEFINIR |
| Conta, autenticação, segurança e auditoria da própria Plataforma | A DEFINIR (hipótese: a Plataforma) | A DEFINIR |

O contrato de tratamento de dados com cada clínica será assinado depois dessa definição.

## 3. Dados de saúde são dados pessoais sensíveis

Dados de saúde (motivo do encaminhamento, exames, anexos, informações da consulta e contrarreferência) são **dados pessoais sensíveis** (LGPD, art. 5º, II, e art. 11). Por isso:

- o caso só é compartilhado com a clínica destino com o **consentimento específico e destacado do paciente** para essa finalidade, que ele pode revogar a qualquer momento; sem consentimento ativo, a clínica destino não vê o caso;
- só quem participa do encaminhamento vê os dados dele (acesso mínimo);
- todo acesso a dado de saúde fica registrado em trilha de auditoria;
- anexos ficam em armazenamento criptografado e só são baixados por link de curta duração;
- mensagens de WhatsApp nunca trazem dado clínico: só um link autenticado e com prazo de validade.

Base legal alternativa (por exemplo, tutela da saúde, art. 11, II, "f"): **A DEFINIR** com o advogado.

## 4. Que dados tratamos e para quê

| Dado | Finalidade | Base legal |
|---|---|---|
| Nome, data de nascimento, telefone do paciente | Agendar, confirmar e lembrar consultas; identificar o paciente com segurança | A DEFINIR |
| CPF (guardado cifrado) | Evitar cadastro duplicado | A DEFINIR |
| Motivo do encaminhamento, exames e anexos | Permitir que a clínica destino atenda o paciente encaminhado | Consentimento do paciente (finalidade COMPARTILHAR_CASO); alternativa A DEFINIR |
| Contrarreferência (conduta do especialista) | Devolver ao médico que encaminhou o resultado do atendimento | A DEFINIR |
| Dados de profissionais e da equipe das clínicas | Acesso ao sistema, segurança e auditoria | A DEFINIR |
| Registros de acesso (data, hora, IP, ação) | Segurança, auditoria e cumprimento de obrigação legal | A DEFINIR |

Não vendemos dados. Não usamos dados de pacientes para publicidade.

## 5. Consentimento

O paciente vê o texto do consentimento de cada finalidade antes de aceitar. Cada texto tem uma **versão identificada**; se o texto mudar, nasce uma versão nova, e o registro guarda qual versão e qual texto o paciente aceitou, a finalidade, o caso, a data e o canal. Esses dados são gravados pelo sistema a partir da sessão autenticada do paciente, nunca a partir de informação enviada pelo navegador.

O paciente pode revogar o consentimento a qualquer momento pela mesma página do encaminhamento ou pelo canal do encarregado. A revogação vale a partir dela e não apaga o registro de que o consentimento existiu.

## 6. Livre escolha do paciente

O paciente é sempre livre para escolher outro especialista, dentro ou fora da rede. Recusar ou revogar um consentimento não muda o atendimento do médico que encaminhou.

## 7. Como a Plataforma é paga

Só a clínica que recebe pacientes paga, numa **mensalidade fixa**. A Plataforma nunca cobra por paciente recebido e nunca paga, dá desconto ou qualquer outra **vantagem a quem encaminha** (Código de Ética Médica). Nenhum dado de paciente é usado para calcular cobrança.

## 8. Com quem compartilhamos

- Com a clínica destino escolhida pelo paciente, só com o consentimento dele e só os dados do caso.
- Com o médico que encaminhou: o andamento do encaminhamento e a contrarreferência.
- Com fornecedores de infraestrutura (hospedagem em nuvem no Brasil, envio de mensagens, autenticação), como operadores, sob contrato: [LISTA DE FORNECEDORES A PREENCHER].
- Com autoridades, quando a lei exigir.

Transferência internacional: [A PREENCHER conforme os fornecedores contratados].

## 9. Por quanto tempo guardamos (retenção)

**Prazos A DEFINIR com o advogado** (inclusive a relação com o prazo de guarda do prontuário). Marcadores:

- dados do encaminhamento e anexos: [PRAZO A DEFINIR] a partir do encerramento do caso;
- registro de consentimento e de revogação: [PRAZO A DEFINIR], para prova;
- trilha de auditoria: [PRAZO A DEFINIR];
- links de acesso do paciente: expiram em poucos dias e não são reaproveitados.

Ao fim do prazo, os dados são eliminados ou anonimizados, salvo obrigação legal de guarda.

## 10. Direitos do titular

Pedidos de acesso, correção e exclusão são atendidos pelo canal do encarregado (seção 11). O titular dos dados pode, a qualquer momento e de graça (LGPD, art. 18):

- confirmar se tratamos dados seus e ter acesso a eles;
- pedir a correção de dados incompletos, inexatos ou desatualizados;
- pedir anonimização, bloqueio ou eliminação (exclusão) de dados desnecessários ou tratados em desacordo com a lei;
- pedir a portabilidade;
- pedir a exclusão dos dados tratados com consentimento;
- saber com quem compartilhamos seus dados;
- saber que pode não consentir e quais as consequências;
- revogar o consentimento;
- peticionar à Autoridade Nacional de Proteção de Dados (ANPD).

Prazo de resposta e procedimento de confirmação de identidade: [A DEFINIR com o advogado].

## 11. Encarregado de dados (DPO)

Encarregado: [NOME DO ENCARREGADO]. Contato: [E-MAIL DO ENCARREGADO]. É o canal para exercer os direitos acima, tirar dúvidas e reclamar.

## 12. Segurança e incidentes

Usamos criptografia em trânsito e em repouso, isolamento de dados entre clínicas, autenticação forte da equipe, registro de todo acesso a dado de saúde e revisão de segurança antes de cada mudança relevante. Em caso de incidente com risco aos titulares, comunicamos a ANPD e os titulares afetados conforme a lei: [PROCEDIMENTO A DEFINIR].

## 13. Mudanças nesta política

Quando esta política mudar, publicamos a versão nova com a data. Se a mudança afetar um consentimento, pedimos o consentimento de novo.

## 14. Lei e foro

[A DEFINIR com o advogado].
