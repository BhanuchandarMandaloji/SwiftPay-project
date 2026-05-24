package com.swiftpay.project.event;

import java.math.BigDecimal;
import java.util.UUID;

public record PaymentInitiatedEvent(
        UUID paymentId,
        String transactionId,
        String senderId,
        String receiverId,
        BigDecimal amount,
        String currency
) {
}
