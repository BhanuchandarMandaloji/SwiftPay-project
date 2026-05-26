import http from "k6/http";
import { check } from "k6";

export const options = {
  scenarios: {
    swiftpay_250_tps: {
      executor: "constant-arrival-rate",
      rate: 250,
      timeUnit: "1s",
      duration: "1h6m40s",
      preAllocatedVUs: 1000,
      maxVUs: 5000,
    },
  },
  discardResponseBodies: true,
};

const baseUrl = __ENV.BASE_URL || "http://localhost:8080";

export default function () {
  const tx = `${Date.now()}-${__VU}-${__ITER}`;
  const body = JSON.stringify({
    senderId: "user-100",
    receiverId: "user-200",
    amount: 1.00,
    currency: "USD",
    transactionId: tx,
  });

  const response = http.post(`${baseUrl}/v1/payments`, body, {
    headers: { "Content-Type": "application/json" },
  });

  check(response, {
    "accepted": (r) => r.status === 202,
  });
}
