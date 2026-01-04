# Frequently Asked Questions

### Q: Why use AWS DMS?
A: DMS provides reliable CDC from Aurora (including deletes), avoids heavy table scans, and maintains source-of-truth offsets based on WAL positions. The continuous instance cost is offset by improved correctness and lower operational risk.

### Q: Do we still use a Lambda watermark export path?
A: No. The canonical ingestion is Aurora → DMS CDC → S3 → Snowpipe → Tasks. All metadata and scheduling live in DMS/Snowflake; there is no Lambda-based export or Parameter Store watermark flow.

### Q: How do we handle schema changes?
A: Schema changes are **not** automatic. You must apply DDL to Snowflake (Staging and Final tables) manually or via a migration tool (like Flyway/Schemachange) *before* the data arrives. If columns are missing in Snowflake, Snowpipe may fail or ignore the new data depending on `ON_ERROR` settings.

### Q: What happens if the DMS task fails?
A: DMS tracks replication checkpoints. After remediation, you can restart the task or reload specific tables. Latency increases, but data consistency is preserved as long as WAL retention covers the outage.

### Q: Can we do real-time sync?
A: This architecture is near-real-time CDC. For lower latency or streaming transforms, consider Debezium/Kafka or Snowflake Streams.

### Q: How do I backfill historical data?
A: Use DMS full-load + CDC for the table, or trigger a DMS "Reload table" and let Snowpipe ingest the resulting files.
