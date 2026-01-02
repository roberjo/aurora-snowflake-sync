# Handling Tables Without updated_at Timestamps

## Problem Statement

The current Aurora-to-Snowflake sync implementation relies on an `updated_at` timestamp column to track incremental changes. However, many legacy or third-party database tables don't have such columns.

**Question:** How do we incrementally sync tables that lack timestamp-based watermark columns?

---

## Solution Strategies

### Strategy 1: Use Auto-Incrementing Primary Keys

**Best for:** Tables with sequential integer primary keys (e.g., `id`, `order_id`)

#### How It Works
Instead of tracking timestamps, track the maximum primary key value that's been exported.

#### Implementation

**Configuration:**
```json
{
  "tables": [
    {
      "table_name": "legacy_orders",
      "watermark_type": "integer",
      "watermark_col": "order_id",
      "primary_key": "order_id"
    }
  ]
}
```

**Query Logic:**
```sql
-- Instead of: WHERE updated_at > '2025-12-24 12:00:00'
-- Use: WHERE order_id > 12345

SELECT * FROM legacy_orders WHERE order_id > 12345
```

**Watermark Tracking:**
```python
# Snowflake query
SELECT MAX(order_id) FROM legacy_orders
# Returns: 12345

# Or S3 state file
{
  "table_name": "legacy_orders",
  "last_watermark": 12345,
  "watermark_type": "integer"
}
```

#### Pros
✅ Simple and efficient  
✅ Works with existing primary keys  
✅ No schema changes required  
✅ Deterministic ordering

#### Cons
❌ Only captures new records (INSERTs), not UPDATEs  
❌ Requires sequential IDs (gaps are OK, but must be monotonically increasing)  
❌ Doesn't work with UUIDs or non-sequential keys

---

### Strategy 2: Add Triggers to Create Audit Columns

**Best for:** Tables where you have schema modification permissions

#### How It Works
Add `updated_at` and `created_at` columns with database triggers to automatically populate them.

#### Implementation

**Step 1: Add Columns**
```sql
ALTER TABLE legacy_orders 
ADD COLUMN created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
ADD COLUMN updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP;
```

**Step 2: Create Update Trigger**
```sql
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_legacy_orders_updated_at
    BEFORE UPDATE ON legacy_orders
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();
```

**Step 3: Backfill Existing Data**
```sql
-- Set initial values for existing records
UPDATE legacy_orders 
SET created_at = CURRENT_TIMESTAMP,
    updated_at = CURRENT_TIMESTAMP
WHERE created_at IS NULL;
```

**Step 4: Use Standard Timestamp-Based Sync**
```python
# Now you can use the standard approach
config = {
    "table_name": "legacy_orders",
    "watermark_col": "updated_at"
}
```

#### Pros
✅ Captures both INSERTs and UPDATEs  
✅ Standard approach works  
✅ Automatic - no application changes needed  
✅ Provides audit trail

#### Cons
❌ Requires schema modification  
❌ May not be allowed in production  
❌ Backfilled data has artificial timestamps  
❌ Trigger overhead on writes

---

### Strategy 3: Use PostgreSQL System Columns (xmin)

**Best for:** PostgreSQL/Aurora tables where schema changes aren't allowed

#### How It Works
PostgreSQL has hidden system columns that track transaction IDs. `xmin` indicates the transaction that inserted/updated a row.

#### Implementation

**Query with xmin:**
```sql
-- Export rows modified after transaction ID 1000000
SELECT *, xmin::text::bigint as transaction_id 
FROM legacy_orders 
WHERE xmin::text::bigint > 1000000
```

**Watermark Tracking:**
```python
# Get current transaction ID from Aurora
SELECT txid_current() FROM legacy_orders LIMIT 1
# Returns: 1000523

# Store in state file
{
  "table_name": "legacy_orders",
  "last_watermark": 1000523,
  "watermark_type": "xmin"
}
```

**Lambda Implementation:**
```python
def get_current_xmin(db_params):
    """Get the current transaction ID from Aurora"""
    conn = psycopg2.connect(**db_params)
    cur = conn.cursor()
    cur.execute("SELECT txid_current()")
    xmin = cur.fetchone()[0]
    cur.close()
    conn.close()
    return xmin

def export_with_xmin(db_params, s3_bucket, table_name, last_xmin):
    """Export using xmin-based watermark"""
    query = f"""
    SELECT *, xmin::text::bigint as transaction_id 
    FROM {table_name} 
    WHERE xmin::text::bigint > {last_xmin}
    """
    # ... rest of export logic
```

#### Pros
✅ No schema changes required  
✅ Captures both INSERTs and UPDATEs  
✅ Native PostgreSQL feature  
✅ Very efficient

