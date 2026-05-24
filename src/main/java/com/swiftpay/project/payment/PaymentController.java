package com.swiftpay.project.payment;

import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

@RestController
@RequestMapping("/v1")
@Tag(name = "Payments")
public class PaymentController {
    private final PaymentGatewayService paymentGatewayService;
    private final PaymentRepository paymentRepository;

    public PaymentController(PaymentGatewayService paymentGatewayService, PaymentRepository paymentRepository) {
        this.paymentGatewayService = paymentGatewayService;
        this.paymentRepository = paymentRepository;
    }

    @PostMapping("/payments")
    @ResponseStatus(HttpStatus.ACCEPTED)
    @Operation(summary = "Initiate a P2P payment")
    public PaymentResponse create(@Valid @RequestBody CreatePaymentRequest request) {
        return paymentGatewayService.initiate(request);
    }

    @GetMapping("/users/{userId}/transactions")
    @Operation(summary = "Fetch transaction history for a user")
    public List<PaymentResponse> history(@PathVariable String userId) {
        return paymentRepository.findBySenderIdOrReceiverIdOrderByCreatedAtDesc(userId, userId)
                .stream()
                .map(PaymentResponse::from)
                .toList();
    }
}
