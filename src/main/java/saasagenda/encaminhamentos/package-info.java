/**
 * Módulo encaminhamentos (nível 4 em docs/arquitetura/mapa-modulos.md, seção 3).
 * Rede de encaminhamento; reage a eventos da agenda.
 * Só o pacote base é API pública; subpacotes são internos ao módulo.
 */
@ApplicationModule(allowedDependencies = { "agenda", "pacientes", "clinicas", "arquivos", "identidade", "auditoria" })
package saasagenda.encaminhamentos;

import org.springframework.modulith.ApplicationModule;
