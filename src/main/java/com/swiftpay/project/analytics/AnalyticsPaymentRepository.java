package com.swiftpay.project.analytics;

import org.springframework.data.jpa.repository.JpaRepository;

import java.util.UUID;

public interface AnalyticsPaymentRepository extends JpaRepository<AnalyticsPayment, UUID> {
}
