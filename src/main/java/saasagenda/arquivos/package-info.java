/**
 * Módulo arquivos (nível 2 em docs/arquitetura/mapa-modulos.md, seção 3).
 * Anexos em bucket privado e URL assinada.
 * Só o pacote base é API pública; subpacotes são internos ao módulo.
 */
@ApplicationModule(allowedDependencies = { "identidade", "auditoria" })
package saasagenda.arquivos;

import org.springframework.modulith.ApplicationModule;
