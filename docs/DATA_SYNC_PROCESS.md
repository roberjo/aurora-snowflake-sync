# Ensuring Aurora DMS CDC stays in sync with Snowflake

Canonical flow: Aurora PostgreSQL WAL → AWS DMS CDC → S3 → Snowpipe → Snowflake Tasks (merge to FINAL). No Lambda export path is used.

## End-to-end flow
1. **Change capture (DMS)**: DMS reads WAL from Aurora and writes full-load + CDC changes to S3 in Parquet under `dms/<schema>/<table>/...`, including operation metadata.
2. **Staging (S3)**: The dedicated data lake bucket stores CDC files with lifecycle cleanup. Bucket policies restrict access to the Snowflake storage integration role and DMS role.
3. **Ingestion (Snowpipe)**: S3 object-created events fan out to Snowflake’s Snowpipe SQS. Pipes copy files from the stage into per-table STAGING CDC tables using the shared PARQUET file format.
4. **Transformation (Tasks)**: Scheduled Snowflake Tasks (or a reusable merge procedure) dedupe by primary key + commit timestamp, apply deletes/updates/inserts, and upsert into FINAL tables. Successful merges advance downstream watermarks/operational checkpoints.

## Controls that keep data correct
- **DMS checkpoints**: DMS tracks replication positions; restarts resume without skipping committed WAL entries. Task settings should enable validation and logging.
- **Table-scoped prefixes/pipes**: Each table has its own prefix and pipe to prevent cross-table pollution and simplify blast-radius when pausing a single table.
- **Schema alignment**: STAGING and FINAL tables mirror Aurora schemas; merge logic centralizes column mapping and delete handling.
- **Secure storage**: Bucket ownership enforcement, SSE-KMS, TLS-only bucket policy, and least-privilege roles prevent accidental exposure or tampering.

## Validation and reconciliation
- **COPY_HISTORY vs DMS**: Compare Snowpipe `COPY_HISTORY` row counts to DMS task metrics for recent intervals; alert on drift.
- **Merge effects**: Review `TASK_HISTORY` affected rows and error rates; failed tasks should block watermark advancement.
- **Freshness**: Monitor `MAX(commit_timestamp)` (or equivalent) between Aurora and FINAL; alert if the lag exceeds the SLA (e.g., >2 hours).
- **Failure handling**: Investigate any `LOAD_FAILED` files, fix schema/data issues, and trigger Snowpipe reprocess before restarting tasks.

## Operational tips
- Pausing a table: disable its Pipe and Task; DMS continues writing files, so resume ingestion by re-enabling both.
- Reloading a table: run a DMS table reload, truncate the STAGING table, and allow Snowpipe to re-ingest; the merge task will reconcile.
- Schema changes: apply DDL to STAGING and FINAL before DMS emits the new columns to avoid copy failures.
