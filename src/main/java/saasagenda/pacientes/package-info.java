/**
 * Módulo pacientes (nível 2 em docs/arquitetura/mapa-modulos.md, seção 3).
 * Paciente global, vínculo com clínica e consentimento.
 * Só o pacote base é API pública; subpacotes são internos ao módulo.
 */
@ApplicationModule(allowedDependencies = { "identidade", "auditoria" })
package saasagenda.pacientes;

import org.springframework.modulith.ApplicationModule;
