# Operational Runbook

## System Overview
*   **Service Name**: Aurora-Snowflake Sync
*   **Criticality**: Tier 2 (Analytical Data)
*   **On-Call Group**: Data Engineering

## Common Issues & Troubleshooting

### 1. Sync Lagging / Data Missing
**Symptoms**: Dashboard shows data is stale > 2 hours.
**Investigation**:
1.  **Check Lambda Logs**: Go to CloudWatch Log Group `/aws/lambda/aurora-snowflake-sync-exporter`.
    *   Look for "Export failed" or timeouts.
    *   *Fix*: If timeout, increase Lambda timeout in Terraform. If DB connection error, check Aurora status.
2.  **Check S3**: Verify files are landing in the bucket.
    *   If no files: Issue is upstream (Lambda/Aurora).
    *   If files exist: Issue is downstream (Snowpipe).
3.  **Check Snowpipe**:
    ```sql
    SELECT * FROM TABLE(INFORMATION_SCHEMA.COPY_HISTORY(TABLE_NAME=>'STAGING.ORDERS', START_TIME=> DATEADD(hours, -4, CURRENT_TIMESTAMP())));
    ```
    *   Look for `LOAD_FAILED` status.
    *   *Fix*: Check file format issues or schema mismatches.

### 2. Schema Mismatch
**Symptoms**: Snowpipe fails with "Number of columns in file does not match table".
**Cause**: Column added to Aurora but not Snowflake.
**Resolution**:
1.  Pause the Snowpipe (optional, but recommended if errors are flooding).
2.  `ALTER TABLE FINAL_TABLE ADD COLUMN ...`
3.  `ALTER TABLE STAGING_TABLE ADD COLUMN ...`
4.  Update the Merge Task logic if necessary.
5.  Snowpipe will retry failed files automatically (or manually trigger reload).

### 3. Lambda Timeout
**Symptoms**: "Task timed out after 300.00 seconds".
**Cause**: Large data volume in a single batch.
**Resolution**:
*   **Immediate**: Manually run the Lambda for a smaller time range (if logic supports it) or simply re-run to catch up.
*   **Long-term**: Increase Lambda timeout or frequency of sync (e.g., from Daily to Hourly).

## Disaster Recovery

### Re-syncing a Table
If data is corrupted or needs a full reload:
1.  **Truncate Snowflake Tables**:
    ```sql
    TRUNCATE TABLE STAGING.MY_TABLE;
    TRUNCATE TABLE PUBLIC.MY_TABLE;
    ```
2.  **Reset Watermark**:
    *   The Lambda queries `MAX(updated_at)`. If table is empty, it defaults to `1970-01-01`.
    *   The next run will trigger a FULL export.
    *   *Warning*: This may take a long time for large tables. Monitor Aurora CPU.

### Vault Unavailability
If Hashicorp Vault is down:
*   The Lambda will fail to get credentials.
*   **Workaround**: Temporarily inject credentials via AWS Lambda Environment Variables (Encrypted) until Vault is restored. **Revert immediately after.**

## Maintenance
*   **Vacuum**: Ensure Aurora tables are vacuumed regularly to prevent bloat affecting export performance.
*   **S3 Cleanup**: Verify Lifecycle policies are deleting old staging files.
