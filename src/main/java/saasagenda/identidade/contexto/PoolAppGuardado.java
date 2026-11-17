package saasagenda.identidade.contexto;

import com.zaxxer.hikari.HikariDataSource;
import java.io.PrintWriter;
import java.lang.reflect.InvocationHandler;
import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;
import java.lang.reflect.Proxy;
import java.sql.Connection;
import java.sql.SQLException;
import java.sql.SQLFeatureNotSupportedException;
import java.util.Set;
import java.util.function.Supplier;
import java.util.logging.Logger;
import javax.sql.DataSource;

/**
 * O pool {@code saas_app} do processo web, fechado por padrão (ADR-0026, item 7; Red Team I-20).
 * Toda conexão entregue é um invólucro que só aceita os métodos de ciclo de vida da transação
 * (commit, rollback, autocommit, isolamento, {@code isValid}, fechar). Criar comando, preparar SQL,
 * ler metadados ou desembrulhar a conexão exige a permissão que só o {@link ContextoBancoJdbc}
 * concede, por chamada e para aquela conexão: primeiro para conferir e aplicar o contexto, depois
 * por meio do executor {@code ConsultaContexto} da transação. Qualquer outro SQL por
 * {@code saas_app} (um {@code @Transactional} comum com {@code JdbcTemplate}, um
 * {@code getConnection()} direto) falha com SQLSTATE 42501.
 */
final class PoolAppGuardado implements DataSource, AutoCloseable {

    /** SQLSTATE de recusa (insufficient_privilege). */
    static final String RECUSA = "42501";

    /** Métodos de {@link Connection} que não executam SQL de aplicação nem expõem a conexão crua. */
    private static final Set<String> CICLO_DE_VIDA = Set.of("close", "isClosed", "isValid", "commit",
            "rollback", "setAutoCommit", "getAutoCommit", "setReadOnly", "isReadOnly",
            "setTransactionIsolation", "getTransactionIsolation", "getWarnings", "clearWarnings",
            "setHoldability", "getHoldability", "setNetworkTimeout", "getNetworkTimeout", "abort",
            "releaseSavepoint", "setSavepoint", "toString", "hashCode", "equals");

    /** A conexão para a qual a chamada em curso neste fio tem permissão (nenhuma, por padrão). */
    private static final ThreadLocal<Connection> PERMITIDA = new ThreadLocal<>();

    private final HikariDataSource pool;

    PoolAppGuardado(HikariDataSource pool) {
        this.pool = pool;
    }

    /** Conexão guardada: além de {@link Connection}, pode ser descartada do pool. */
    interface ConexaoGuardada extends Connection {
        /** Tira a conexão física do pool (fecha ao ser devolvida); nunca volta a ser emprestada. */
        void descartar();
    }

    /**
     * Executa {@code trabalho} com permissão de SQL só na conexão {@code conexao}, só neste fio e
     * só durante a chamada. Pacote privado: o único chamador é o {@link ContextoBancoJdbc}
     * (conferido pelo teste de arquitetura).
     */
    static <T> T comPermissao(ConexaoGuardada conexao, Supplier<T> trabalho) {
        Connection anterior = PERMITIDA.get();
        PERMITIDA.set(conexao);
        try {
            return trabalho.get();
        } finally {
            if (anterior == null) {
                PERMITIDA.remove();
            } else {
                PERMITIDA.set(anterior);
            }
        }
    }

    @Override
    public Connection getConnection() throws SQLException {
        Connection crua = pool.getConnection();
        return (Connection) Proxy.newProxyInstance(PoolAppGuardado.class.getClassLoader(),
                new Class<?>[] {ConexaoGuardada.class}, new Guarda(crua));
    }

    @Override
    public Connection getConnection(String usuario, String senha) throws SQLException {
        throw new SQLException("credencial fixa no pool saas_app", RECUSA);
    }

    private final class Guarda implements InvocationHandler {
        private final Connection crua;

        Guarda(Connection crua) {
            this.crua = crua;
        }

        @Override
        public Object invoke(Object proxy, Method metodo, Object[] args) throws Throwable {
            String nome = metodo.getName();
            if (metodo.getDeclaringClass() == ConexaoGuardada.class && "descartar".equals(nome)) {
                pool.evictConnection(crua);
                return null;
            }
            if ("unwrap".equals(nome)) {
                throw new SQLException("conexao saas_app nao se desembrulha", RECUSA);
            }
            if ("isWrapperFor".equals(nome)) {
                return false;
            }
            if (!CICLO_DE_VIDA.contains(nome) && PERMITIDA.get() != proxy) {
                throw new SQLException("SQL por saas_app sem contexto aplicado nesta transacao", RECUSA);
            }
            if ("equals".equals(nome)) {
                return proxy == args[0];
            }
            if ("hashCode".equals(nome)) {
                return System.identityHashCode(proxy);
            }
            try {
                return metodo.invoke(crua, args);
            } catch (InvocationTargetException e) {
                throw e.getCause();
            }
        }
    }

    /** Só para fechar o pool no desligamento e para os testes de pool (via reflexão). */
    HikariDataSource pool() {
        return pool;
    }

    @Override
    public void close() {
        pool.close();
    }

    @Override
    public <T> T unwrap(Class<T> tipo) throws SQLException {
        throw new SQLException("pool saas_app nao se desembrulha", RECUSA);
    }

    @Override
    public boolean isWrapperFor(Class<?> tipo) {
        return false;
    }

    @Override
    public PrintWriter getLogWriter() throws SQLException {
        return pool.getLogWriter();
    }

    @Override
    public void setLogWriter(PrintWriter out) throws SQLException {
        pool.setLogWriter(out);
    }

    @Override
    public void setLoginTimeout(int segundos) throws SQLException {
        pool.setLoginTimeout(segundos);
    }

    @Override
    public int getLoginTimeout() throws SQLException {
        return pool.getLoginTimeout();
    }

    @Override
    public Logger getParentLogger() throws SQLFeatureNotSupportedException {
        throw new SQLFeatureNotSupportedException();
    }
}
