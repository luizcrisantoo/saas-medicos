/**
 * Módulo agenda (nível 3 em docs/arquitetura/mapa-modulos.md, seção 3).
 * Núcleo de agendamento; não conhece a rede.
 * Só o pacote base é API pública; subpacotes são internos ao módulo.
 */
@ApplicationModule(allowedDependencies = { "clinicas", "pacientes", "identidade", "auditoria" })
package saasagenda.agenda;

import org.springframework.modulith.ApplicationModule;
