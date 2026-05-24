import http from "k6/http";
import { check, sleep } from "k6";

export const options = {
  scenarios: {
    swiftpay_250_tps: {
      executor: "constant-arrival-rate",
      rate: 250,
      timeUnit: "1s",
      duration: "1h6m40s",
      preAllocatedVUs: 200,
      maxVUs: 1000,
    },
  },
  thresholds: {
    http_req_failed: ["rate<0.01"],
    http_req_duration: ["p(95)<500"],
  },
};

const baseUrl = __ENV.BASE_URL || "http://localhost:8080";

export default function () {
  const tx = `${Date.now()}-${__VU}-${__ITER}`;
  const body = JSON.stringify({
    senderId: "user-100",
    receiverId: "user-200",
    amount: "1.00",
    currency: "USD",
    transactionId: tx,
  });

  const response = http.post(`${baseUrl}/v1/payments`, body, {
    headers: { "Content-Type": "application/json" },
  });

  check(response, {
    "accepted": (r) => r.status === 202,
  });
  sleep(0.1);
}
