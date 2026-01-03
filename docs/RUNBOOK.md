# Operational Runbook

## System Overview
*   **Service Name**: Aurora-Snowflake Sync
*   **Criticality**: Tier 2 (Analytical Data)
*   **On-Call Group**: Data Engineering

## Common Issues & Troubleshooting

### 1. Sync Lagging / Data Missing
**Symptoms**: Dashboard shows data is stale > 2 hours.
**Investigation**:
1.  **Check DMS Task Status**: In the DMS console, confirm the replication task is `Running`.
    *   Look for task errors or high latency in CloudWatch metrics.
    *   *Fix*: Resolve source connectivity, then restart the task.
2.  **Check S3**: Verify CDC files are landing under `dms/<schema>/<table>/`.
    *   If no files: Issue is upstream (DMS/Aurora).
    *   If files exist: Issue is downstream (Snowpipe).
3.  **Check Snowpipe**:
    ```sql
    SELECT * FROM TABLE(INFORMATION_SCHEMA.COPY_HISTORY(TABLE_NAME=>'STAGING.ORDERS_CDC', START_TIME=> DATEADD(hours, -4, CURRENT_TIMESTAMP())));
    ```
    *   Look for `LOAD_FAILED` status.
    *   *Fix*: Check file format issues or schema mismatches.

### 2. Schema Mismatch
**Symptoms**: Snowpipe fails with "Number of columns in file does not match table".
**Cause**: Column added to Aurora but not Snowflake.
**Resolution**:
1.  Pause the Snowpipe (optional, but recommended if errors are flooding).
2.  `ALTER TABLE FINAL_TABLE ADD COLUMN ...`
3.  `ALTER TABLE STAGING_TABLE_CDC ADD COLUMN ...`
4.  Update the Merge Task logic if necessary (CDC merge uses the staging table).
5.  Snowpipe will retry failed files automatically (or manually trigger reload).

### 3. DMS Task Stalled
**Symptoms**: DMS task is running but no new files arrive in S3.
**Cause**: Replication lag, WAL retention too low, or task errors.
**Resolution**:
*   **Immediate**: Check DMS task logs and CloudWatch latency metrics, then restart the task.
*   **Long-term**: Increase WAL retention, scale the replication instance, or limit task scope.

## Disaster Recovery

### Re-syncing a Table
If data is corrupted or needs a full reload:
1.  **Truncate Snowflake Tables**:
    ```sql
    TRUNCATE TABLE STAGING.MY_TABLE_CDC;
    TRUNCATE TABLE PUBLIC.MY_TABLE;
    ```
2.  **Reload via DMS**:
    *   Use DMS "Reload table" or recreate the task with a fresh full load.
    *   Monitor task progress and Snowpipe ingestion.

## Maintenance
*   **Vacuum**: Ensure Aurora tables are vacuumed regularly to prevent bloat affecting export performance.
*   **S3 Cleanup**: Verify Lifecycle policies are deleting old staging files.
