# shellcheck shell=bash
# F9: base LGPD. Consentimento via API e rascunhos de termos de uso e politica de privacidade.
TITULO="Base LGPD: consentimento conceder e revogar pela API, termos e politica em rascunho para advogado"
aceite() {
  declara F9.1 "GET /api/termos/consentimento/COMPARTILHAR_CASO devolve finalidade, versao e texto"
  declara F9.2 "paciente concede pela API: registro com paciente da sessao, caso do link, clinica destino, versao e texto exato"
  declara F9.3 "versao inexistente, outro caso, outra paciente, recepcao, sem sessao e campos forjados: recusados ou ignorados"
  declara F9.4 "paciente lista os proprios consentimentos do caso"
  declara F9.5 "paciente revoga pela API; revogar de novo nao reescreve a data; consentimento alheio intocado"
  declara F9.6 "efeito no banco: clinica destino so ve o caso enquanto o consentimento esta ativo"
  declara F9.7 "docs/legal: termos de uso e politica de privacidade em rascunho marcado, cobrindo dado de saude, direitos, encarregado, retencao e papeis (A DEFINIR), etica de cobranca e livre escolha"
  local d; d=$(python3 "$ACC/F9/confere_docs.py" "$RAIZ" 2>&1); echo "$d" >>"$LOGF"
  agrega_py "$d"
  app_prepara f9 "$ACC/F9/semente-f9.sql" || return 0
  local out; out=$(python3 "$ACC/F9/teste_f9.py" 2>&1); echo "$out" >>"$LOGF"
  agrega_py "$out"
  pendentes_vermelhos "teste nao produziu resultado (ver $LOGF)"
}
