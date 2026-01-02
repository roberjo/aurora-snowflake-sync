# Ensuring Aurora exports stay in sync with Snowflake

This guide explains how the pipeline ensures the right records are exported from Aurora and applied to Snowflake so tables remain current.

## End-to-end flow
1. **Load table metadata** from AWS Systems Manager Parameter Store (`/aurora-snowflake-sync/tables`) as JSON. Each entry defines:
   * `table_name` (e.g., `public.orders`)
   * `watermark_col` (e.g., `updated_at`)
   * optional `primary_keys` for merge logic and `full_refresh` flag for one-off reloads.
2. **Resolve the watermark** by querying Snowflake for the latest processed `watermark_col` value per table in the FINAL table. If a table is empty, default to `1970-01-01` to trigger a full backfill.
3. **Build the export query** in Lambda using the watermark and table metadata. The query selects rows where `watermark_col > watermark_value` and writes them to S3 via `aws_s3.query_export_to_s3` using a table-specific prefix (`s3://<bucket>/<table>/YYYY/MM/DD/HH/run-<uuid>.csv`).
4. **Verify the export call** by checking Lambda logs for the generated query, returned row count, and S3 object key. Unexpectedly low row counts should trigger investigation before proceeding.
5. **Auto-ingest to Snowflake** through per-table Snowpipe objects that watch their prefix. Files are loaded into the matching STAGING table.
6. **Merge to FINAL** using a scheduled Snowflake Task that performs `MERGE` on `primary_keys`, updating changed rows and inserting new ones. Deleted rows can be handled via a `is_deleted` soft-delete flag.

## Controls that ensure the right records move
* **Watermark discipline**: The Lambda reads the watermark from Snowflake right before exporting, so retries or failed runs don’t skip data. Watermarks advance only after the merge completes successfully.
* **Table-scoped prefixes and pipes**: Each table writes to a dedicated S3 prefix and Snowpipe, preventing cross-table pollution and making it obvious which files belong to which target.
* **Deterministic export filters**: The Lambda assembles the `WHERE watermark_col > :watermark` predicate directly from metadata; no hardcoded table lists or timestamps mean updates are always relative to the latest ingested row.
* **Schema alignment**: Staging/Final tables should mirror Aurora schemas; the merge task is the single point that enforces column mapping and deduplication.

## Validation and reconciliation
* **Row count deltas**: After each run, compare the Lambda-reported export row count to Snowflake `COPY_HISTORY` and `TASK_HISTORY` affected rows. Significant mismatches should page the on-call.
* **Watermark drift check**: A monitoring query should compute `MAX(updated_at)` in Aurora vs. Snowflake FINAL; alert if the difference exceeds the SLA (e.g., >2 hours).
* **Sample-based verification**: Periodically sample a handful of recent Aurora rows and confirm they exist in Snowflake FINAL with identical primary keys and timestamps.
* **Dead-letter review**: Investigate any Snowpipe `LOAD_FAILED` rows or Lambda errors before clearing the watermark to avoid data loss.

## Operational tips
* To force a full reload of a table, set its Parameter Store config to `{ "full_refresh": true }`; the Lambda will skip the watermark filter for the next run and then revert to incremental mode.
* If schema changes add new columns, deploy the DDL to Snowflake STAGING and FINAL before the export to avoid ingestion failures.
