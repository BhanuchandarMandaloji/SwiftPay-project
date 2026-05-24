package com.swiftpay.project.payment;

import com.swiftpay.project.account.Account;
import com.swiftpay.project.account.AccountRepository;
import com.swiftpay.project.config.KafkaTopics;
import com.swiftpay.project.event.PaymentInitiatedEvent;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Duration;
import java.util.concurrent.TimeUnit;

@Service
public class PaymentGatewayService {
    private static final Logger log = LoggerFactory.getLogger(PaymentGatewayService.class);
    private static final Duration IDEMPOTENCY_WINDOW = Duration.ofHours(24);

    private final PaymentRepository paymentRepository;
    private final AccountRepository accountRepository;
    private final StringRedisTemplate redisTemplate;
    private final KafkaTemplate<String, Object> kafkaTemplate;

    public PaymentGatewayService(
            PaymentRepository paymentRepository,
            AccountRepository accountRepository,
            StringRedisTemplate redisTemplate,
            KafkaTemplate<String, Object> kafkaTemplate
    ) {
        this.paymentRepository = paymentRepository;
        this.accountRepository = accountRepository;
        this.redisTemplate = redisTemplate;
        this.kafkaTemplate = kafkaTemplate;
    }

    @Transactional
    public PaymentResponse initiate(CreatePaymentRequest request) {
        if (request.senderId().equals(request.receiverId())) {
            throw new IllegalArgumentException("senderId and receiverId must be different");
        }

        String idempotencyKey = "payment:idempotency:" + request.transactionId();
        Boolean accepted = redisTemplate.opsForValue()
                .setIfAbsent(idempotencyKey, "PROCESSING", IDEMPOTENCY_WINDOW);

        if (Boolean.FALSE.equals(accepted)) {
            return paymentRepository.findByTransactionId(request.transactionId())
                    .map(PaymentResponse::from)
                    .orElseThrow(() -> new IllegalArgumentException("Duplicate transaction_id is already being processed"));
        }

        try {
            Account sender = accountRepository.findById(request.senderId())
                    .orElseThrow(() -> new IllegalArgumentException("Sender account not found"));
            if (!sender.getCurrency().equals(request.currency())) {
                throw new IllegalArgumentException("Sender currency does not match payment currency");
            }
            if (sender.getBalance().compareTo(request.amount()) < 0) {
                throw new IllegalArgumentException("Insufficient funds");
            }

            Payment payment = new Payment(
                    request.transactionId(),
                    request.senderId(),
                    request.receiverId(),
                    request.amount(),
                    request.currency()
            );
            Payment saved = paymentRepository.saveAndFlush(payment);
            PaymentInitiatedEvent event = new PaymentInitiatedEvent(
                    saved.getId(),
                    saved.getTransactionId(),
                    saved.getSenderId(),
                    saved.getReceiverId(),
                    saved.getAmount(),
                    saved.getCurrency()
            );
            kafkaTemplate.send(KafkaTopics.PAYMENT_INITIATED, saved.getTransactionId(), event).get(5, TimeUnit.SECONDS);
            log.info("PaymentInitiated emitted for transactionId={}", saved.getTransactionId());
            return PaymentResponse.from(saved);
        } catch (DataIntegrityViolationException ex) {
            return paymentRepository.findByTransactionId(request.transactionId())
                    .map(PaymentResponse::from)
                    .orElseThrow(() -> ex);
        } catch (RuntimeException ex) {
            redisTemplate.delete(idempotencyKey);
            throw ex;
        } catch (Exception ex) {
            redisTemplate.delete(idempotencyKey);
            throw new IllegalStateException("Unable to publish payment event", ex);
        }
    }
}
