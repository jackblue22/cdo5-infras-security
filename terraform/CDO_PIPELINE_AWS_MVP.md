# CDO Ingest AWS MVP

This branch implements only the Ingest foundation for the CDO pipeline.

It does not deploy or implement Correlator, Evidence Builder, Triage Context Builder, AIO calls, RCA logic, Jira/Slack integrations, or Kubernetes workloads.

## Flow

```text
Raw alert / Alertmanager webhook
-> Ingest Lambda Function URL
-> S3 raw + normalized pre-correlation artifacts
-> DynamoDB idempotency table
-> SQS normalized-alert reference message
-> future Correlator workload
```

## Lambda Input

The Lambda supports one alert object per request. Batch payloads such as `{ "alerts": [...] }` are rejected for this MVP.

Required metadata may be present on the top-level object or in `labels`:

```text
alert_id
tenant_id
environment
cluster
namespace
source
service
severity
title
started_at
```

Supported aliases:

```text
environment <- environment or env
started_at  <- started_at, startsAt, or starts_at
title       <- title, summary, annotations.title, annotations.summary, alert_name, or alertname
```

The Lambda keeps the existing guardrails:

```text
x-tf1-signature
x-tf1-timestamp
x-tenant-id
```

If `x-tenant-id` is present, it must match the normalized `tenant_id`.

## Normalized Wrapper

Accepted alerts are normalized to:

```json
{
  "ingest_id": "ingest-...",
  "schema_version": "cdo.alert.v1",
  "received_at": "2026-06-29T10:01:00Z",
  "raw_source": "prometheus",
  "normalized_alert": {
    "alert_id": "...",
    "tenant_id": "...",
    "environment": "prod",
    "cluster": "eks-prod",
    "namespace": "bookhub-prod",
    "source": "prometheus",
    "service": "book-service",
    "severity": "critical",
    "title": "...",
    "description": "...",
    "started_at": "2026-06-29T10:00:00Z",
    "labels": {}
  },
  "validation": {
    "status": "VALID",
    "missing_fields": [],
    "missing_optional_fields": []
  },
  "enrichment": {
    "status": "NOT_NEEDED",
    "source": null,
    "enriched_fields": []
  }
}
```

`tenant_id`, `environment`, `cluster`, and `namespace` are promoted to `normalized_alert` top-level fields and removed from `normalized_alert.labels`.

No service-catalog enrichment is performed in this AWS MVP.

## Validation

```text
VALID:
  required fields present
  optional fields present
  write artifacts, write idempotency item, publish SQS

VALID_WITH_WARNINGS:
  required fields present
  one or more optional fields missing
  write artifacts, write idempotency item, publish SQS

INVALID_ALERT:
  one or more required fields missing or environment invalid
  write audit artifacts if S3 is configured
  do not write processed idempotency item
  do not publish SQS
```

Allowed environments:

```text
prod
staging
sandbox
```

Severity normalization:

```text
critical -> critical
high     -> high
warning  -> medium
medium   -> medium
low      -> low
info     -> low
unknown  -> unknown
other    -> unknown
missing  -> INVALID_ALERT
```

## S3 Layout

Raw alert artifact:

```text
s3://<bucket>/tenants/<tenant_id>/envs/<environment>/pre-correlation/raw-alerts/yyyy/mm/dd/<alert_id>/<ingest_id>.json
```

Normalized alert artifact:

```text
s3://<bucket>/tenants/<tenant_id>/envs/<environment>/pre-correlation/normalized-alerts/yyyy/mm/dd/<alert_id>/<ingest_id>.json
```

Invalid safe prefix:

```text
s3://<bucket>/invalid/pre-correlation/raw-alerts/yyyy/mm/dd/<ingest_id>.json
s3://<bucket>/invalid/pre-correlation/normalized-alerts/yyyy/mm/dd/<ingest_id>.json
```

S3 stores artifacts, audit, and replay data. DynamoDB remains the live-state/idempotency source of truth.

## DynamoDB Idempotency

This branch creates a dedicated table:

```text
<name_prefix>-idempotency
hash key: PK
```

The existing `<name_prefix>-incident-state` table is unchanged and remains reserved for future Correlator/open-incident state.

Idempotency item key:

```text
PK = IDEMPOTENCY#<tenant_id>#<environment>#<alert_id>#<started_at>#<fingerprint>
```

The Lambda writes the idempotency item with:

```text
ConditionExpression = attribute_not_exists(PK)
```

If the item already exists, the Lambda returns `DUPLICATE` and does not publish another SQS message.

## SQS Message

The existing physical FIFO queue is not renamed or recreated. It is exposed through normalized-alert aliases:

```text
normalized_alerts_queue_url
normalized_alerts_queue_arn
normalized_alerts_queue_name
```

Message body:

```json
{
  "schema_version": "cdo.normalized_alert_ref.v1",
  "ingest_id": "ingest-...",
  "alert_id": "alert-book-service-5xx-001",
  "tenant_id": "tenant-a",
  "environment": "prod",
  "cluster": "eks-prod",
  "namespace": "bookhub-prod",
  "service": "book-service",
  "severity": "critical",
  "started_at": "2026-06-29T10:00:00Z",
  "validation_status": "VALID",
  "normalized_alert_uri": "s3://..."
}
```

Only `VALID` and `VALID_WITH_WARNINGS` alerts are published.

## Smoke Test

After Terraform apply, send a fake alert:

```bash
cd terraform
TENANT_ID=tenant-a ./scripts/send-fake-alert.sh \
  "$(terraform -chdir=environments/dev output -raw ingest_lambda_function_url)" \
  /path/to/fake-alert.json \
  "$WEBHOOK_SIGNING_SECRET"
```

If the webhook secret is empty or unset in AWS, omit the third argument.

Then verify:

```bash
terraform -chdir=environments/dev output -raw audit_bucket_name
terraform -chdir=environments/dev output -raw idempotency_table_name
terraform -chdir=environments/dev output -raw normalized_alerts_queue_url
```

Expected result:

```text
Lambda response: ACCEPTED, ACCEPTED_WITH_WARNINGS, REJECTED, or DUPLICATE
S3 contains raw + normalized artifacts
DynamoDB contains one idempotency item for accepted alerts
SQS receives one normalized-alert reference for accepted non-duplicate alerts
```

## Out Of Scope

```text
Correlator
Evidence Builder
Triage Context Builder
Contract Validator
AIO /v1/triage client
fallback diagnosis
RCA logic
confidence score
recommended actions
ticket payload
Jira integration
Slack integration
Kubernetes Deployment/Namespace/ServiceAccount
AI Engine workload
physical queue rename/recreate
```
