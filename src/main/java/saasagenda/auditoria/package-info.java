/**
 * Módulo auditoria (nível 0 em docs/arquitetura/mapa-modulos.md, seção 3).
 * EventoAuditoria, só inclusão.
 * Só o pacote base é API pública; subpacotes são internos ao módulo.
 */
@ApplicationModule(allowedDependencies = {})
package saasagenda.auditoria;

import org.springframework.modulith.ApplicationModule;
