package com.swiftpay.project.analytics;

import com.swiftpay.project.config.KafkaTopics;
import com.swiftpay.project.event.PaymentStatusEvent;
import com.swiftpay.project.payment.Payment;
import com.swiftpay.project.payment.PaymentRepository;
import com.swiftpay.project.payment.PaymentStatus;
import org.springframework.kafka.annotation.KafkaListener;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

@Component
public class AnalyticsWorker {
    private final PaymentRepository paymentRepository;
    private final AnalyticsPaymentRepository analyticsPaymentRepository;

    public AnalyticsWorker(PaymentRepository paymentRepository, AnalyticsPaymentRepository analyticsPaymentRepository) {
        this.paymentRepository = paymentRepository;
        this.analyticsPaymentRepository = analyticsPaymentRepository;
    }

    @Transactional
    @KafkaListener(topics = KafkaTopics.PAYMENT_STATUS, groupId = "swiftpay-analytics")
    public void onPaymentStatus(PaymentStatusEvent event) {
        if (event.status() != PaymentStatus.COMPLETED) {
            return;
        }

        Payment payment = paymentRepository.findByTransactionId(event.transactionId())
                .orElseThrow(() -> new IllegalArgumentException("Payment not found"));
        if (analyticsPaymentRepository.existsById(payment.getId())) {
            return;
        }
        analyticsPaymentRepository.save(new AnalyticsPayment(
                payment.getId(),
                payment.getTransactionId(),
                payment.getAmount(),
                payment.getCurrency()
        ));
    }
}
