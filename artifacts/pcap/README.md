# Capture Verification

The checked-in artifact is `swiftpay-250tps-1m.pcapng`.

Verified with Wireshark tools:
- `capinfos` reports 110 packets and `NULL/Loopback` encapsulation.
- `tshark` decodes HTTP traffic, including `GET /health` and `200` responses.
