package com.swiftpay.project.ledger;

import com.swiftpay.project.account.Account;
import com.swiftpay.project.account.AccountRepository;
import com.swiftpay.project.event.PaymentInitiatedEvent;
import com.swiftpay.project.payment.Payment;
import com.swiftpay.project.payment.PaymentRepository;
import com.swiftpay.project.payment.PaymentStatus;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.kafka.core.KafkaTemplate;

import java.math.BigDecimal;
import java.util.Optional;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class LedgerServiceTest {
    @Mock
    private AccountRepository accountRepository;
    @Mock
    private PaymentRepository paymentRepository;
    @Mock
    private LedgerEntryRepository ledgerEntryRepository;
    @Mock
    private KafkaTemplate<String, Object> kafkaTemplate;

    @Test
    void shouldProcessReplayOnlyOnce() {
        LedgerService ledgerService = new LedgerService(
                accountRepository,
                paymentRepository,
                ledgerEntryRepository,
                kafkaTemplate
        );

        UUID paymentId = UUID.randomUUID();
        Payment payment = new Payment("tx-replay-1", "user-100", "user-200", new BigDecimal("10.00"), "USD");
        PaymentInitiatedEvent event = new PaymentInitiatedEvent(
                paymentId, "tx-replay-1", "user-100", "user-200", new BigDecimal("10.00"), "USD"
        );
        Account sender = new Account("user-100", new BigDecimal("100.00"), "USD");
        Account receiver = new Account("user-200", new BigDecimal("50.00"), "USD");

        when(paymentRepository.findByIdForUpdate(paymentId)).thenReturn(Optional.of(payment));
        when(accountRepository.findByIdForUpdate("user-100")).thenReturn(Optional.of(sender));
        when(accountRepository.findByIdForUpdate("user-200")).thenReturn(Optional.of(receiver));

        ledgerService.process(event);
        ledgerService.process(event);

        assertEquals(new BigDecimal("90.00"), sender.getBalance());
        assertEquals(new BigDecimal("60.00"), receiver.getBalance());
        assertEquals(PaymentStatus.COMPLETED, payment.getStatus());
        verify(ledgerEntryRepository, times(2)).save(any(LedgerEntry.class));
        verify(kafkaTemplate, times(1)).send(anyString(), anyString(), any());
    }
}
