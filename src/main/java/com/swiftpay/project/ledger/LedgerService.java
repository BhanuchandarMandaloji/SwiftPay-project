package com.swiftpay.project.ledger;

import com.swiftpay.project.account.Account;
import com.swiftpay.project.account.AccountRepository;
import com.swiftpay.project.config.KafkaTopics;
import com.swiftpay.project.event.PaymentInitiatedEvent;
import com.swiftpay.project.event.PaymentStatusEvent;
import com.swiftpay.project.payment.Payment;
import com.swiftpay.project.payment.PaymentRepository;
import com.swiftpay.project.payment.PaymentStatus;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class LedgerService {
    private static final Logger log = LoggerFactory.getLogger(LedgerService.class);

    private final AccountRepository accountRepository;
    private final PaymentRepository paymentRepository;
    private final LedgerEntryRepository ledgerEntryRepository;
    private final KafkaTemplate<String, Object> kafkaTemplate;

    public LedgerService(
            AccountRepository accountRepository,
            PaymentRepository paymentRepository,
            LedgerEntryRepository ledgerEntryRepository,
            KafkaTemplate<String, Object> kafkaTemplate
    ) {
        this.accountRepository = accountRepository;
        this.paymentRepository = paymentRepository;
        this.ledgerEntryRepository = ledgerEntryRepository;
        this.kafkaTemplate = kafkaTemplate;
    }

    @Transactional
    public void process(PaymentInitiatedEvent event) {
        try {
            Payment payment = paymentRepository.findByIdForUpdate(event.paymentId())
                    .orElseThrow(() -> new IllegalArgumentException("Payment not found"));
            if (payment.getStatus() != PaymentStatus.PENDING) {
                log.info("Skipping transactionId={} because status is {}", event.transactionId(), payment.getStatus());
                return;
            }

            Account sender = accountRepository.findByIdForUpdate(event.senderId())
                    .orElseThrow(() -> new IllegalArgumentException("Sender account not found"));
            Account receiver = accountRepository.findByIdForUpdate(event.receiverId())
                    .orElseThrow(() -> new IllegalArgumentException("Receiver account not found"));

            if (!sender.getCurrency().equals(event.currency()) || !receiver.getCurrency().equals(event.currency())) {
                payment.fail("Account currency does not match payment currency");
                publishStatus(event, PaymentStatus.FAILED, "Account currency does not match payment currency");
                return;
            }
            if (sender.getBalance().compareTo(event.amount()) < 0) {
                payment.fail("Insufficient funds");
                publishStatus(event, PaymentStatus.FAILED, "Insufficient funds");
                return;
            }

            sender.debit(event.amount());
            receiver.credit(event.amount());
            payment.complete();
            ledgerEntryRepository.save(new LedgerEntry(
                    event.paymentId(), event.senderId(), LedgerEntryType.DEBIT, event.amount(), event.currency()));
            ledgerEntryRepository.save(new LedgerEntry(
                    event.paymentId(), event.receiverId(), LedgerEntryType.CREDIT, event.amount(), event.currency()));
            publishStatus(event, PaymentStatus.COMPLETED, null);
        } catch (RuntimeException ex) {
            log.warn("Payment processing failed for transactionId={}", event.transactionId(), ex);
            throw ex;
        }
    }

    private void publishStatus(PaymentInitiatedEvent event, PaymentStatus status, String failureReason) {
        PaymentStatusEvent statusEvent = new PaymentStatusEvent(
                event.paymentId(), event.transactionId(), status, failureReason);
        kafkaTemplate.send(KafkaTopics.PAYMENT_STATUS, event.transactionId(), statusEvent);
        log.info("PaymentStatus emitted transactionId={} status={}", event.transactionId(), status);
    }
}
