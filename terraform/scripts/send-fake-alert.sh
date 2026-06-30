#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  TENANT_ID=tenant-a ./scripts/send-fake-alert.sh <lambda-url> <alert-json-file> [webhook-secret]

The optional webhook secret signs the request with the existing x-tf1-* headers.
If TENANT_ID is set, the script sends x-tenant-id and the Lambda will enforce a match.
USAGE
}

if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
  usage
  exit 1
fi

lambda_url="$1"
alert_file="$2"
webhook_secret="${3:-}"
timestamp="$(date +%s)"

headers=(-H "content-type: application/json")

if [ -n "${TENANT_ID:-}" ]; then
  headers+=(-H "x-tenant-id: ${TENANT_ID}")
fi

if [ -n "$webhook_secret" ]; then
  signature="$(
    python3 - "$webhook_secret" "$timestamp" "$alert_file" <<'PY'
import hashlib
import hmac
import sys

secret, timestamp, alert_file = sys.argv[1], sys.argv[2], sys.argv[3]
with open(alert_file, "rb") as fh:
    body = fh.read()
signed = timestamp.encode("utf-8") + b"." + body
print(hmac.new(secret.encode("utf-8"), signed, hashlib.sha256).hexdigest())
PY
  )"
  headers+=(-H "x-tf1-timestamp: ${timestamp}" -H "x-tf1-signature: ${signature}")
fi

curl -sS -X POST "$lambda_url" "${headers[@]}" --data-binary "@${alert_file}"
