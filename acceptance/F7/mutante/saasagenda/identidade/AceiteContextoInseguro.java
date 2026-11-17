package saasagenda.identidade;

/** Mutante de aceite F7 (I-20): token interpolado no texto do SQL. A suite do Executor tem que recusar. */
class AceiteContextoInseguro {
    String sql(String token) {
        return "select set_config('app.sessao', '" + token + "', true)";
    }
}
