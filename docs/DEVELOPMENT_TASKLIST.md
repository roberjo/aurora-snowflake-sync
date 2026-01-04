# Development Tasklist

Canonical architecture is AWS DMS CDC → S3 → Snowpipe/Tasks (managed in this repo). Tasks are prioritized to make the current Terraform stack deployable and secure.

## P0 — Fix functional gaps
- Align docs (Architecture, Runbook, FAQ, Data Sync) to the DMS CDC path and remove the Lambda watermark narrative.
- Finish Snowflake ingestion in Terraform: create staging tables, warehouse, per-table merge tasks/proc; ensure Pipes reference real tables.
- Wire S3 ↔ Snowflake: bucket policy for `storage_aws_role_arn` (TLS-only), trust update for Snowflake IAM user/external ID, S3 event notifications to Snowflake SQS with dependencies.

## P1 — Harden security and resilience
- Storage hardening: switch bucket to SSE-KMS, add access logging, remove `force_destroy` for non-demo.
- Secrets: use Secrets Manager for Aurora creds; remove plaintext placeholders from tfvars.example.
- DMS resilience: enable Multi-AZ, KMS, log retention, task validation/error handling/commit interval tuning; tighten table mappings off `%`.
- Network: add per-AZ NAT (or AWS-managed egress) to avoid single-AZ SPOF.

## P2 — Observability and delivery
- Provision CloudWatch alarms for task errors/latency and Snowflake alert for pipe failures; set log retention.
- Add CI to run `terraform fmt -check` and `terraform validate`; add Harness plan/approval before apply.
