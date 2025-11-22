# Frequently Asked Questions

### Q: Why not use AWS DMS?
A: AWS DMS is a powerful tool but incurs continuous instance costs. For our batch requirements (hourly/daily), a serverless approach (Lambda + Aurora Export) is significantly more cost-effective and easier to maintain for simple replication needs.

### Q: How do we handle schema changes?
A: Schema changes are **not** automatic. You must apply DDL to Snowflake (Staging and Final tables) manually or via a migration tool (like Flyway/Schemachange) *before* the data arrives. If columns are missing in Snowflake, Snowpipe may fail or ignore the new data depending on `ON_ERROR` settings.

### Q: What happens if the Lambda fails?
A: The Lambda is stateless. It queries the *current* watermark from Snowflake. If a run fails, the next scheduled run will simply pick up from the last successful watermark. No data is lost, but latency increases.

### Q: Can we do real-time sync?
A: This architecture is optimized for batch. For real-time, we would need to switch to AWS DMS or a Kafka-based CDC approach (Debezium), which increases cost and complexity.

### Q: How do I backfill historical data?
A: To backfill, you can manually trigger the Lambda with a specific `start_time` (if logic permits) or use a one-time `COPY` command in Aurora to export the full table to S3, then let Snowpipe ingest it.
