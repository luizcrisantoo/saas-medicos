/**
 * Módulo clinicas (nível 2 em docs/arquitetura/mapa-modulos.md, seção 3).
 * Clínica, profissionais, especialidades e flags por clínica.
 * Só o pacote base é API pública; subpacotes são internos ao módulo.
 */
@ApplicationModule(allowedDependencies = { "identidade", "auditoria" })
package saasagenda.clinicas;

import org.springframework.modulith.ApplicationModule;
