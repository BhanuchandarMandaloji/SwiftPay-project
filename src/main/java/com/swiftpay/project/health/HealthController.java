package com.swiftpay.project.health;

import io.swagger.v3.oas.annotations.Operation;
import org.springframework.boot.actuate.health.HealthEndpoint;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class HealthController {
    private final HealthEndpoint healthEndpoint;

    public HealthController(HealthEndpoint healthEndpoint) {
        this.healthEndpoint = healthEndpoint;
    }

    @GetMapping("/health")
    @Operation(summary = "Application health check")
    public Object health() {
        return healthEndpoint.health();
    }
}
