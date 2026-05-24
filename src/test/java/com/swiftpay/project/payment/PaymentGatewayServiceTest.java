package com.swiftpay.project.payment;

import com.swiftpay.project.account.Account;
import com.swiftpay.project.account.AccountRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.data.redis.core.ValueOperations;
import org.springframework.kafka.core.KafkaTemplate;

import java.math.BigDecimal;
import java.util.Optional;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class PaymentGatewayServiceTest {
    @Mock
    private PaymentRepository paymentRepository;
    @Mock
    private AccountRepository accountRepository;
    @Mock
    private StringRedisTemplate redisTemplate;
    @Mock
    private ValueOperations<String, String> valueOperations;
    @Mock
    private KafkaTemplate<String, Object> kafkaTemplate;

    private PaymentGatewayService paymentGatewayService;

    @BeforeEach
    void setUp() {
        paymentGatewayService = new PaymentGatewayService(
                paymentRepository,
                accountRepository,
                redisTemplate,
                kafkaTemplate
        );
        when(redisTemplate.opsForValue()).thenReturn(valueOperations);
    }

    @Test
    void shouldReturnExistingPaymentForDuplicateTransaction() {
        CreatePaymentRequest request = new CreatePaymentRequest(
                "user-100", "user-200", new BigDecimal("10.00"), "USD", "tx-dup-1"
        );
        Payment existing = new Payment(
                request.transactionId(),
                request.senderId(),
                request.receiverId(),
                request.amount(),
                request.currency()
        );

        when(valueOperations.setIfAbsent(anyString(), anyString(), any())).thenReturn(Boolean.FALSE);
        when(paymentRepository.findByTransactionId(request.transactionId())).thenReturn(Optional.of(existing));

        PaymentResponse response = paymentGatewayService.initiate(request);

        assertEquals("tx-dup-1", response.transactionId());
        assertEquals(PaymentStatus.PENDING, response.status());
        verify(accountRepository, never()).findById(anyString());
    }

    @Test
    void shouldDeleteIdempotencyKeyWhenBalanceIsInsufficient() {
        CreatePaymentRequest request = new CreatePaymentRequest(
                "user-100", "user-200", new BigDecimal("1000.00"), "USD", "tx-insufficient-1"
        );
        Account sender = new Account("user-100", new BigDecimal("100.00"), "USD");

        when(valueOperations.setIfAbsent(anyString(), anyString(), any())).thenReturn(Boolean.TRUE);
        when(accountRepository.findById("user-100")).thenReturn(Optional.of(sender));

        assertThrows(IllegalArgumentException.class, () -> paymentGatewayService.initiate(request));

        verify(redisTemplate).delete("payment:idempotency:tx-insufficient-1");
        verify(paymentRepository, never()).saveAndFlush(any(Payment.class));
    }
}
