package saasagenda.identidade;

import java.util.Optional;

/**
 * API pública de sessão do módulo identidade (docs/arquitetura/mapa-modulos.md, identidade).
 * A identidade que o banco aceita é a linha de {@code sessao} apresentada pelo token opaco
 * (ADR-0023). O token nunca vai para log (ADR-0026).
 */
public interface SessaoApi {

    /**
     * Abre sessão de equipe pelo papel {@code saas_auth} para o {@code sub} de um access token
     * já validado. Devolve o token opaco (hexadecimal) ou vazio se o usuário não existe ou está inativo.
     */
    Optional<String> abrirEquipe(String subOidc);

    /** Tipo do ator da sessão (EQUIPE, PACIENTE, ENCAMINHADOR), consultado pelo papel {@code saas_app}. */
    Optional<String> tipo(String tokenSessao);

    /** Encerra a sessão no banco, pelo papel {@code saas_app}. */
    void encerrar(String tokenSessao);
}
