# SwiftPay Real-Time Payment Ledger

SwiftPay is a Java 21 Spring Boot implementation of the requested P2P payment ledger. It uses MySQL for transactional storage, Kafka for payment events, Redis for 24-hour idempotency, and Swagger/OpenAPI for API documentation.

## Services

- Service A, Transaction Gateway: `POST /v1/payments` validates the sender balance, stores a `PENDING` payment, enforces Redis idempotency by `transactionId`, and emits `PaymentInitiated`.
- Service B, Ledger Processor: consumes `PaymentInitiated`, debits and credits accounts inside one database transaction, writes ledger entries, and emits `PaymentCompleted` or `PaymentFailed` status events.
- Service B, Reporting: `GET /v1/users/{userId}/transactions` returns user transaction history.
- Service C, Analytics Worker: consumes completed status events and writes a mock OLAP row to `analytics_payments`.

## Run Locally

```bash
docker compose up --build
```

Useful URLs:

- API health: `http://localhost:8080/health`
- Swagger UI: `http://localhost:8080/swagger-ui.html`
- OpenAPI JSON: `http://localhost:8080/v3/api-docs`

If you want to run the app on Windows without Docker, start the repo-local MySQL instance first:

```powershell
.\scripts\start-mysql-local.ps1
.\mvnw spring-boot:run
```

That script provisions `artifacts/mysql-data/` and configures the `swiftpay / swiftpay` credentials expected by `application.properties`.
For MySQL Workbench on Windows, connect to `127.0.0.1:3306` with the `swiftpay / swiftpay` account after starting the script.

Seeded demo accounts:

- `user-100`, USD 10000.00
- `user-200`, USD 500.00
- `user-300`, USD 750.00

Example payment:

```bash
curl -X POST http://localhost:8080/v1/payments \
  -H "Content-Type: application/json" \
  -d '{"senderId":"user-100","receiverId":"user-200","amount":"10.00","currency":"USD","transactionId":"tx-001"}'
```

## Failure Handling

- Duplicate `transactionId` values are rejected or return the existing payment inside a 24-hour Redis window.
- Insufficient funds are rejected before the event is emitted and rechecked during ledger processing.
- Kafka publish failures fail the payment initiation request instead of silently accepting it.
- Consumer processing is transactional; transient database errors are retried by Kafka listener retry behavior.
- API errors use a consistent JSON response with status, message, timestamp, and path.

## Load Tuning

The datasource pool is tuned for the 250 TPS load run so the gateway does not spend the entire test stalled on connection acquisition:

- Hikari maximum pool size: `100`
- Hikari minimum idle: `20`
- Hikari connection timeout: `10000` ms

## Testing and CI

```bash
./mvnw test
```

The GitHub Actions workflow compiles the Java code, runs tests, and builds the Docker image.

## Load Test

The k6 script targets 250 TPS for 1,000,000 transactions.

```bash
k6 run scripts/load-test.js
```

## PCAP Artifact

The checked-in artifact for review is `artifacts/pcap/load-test.pcapng`.

Use the Docker-based capture path if you need to regenerate a `.pcap` version. It starts the MySQL, Redis, Kafka, and app services in Docker, runs the load generator in the same compose network, and captures the app-side traffic with `tcpdump`.

```powershell
.\scripts\capture-pcap-docker.ps1
```

The generated artifact is written to `artifacts/pcap/load-test.pcap`.
If you want to use a different load command, pass it with `-LoadCommand`. The default load command runs `k6` through Docker Compose, so the host does not need a local `k6` install.

## Local PCAP Artifact

If Docker Desktop is unavailable on the machine, use the local Wireshark/Npcap path instead. Install Wireshark and Npcap, start MySQL, Redis, Kafka, and the app on localhost, then run:

If the Windows `MySQL80` service is stopped, run `.\scripts\start-mysql-local.ps1` first.

```powershell
.\scripts\capture-pcap-local.ps1
```

The local capture uses the Npcap loopback adapter and writes the artifact to `artifacts/pcap/load-test.pcapng`. If `dumpcap` cannot see a loopback interface, Npcap is not installed correctly yet.
It applies the TCP capture filter directly, so it avoids the large raw-file post-processing step that can fail on long load runs.

Verification details for the checked-in capture are in [artifacts/pcap/README.md](artifacts/pcap/README.md).
