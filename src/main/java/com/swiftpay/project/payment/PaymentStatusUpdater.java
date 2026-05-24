package com.swiftpay.project.payment;

import com.swiftpay.project.event.PaymentStatusEvent;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class PaymentStatusUpdater {
    private final PaymentRepository paymentRepository;

    public PaymentStatusUpdater(PaymentRepository paymentRepository) {
        this.paymentRepository = paymentRepository;
    }

    @Transactional
    public void apply(PaymentStatusEvent event) {
        Payment payment = paymentRepository.findByTransactionId(event.transactionId())
                .orElseThrow(() -> new IllegalArgumentException("Payment not found"));
        if (payment.getStatus() == event.status()) {
            return;
        }
        if (event.status() == PaymentStatus.COMPLETED) {
            payment.complete();
        } else {
            payment.fail(event.failureReason());
        }
    }
}
