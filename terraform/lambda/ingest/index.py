import base64
import hashlib
import hmac
import json
import os
import time
from typing import Any, Dict

import boto3


sqs = boto3.client("sqs")
secrets = boto3.client("secretsmanager")


REQUIRED_LABELS = ["tenant_id", "service", "env", "severity"]


def _response(status: int, body: Dict[str, Any]) -> Dict[str, Any]:
    return {
        "statusCode": status,
        "headers": {"content-type": "application/json"},
        "body": json.dumps(body),
    }


def _raw_body(event: Dict[str, Any]) -> bytes:
    body = event.get("body") or ""
    if event.get("isBase64Encoded"):
        return base64.b64decode(body)
    return body.encode("utf-8")


def _headers(event: Dict[str, Any]) -> Dict[str, str]:
    return {str(k).lower(): str(v) for k, v in (event.get("headers") or {}).items()}


def _get_secret() -> str:
    arn = os.environ.get("WEBHOOK_SIGNING_SECRET_ARN")
    if not arn:
        return ""
    value = secrets.get_secret_value(SecretId=arn)
    return value.get("SecretString", "")


def _verify_signature(event: Dict[str, Any], body: bytes) -> bool:
    secret = _get_secret()
    if not secret:
        return True

    headers = _headers(event)
    timestamp = headers.get("x-tf1-timestamp", "")
    signature = headers.get("x-tf1-signature", "")
    if not timestamp or not signature:
        return False

    try:
        ts = int(timestamp)
    except ValueError:
        return False

    if abs(int(time.time()) - ts) > 300:
        return False

    signed = f"{timestamp}.".encode("utf-8") + body
    expected = hmac.new(secret.encode("utf-8"), signed, hashlib.sha256).hexdigest()
    return hmac.compare_digest(signature, expected)


def _normalize_alert(payload: Dict[str, Any], tenant_header: str) -> Dict[str, Any]:
    labels = payload.get("labels") or {}
    annotations = payload.get("annotations") or {}

    alert = {
        "schema_version": "tf1.incident_seed.v1",
        "tenant_id": payload.get("tenant_id") or labels.get("tenant_id"),
        "service": payload.get("service") or labels.get("service"),
        "env": payload.get("env") or labels.get("env") or labels.get("environment"),
        "severity": payload.get("severity") or labels.get("severity"),
        "alert_name": payload.get("alert_name") or labels.get("alertname"),
        "alert_fingerprint": payload.get("fingerprint") or payload.get("alert_fingerprint"),
        "starts_at": payload.get("startsAt") or payload.get("starts_at"),
        "ends_at": payload.get("endsAt") or payload.get("ends_at"),
        "status": payload.get("status", "firing"),
        "summary": payload.get("summary") or annotations.get("summary", ""),
        "description": payload.get("description") or annotations.get("description", ""),
        "source": "alertmanager",
        "raw": payload,
    }

    missing = [field for field in ["tenant_id", "service", "env", "severity", "alert_fingerprint"] if not alert.get(field)]
    if missing:
        raise ValueError(f"missing required fields: {','.join(missing)}")

    if tenant_header and tenant_header != alert["tenant_id"]:
        raise ValueError("tenant header does not match payload tenant_id")

    return alert


def _message_group_id(alert: Dict[str, Any]) -> str:
    raw_group = f"{alert['tenant_id']}#{alert['service']}#{alert['env']}"
    return hashlib.sha256(raw_group.encode("utf-8")).hexdigest()


def _message_deduplication_id(alert: Dict[str, Any]) -> str:
    raw_dedup = "#".join(
        [
            alert["tenant_id"],
            alert["service"],
            alert["env"],
            alert.get("alert_fingerprint") or "",
            alert.get("status") or "firing",
            alert.get("starts_at") or "",
        ]
    )
    return hashlib.sha256(raw_dedup.encode("utf-8")).hexdigest()


def handler(event: Dict[str, Any], _context: Any) -> Dict[str, Any]:
    body = _raw_body(event)
    if not _verify_signature(event, body):
        return _response(401, {"ok": False, "error": "invalid signature"})

    try:
        payload = json.loads(body.decode("utf-8"))
    except json.JSONDecodeError:
        return _response(400, {"ok": False, "error": "invalid json"})

    headers = _headers(event)
    try:
        alert = _normalize_alert(payload, headers.get("x-tenant-id", ""))
    except ValueError as exc:
        return _response(400, {"ok": False, "error": str(exc)})

    sqs.send_message(
        QueueUrl=os.environ["INCIDENT_QUEUE_URL"],
        MessageBody=json.dumps(alert),
        MessageGroupId=_message_group_id(alert),
        MessageDeduplicationId=_message_deduplication_id(alert),
        MessageAttributes={
            "tenant_id": {"DataType": "String", "StringValue": alert["tenant_id"]},
            "service": {"DataType": "String", "StringValue": alert["service"]},
            "env": {"DataType": "String", "StringValue": alert["env"]},
            "severity": {"DataType": "String", "StringValue": alert["severity"]},
        },
    )

    return _response(202, {"ok": True, "tenant_id": alert["tenant_id"], "fingerprint": alert["alert_fingerprint"]})
