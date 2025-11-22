# Observability & Monitoring

## Logging Strategy
*   **Lambda**: All logs sent to CloudWatch Logs.
    *   **Log Group**: `/aws/lambda/aurora-snowflake-sync-exporter`
    *   **Format**: JSON structured logging (recommended) for easy parsing.
    *   **Retention**: 30 Days.
*   **Snowflake**:
    *   **COPY_HISTORY**: Tracks file ingestion status.
    *   **TASK_HISTORY**: Tracks Merge task execution.
    *   **QUERY_HISTORY**: Tracks export query performance (on Aurora side via `pg_stat_activity` if needed).

## Metrics
We track the following Key Performance Indicators (KPIs):

| Metric | Source | Threshold (Warning/Critical) | Description |
| :--- | :--- | :--- | :--- |
| **Lambda Errors** | CloudWatch | > 0 / > 5 | Function execution failures. |
| **Lambda Duration** | CloudWatch | > 60s / > 250s | Time taken to export data. |
| **Sync Latency** | Custom (Snowflake) | > 2h / > 6h | Time diff between `MAX(updated_at)` in Aurora vs Snowflake. |
| **Snowpipe Failures** | Snowflake | > 0 | Files failing to load. |

## Alerting
Alerts are managed via CloudWatch Alarms and Snowflake Alerts, routed to PagerDuty/Slack.

### CloudWatch Alarms
1.  **LambdaErrorAlarm**: Triggers if `Errors > 0` in 5 minutes.
2.  **LambdaTimeoutAlarm**: Triggers if `Duration > 290s` (approaching 300s limit).

### Snowflake Alerts (Email/Slack)
Create a Snowflake Alert to check for pipe failures:
```sql
CREATE OR REPLACE ALERT PIPE_FAILURE_ALERT
  WAREHOUSE = COMPUTE_WH
  SCHEDULE = '60 MINUTE'
  IF (EXISTS (
      SELECT * FROM TABLE(INFORMATION_SCHEMA.COPY_HISTORY(
        TABLE_NAME=>'STAGING.ORDERS', 
        START_TIME=>DATEADD(hour, -1, CURRENT_TIMESTAMP())))
      WHERE STATUS = 'LOAD_FAILED'
  ))
  THEN CALL SYSTEM$SEND_EMAIL(...);
```

## Dashboards
A **Grafana** or **CloudWatch Dashboard** should be created with:
1.  Lambda Invocation Count & Error Rate.
2.  Average Export Duration.
3.  S3 Bucket Size / Object Count (Daily Growth).
4.  Snowflake Credit Usage (Pipe + Tasks).