#### Cons
❌ PostgreSQL-specific (won't work on MySQL, SQL Server)  
❌ Transaction IDs can wrap around (after ~4 billion transactions)  
❌ VACUUM can affect xmin values  
❌ Less intuitive than timestamps  
❌ Deleted rows aren't captured

---

### Strategy 4: Full Table Snapshot with Change Detection

**Best for:** Small tables or tables that change infrequently

#### How It Works
Export the entire table every time, then use Snowflake to detect changes via MERGE.

#### Implementation

**Lambda Logic:**
```python
def export_full_snapshot(db_params, s3_bucket, table_name):
    """Export entire table - no watermark needed"""
    query = f"SELECT * FROM {table_name}"
    
    # Export to timestamped location
    s3_prefix = f"{table_name}/snapshots/{datetime.now().strftime('%Y%m%d_%H%M%S')}"
    
    export_sql = f"""
    SELECT * from aws_s3.query_export_to_s3(
        '{query}', 
        aws_commons.create_s3_uri('{s3_bucket}', '{s3_prefix}', 'us-east-1')
    );
    """
    # Execute export
```

**Snowflake MERGE Logic:**
```sql
-- Detect changes by comparing with existing table
MERGE INTO target_table t
USING (
    SELECT * FROM @stage/snapshots/latest/
) s
ON t.id = s.id
WHEN MATCHED AND t <> s THEN UPDATE SET *
WHEN NOT MATCHED THEN INSERT *;
```

#### Pros
✅ No watermark needed  
✅ Captures all changes (INSERT, UPDATE, DELETE)  
✅ Simple logic  
✅ Works with any table structure

#### Cons
❌ Inefficient for large tables  
❌ High data transfer costs  
❌ Longer execution time  
❌ More S3 storage required

---

### Strategy 5: Use Database Change Data Capture (CDC)

**Best for:** High-volume tables requiring real-time sync

#### How It Works
Use Aurora's native CDC capabilities or AWS DMS to capture database changes.

#### Implementation Options

**Option A: AWS DMS (Database Migration Service)**
```yaml
# DMS Task Configuration
source: Aurora PostgreSQL
target: S3 (Parquet)
mode: CDC (Change Data Capture)
tables:
  - legacy_orders
  - legacy_customers
```

**Option B: PostgreSQL Logical Replication**
```sql
-- Enable logical replication
ALTER TABLE legacy_orders REPLICA IDENTITY FULL;

-- Create publication
CREATE PUBLICATION aurora_sync FOR TABLE legacy_orders;
```

**Option C: Debezium + Kafka**
```yaml
# Debezium connector
connector.class: io.debezium.connector.postgresql.PostgresConnector
database.hostname: aurora-endpoint
database.dbname: mydb
table.include.list: public.legacy_orders
```

#### Pros
✅ Real-time or near-real-time sync  
✅ Captures all operations (INSERT, UPDATE, DELETE)  
✅ No schema changes required  
✅ Minimal impact on source database  
✅ Industry-standard approach

#### Cons
❌ More complex architecture  
❌ Additional AWS services/costs  
❌ Requires operational expertise  
❌ Overkill for batch sync scenarios

---

### Strategy 6: Composite Watermark (Timestamp + ID)

**Best for:** Tables with both timestamp and ID columns, but timestamps aren't unique

#### How It Works
Use a combination of timestamp and ID to ensure no records are missed.

#### Implementation

**Configuration:**
```json
{
  "table_name": "orders",
  "watermark_type": "composite",
  "watermark_cols": ["updated_at", "order_id"],
  "primary_key": "order_id"
}
```

**Query Logic:**
```sql
-- Handle case where multiple records have same timestamp
SELECT * FROM orders 
WHERE (updated_at > '2025-12-24 12:00:00')
   OR (updated_at = '2025-12-24 12:00:00' AND order_id > 12345)
ORDER BY updated_at, order_id
```

**Watermark State:**
```json
{
  "table_name": "orders",
  "last_watermark": {
    "updated_at": "2025-12-24 12:00:00",
    "order_id": 12345
  }
}
```

#### Pros
✅ Handles non-unique timestamps  
✅ No data loss risk  
✅ Deterministic ordering

#### Cons
❌ More complex query logic  
❌ Slightly slower queries  
❌ More complex state management

---

## Comparison Matrix

| Strategy | Schema Changes | Captures Updates | Captures Deletes | Complexity | Performance | Best Use Case |
|----------|---------------|------------------|------------------|------------|-------------|---------------|
| **Auto-Incrementing ID** | None | ❌ No | ❌ No | Low | Excellent | Append-only tables |
| **Add Triggers** | Required | ✅ Yes | ❌ No | Medium | Good | Tables you control |
| **PostgreSQL xmin** | None | ✅ Yes | ❌ No | Medium | Excellent | PostgreSQL only |
| **Full Snapshot** | None | ✅ Yes | ✅ Yes | Low | Poor | Small tables |
| **CDC (DMS/Debezium)** | None | ✅ Yes | ✅ Yes | High | Excellent | Real-time needs |
| **Composite Watermark** | None | ✅ Yes | ❌ No | Medium | Good | Non-unique timestamps |

---

## Recommended Approach by Table Type

### Append-Only Tables (e.g., logs, events)
**Use:** Auto-incrementing ID watermark
```json
{"watermark_type": "integer", "watermark_col": "id"}
```

### Frequently Updated Tables (e.g., orders, inventory)
**Use:** Add `updated_at` trigger (if allowed) or xmin
```json
{"watermark_type": "timestamp", "watermark_col": "updated_at"}
```

### Small Reference Tables (e.g., countries, categories)
**Use:** Full snapshot
```json
{"watermark_type": "full_snapshot"}
```

### High-Volume Transactional Tables
**Use:** AWS DMS with CDC
```yaml
mode: cdc
replication_instance: dms.r5.large
```

---

## Implementation Example: Multi-Strategy Lambda

Here's how to modify the Lambda to support multiple watermark strategies:

```python
def get_watermark_query(table_config, watermark_value):
    """
    Generate the appropriate WHERE clause based on watermark type.
    """
    watermark_type = table_config.get('watermark_type', 'timestamp')
    
    if watermark_type == 'timestamp':
        col = table_config['watermark_col']
        return f"WHERE {col} > '{watermark_value}'"
    
    elif watermark_type == 'integer':
        col = table_config['watermark_col']
        return f"WHERE {col} > {watermark_value}"
    
    elif watermark_type == 'xmin':
        return f"WHERE xmin::text::bigint > {watermark_value}"
    
    elif watermark_type == 'composite':
        ts_col, id_col = table_config['watermark_cols']
        ts_val, id_val = watermark_value['timestamp'], watermark_value['id']
        return f"""WHERE ({ts_col} > '{ts_val}') 
                   OR ({ts_col} = '{ts_val}' AND {id_col} > {id_val})"""
    
    elif watermark_type == 'full_snapshot':
        return ""  # No WHERE clause - export everything
    
    else:
        raise ValueError(f"Unknown watermark type: {watermark_type}")

# Usage in export function
def export_from_aurora(db_params, s3_bucket, table_config, watermark):
    table = table_config['table_name']
    where_clause = get_watermark_query(table_config, watermark)
    
    query = f"SELECT * FROM {table} {where_clause}"
    # ... rest of export logic
```

---

## Migration Path for Legacy Tables

### Step 1: Assess Your Tables
```sql
-- Check which tables have updated_at
SELECT 
    table_name,
    column_name
FROM information_schema.columns
WHERE table_schema = 'public'
  AND column_name IN ('updated_at', 'modified_at', 'last_modified');

-- Check for auto-incrementing IDs
SELECT 
    table_name,
    column_name
FROM information_schema.columns
WHERE table_schema = 'public'
  AND column_name LIKE '%id'
  AND data_type IN ('integer', 'bigint');
```

### Step 2: Choose Strategy Per Table
Create a decision matrix for each table based on:
- Size (rows)
- Update frequency
- Schema modification permissions
- Business criticality

### Step 3: Implement Incrementally
1. Start with tables that have `updated_at` (easiest)
2. Add triggers to tables you control
3. Use xmin for legacy tables
4. Use full snapshot for small reference tables
5. Consider DMS/CDC for high-volume tables

---

## Monitoring & Validation

### Detect Missing Records
```sql
-- Compare counts between Aurora and Snowflake
SELECT 
    'Aurora' as source, COUNT(*) as record_count 
FROM aurora.orders
UNION ALL
SELECT 
    'Snowflake' as source, COUNT(*) as record_count 
FROM snowflake.orders;
```

### Track Watermark Progression
```python
# Log watermark changes
{
    "table": "orders",
    "old_watermark": 12345,
    "new_watermark": 12567,
    "records_exported": 222,
    "execution_time": "2.3s"
}
```

---

## Conclusion

**For tables WITHOUT `updated_at`:**

1. **First choice:** Use auto-incrementing ID if available
2. **Second choice:** Add `updated_at` trigger if schema changes allowed
3. **Third choice:** Use PostgreSQL `xmin` for no-schema-change solution
4. **Last resort:** Full snapshot for small tables or CDC for large tables

The key is to **match the strategy to your specific constraints** (schema permissions, table size, update patterns).
