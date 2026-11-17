package saasagenda;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.modulith.Modulithic;

/**
 * Monolito modular (ADR-0001). Os 8 módulos são os pacotes de primeiro nível
 * abaixo de {@code saasagenda}; as dependências permitidas estão no
 * {@code package-info.java} de cada um, conforme docs/arquitetura/mapa-modulos.md, seção 3.
 */
@Modulithic(systemName = "saas-agenda")
@SpringBootApplication
public class Aplicacao {

    public static void main(String[] args) {
        SpringApplication.run(Aplicacao.class, args);
    }
}
