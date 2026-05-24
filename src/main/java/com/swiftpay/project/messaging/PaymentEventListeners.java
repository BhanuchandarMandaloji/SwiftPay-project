package com.swiftpay.project.messaging;

import com.swiftpay.project.config.KafkaTopics;
import com.swiftpay.project.event.PaymentInitiatedEvent;
import com.swiftpay.project.event.PaymentStatusEvent;
import com.swiftpay.project.ledger.LedgerService;
import com.swiftpay.project.payment.PaymentStatusUpdater;
import org.springframework.kafka.annotation.KafkaListener;
import org.springframework.stereotype.Component;

@Component
public class PaymentEventListeners {
    private final LedgerService ledgerService;
    private final PaymentStatusUpdater paymentStatusUpdater;

    public PaymentEventListeners(LedgerService ledgerService, PaymentStatusUpdater paymentStatusUpdater) {
        this.ledgerService = ledgerService;
        this.paymentStatusUpdater = paymentStatusUpdater;
    }

    @KafkaListener(topics = KafkaTopics.PAYMENT_INITIATED, groupId = "swiftpay-ledger")
    public void onPaymentInitiated(PaymentInitiatedEvent event) {
        ledgerService.process(event);
    }

    @KafkaListener(topics = KafkaTopics.PAYMENT_STATUS, groupId = "swiftpay-gateway")
    public void onPaymentStatus(PaymentStatusEvent event) {
        paymentStatusUpdater.apply(event);
    }
}
