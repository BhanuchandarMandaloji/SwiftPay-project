package com.swiftpay.project.analytics;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.UUID;

@Entity
@Table(name = "analytics_payments")
public class AnalyticsPayment {
    @Id
    @Column(name = "payment_id")
    private UUID paymentId;

    @Column(name = "transaction_id", nullable = false, length = 128)
    private String transactionId;

    @Column(nullable = false, precision = 19, scale = 4)
    private BigDecimal amount;

    @Column(nullable = false, length = 3)
    private String currency;

    @Column(name = "completed_at", nullable = false)
    private Instant completedAt;

    protected AnalyticsPayment() {
    }

    public AnalyticsPayment(UUID paymentId, String transactionId, BigDecimal amount, String currency) {
        this.paymentId = paymentId;
        this.transactionId = transactionId;
        this.amount = amount;
        this.currency = currency;
        this.completedAt = Instant.now();
    }
}
