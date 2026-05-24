package com.swiftpay.project.event;

import com.swiftpay.project.payment.PaymentStatus;

import java.util.UUID;

public record PaymentStatusEvent(
        UUID paymentId,
        String transactionId,
        PaymentStatus status,
        String failureReason
) {
}
