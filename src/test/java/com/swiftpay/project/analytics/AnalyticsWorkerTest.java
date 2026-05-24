package com.swiftpay.project.analytics;

import com.swiftpay.project.event.PaymentStatusEvent;
import com.swiftpay.project.payment.Payment;
import com.swiftpay.project.payment.PaymentRepository;
import com.swiftpay.project.payment.PaymentStatus;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.test.util.ReflectionTestUtils;

import java.math.BigDecimal;
import java.util.Optional;
import java.util.UUID;

import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class AnalyticsWorkerTest {
    @Mock
    private PaymentRepository paymentRepository;
    @Mock
    private AnalyticsPaymentRepository analyticsPaymentRepository;

    @Test
    void shouldIgnoreAlreadyPersistedAnalyticsRecord() {
        AnalyticsWorker worker = new AnalyticsWorker(paymentRepository, analyticsPaymentRepository);
        Payment payment = new Payment("tx-analytics-1", "user-100", "user-200", new BigDecimal("10.00"), "USD");
        UUID paymentId = UUID.randomUUID();
        ReflectionTestUtils.setField(payment, "id", paymentId);
        PaymentStatusEvent event = new PaymentStatusEvent(
                UUID.randomUUID(), "tx-analytics-1", PaymentStatus.COMPLETED, null
        );

        when(paymentRepository.findByTransactionId("tx-analytics-1")).thenReturn(Optional.of(payment));
        when(analyticsPaymentRepository.existsById(paymentId)).thenReturn(true);

        worker.onPaymentStatus(event);

        verify(analyticsPaymentRepository, never()).save(org.mockito.ArgumentMatchers.any(AnalyticsPayment.class));
    }
}
