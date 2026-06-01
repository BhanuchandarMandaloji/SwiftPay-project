package com.swiftpay.project.bootstrap;

import com.swiftpay.project.account.Account;
import com.swiftpay.project.account.AccountRepository;
import org.springframework.boot.CommandLineRunner;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

import java.math.BigDecimal;

@Configuration
public class DataSeeder {
    @Bean
    CommandLineRunner seedAccounts(AccountRepository accountRepository) {
        return args -> {
            if (accountRepository.count() > 0) {
                return;
            }
            accountRepository.save(new Account("user-100", new BigDecimal("2000000.00"), "USD"));
            accountRepository.save(new Account("user-200", new BigDecimal("500.00"), "USD"));
            accountRepository.save(new Account("user-300", new BigDecimal("750.00"), "USD"));
        };
    }
}
