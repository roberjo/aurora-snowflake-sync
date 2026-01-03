# Observability & Monitoring

## Logging Strategy
*   **DMS**: Task logs sent to CloudWatch Logs.
    *   **Log Group**: `/aws/dms/task/<task-id>`
    *   **Retention**: 30 Days.
*   **Snowflake**:
    *   **COPY_HISTORY**: Tracks file ingestion status.
    *   **TASK_HISTORY**: Tracks Merge task execution.
    *   **QUERY_HISTORY**: Tracks CDC merge performance.

## Metrics
We track the following Key Performance Indicators (KPIs):

| Metric | Source | Threshold (Warning/Critical) | Description |
| :--- | :--- | :--- | :--- |
| **DMS Task Errors** | CloudWatch | > 0 / > 5 | Replication task failures. |
| **DMS CDC Latency** | CloudWatch | > 10m / > 60m | Source-to-target latency. |
| **Sync Latency** | Custom (Snowflake) | > 2h / > 6h | Time diff between latest CDC commit timestamp in S3 and Snowflake. |
| **Snowpipe Failures** | Snowflake | > 0 | Files failing to load. |

## Alerting
Alerts are managed via CloudWatch Alarms and Snowflake Alerts, routed to PagerDuty/Slack.

### CloudWatch Alarms
1.  **DmsTaskErrorAlarm**: Triggers if replication task errors > 0.
2.  **DmsLatencyAlarm**: Triggers if CDC latency exceeds threshold.

### Snowflake Alerts (Email/Slack)
Create a Snowflake Alert to check for pipe failures:
```sql
CREATE OR REPLACE ALERT PIPE_FAILURE_ALERT
  WAREHOUSE = COMPUTE_WH
  SCHEDULE = '60 MINUTE'
  IF (EXISTS (
      SELECT * FROM TABLE(INFORMATION_SCHEMA.COPY_HISTORY(
        TABLE_NAME=>'STAGING.ORDERS_CDC',
        START_TIME=>DATEADD(hour, -1, CURRENT_TIMESTAMP())))
      WHERE STATUS = 'LOAD_FAILED'
  ))
  THEN CALL SYSTEM$SEND_EMAIL(...);
```

## Dashboards
A **Grafana** or **CloudWatch Dashboard** should be created with:
1.  DMS Task Status & Error Rate.
2.  CDC Latency (source → S3).
3.  S3 Bucket Size / Object Count (Daily Growth).
4.  Snowflake Credit Usage (Pipe + Tasks).
