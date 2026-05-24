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

To capture a PCAP trace during the run:

```bash
sudo tcpdump -i any -w swiftpay-250tps-1m.pcap port 8080 or port 9092 or port 3306 or port 6379
```

## PCAP Artifact

On Windows, run the capture wrapper from an elevated PowerShell session:

```powershell
.\scripts\capture-pcap.ps1 -LoadCommand "k6 run scripts/load-test.js"
```

The generated artifact is written to `artifacts/pcap/swiftpay-250tps-1m.pcapng`.
The capture needs an administrator shell because `pktmon` cannot start from a medium-integrity session.
Install `k6` first or pass a different `-LoadCommand` if you want to use another load generator.

```powershell
winget install grafana.k6
```
