/**
 * Módulo notificacoes (nível 5 em docs/arquitetura/mapa-modulos.md, seção 3).
 * Único módulo que envia mensagens; envio só por evento.
 * Só o pacote base é API pública; subpacotes são internos ao módulo.
 */
@ApplicationModule(allowedDependencies = { "encaminhamentos", "agenda", "pacientes", "clinicas", "identidade", "auditoria" })
package saasagenda.notificacoes;

import org.springframework.modulith.ApplicationModule;
