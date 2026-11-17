package saasagenda;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.context.ApplicationContext;

@SpringBootTest
class AplicacaoTest {

    @Autowired
    ApplicationContext contexto;

    @Test
    void contextoSobe() {
        assertThat(contexto.getBean(Aplicacao.class)).isNotNull();
    }
}
