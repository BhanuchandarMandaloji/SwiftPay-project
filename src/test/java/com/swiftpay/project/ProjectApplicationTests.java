package com.swiftpay.project;

import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.test.context.ActiveProfiles;

@SpringBootTest
@ActiveProfiles("test")
class ProjectApplicationTests {
	@MockBean
	StringRedisTemplate redisTemplate;

	@MockBean
	KafkaTemplate<String, Object> kafkaTemplate;

	@Test
	void contextLoads() {
	}

}
