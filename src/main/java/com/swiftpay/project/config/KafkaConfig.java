package com.swiftpay.project.config;

import org.apache.kafka.clients.admin.NewTopic;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.kafka.config.TopicBuilder;

@Configuration
public class KafkaConfig {
    @Bean
    NewTopic paymentInitiatedTopic() {
        return TopicBuilder.name(KafkaTopics.PAYMENT_INITIATED).partitions(3).replicas(1).build();
    }

    @Bean
    NewTopic paymentStatusTopic() {
        return TopicBuilder.name(KafkaTopics.PAYMENT_STATUS).partitions(3).replicas(1).build();
    }
}
