-- Procedure to merge CDC data into final tables
-- Assumes CDC tables include operation and commit timestamp columns from DMS.

CREATE OR REPLACE PROCEDURE MERGE_CDC(
  TARGET_TABLE VARCHAR,
  CDC_TABLE VARCHAR,
  PK_COL VARCHAR,
  COMMIT_TS_COL VARCHAR,
  OP_COL VARCHAR
)
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
DECLARE
  MERGE_QUERY VARCHAR;
BEGIN
  MERGE_QUERY := 'MERGE INTO ' || TARGET_TABLE || ' AS T ' ||
                 'USING (SELECT * FROM ' || CDC_TABLE ||
                 ' QUALIFY ROW_NUMBER() OVER (PARTITION BY ' || PK_COL ||
                 ' ORDER BY ' || COMMIT_TS_COL || ' DESC) = 1) AS S ' ||
                 'ON T.' || PK_COL || ' = S.' || PK_COL || ' ' ||
                 'WHEN MATCHED AND S.' || OP_COL || ' = ''D'' THEN DELETE ' ||
                 'WHEN MATCHED AND S.' || OP_COL || ' IN (''U'',''I'') THEN UPDATE SET T.updated_at = S.updated_at, T.data = S.data ' ||
                 'WHEN NOT MATCHED AND S.' || OP_COL || ' IN (''I'',''U'') THEN INSERT (id, updated_at, data) VALUES (S.id, S.updated_at, S.data)';

  -- Note: This is a simplified example; adjust column lists to match your schema.
  EXECUTE IMMEDIATE :MERGE_QUERY;
  RETURN 'Merge Completed for ' || TARGET_TABLE;
END;
$$;

-- Example Task to run the merge hourly
CREATE OR REPLACE TASK MERGE_ORDERS_TASK
  WAREHOUSE = COMPUTE_WH
  SCHEDULE = '60 MINUTE'
AS
CALL MERGE_CDC('ORDERS', 'STAGING.ORDERS_CDC', 'order_id', 'commit_timestamp', 'op');

ALTER TASK MERGE_ORDERS_TASK RESUME;
