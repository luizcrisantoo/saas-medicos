/**
 * Módulo identidade (nível 1 em docs/arquitetura/mapa-modulos.md, seção 3).
 * Usuário, vínculo com clínica, sessão e autorização centralizada.
 * Só o pacote base é API pública; subpacotes são internos ao módulo.
 */
@ApplicationModule(allowedDependencies = { "auditoria" })
package saasagenda.identidade;

import org.springframework.modulith.ApplicationModule;
