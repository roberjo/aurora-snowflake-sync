-- Procedure to merge data from Staging to Final table
-- Assumes Staging table has same structure as Final but with potential duplicates

CREATE OR REPLACE PROCEDURE MERGE_DATA(TABLE_NAME VARCHAR, PK_COL VARCHAR)
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
DECLARE
  MERGE_QUERY VARCHAR;
BEGIN
  MERGE_QUERY := 'MERGE INTO ' || TABLE_NAME || ' AS T 
                  USING STAGING.' || TABLE_NAME || ' AS S 
                  ON T.' || PK_COL || ' = S.' || PK_COL || '
                  WHEN MATCHED THEN UPDATE SET T.updated_at = S.updated_at, T.data = S.data
                  WHEN NOT MATCHED THEN INSERT (id, updated_at, data) VALUES (S.id, S.updated_at, S.data)';
                  
  -- Note: The above is a simplified example. In a real dynamic proc, you'd query INFORMATION_SCHEMA to build the column list dynamically.
  
  EXECUTE IMMEDIATE :MERGE_QUERY;
  
  -- Optional: Truncate staging after successful merge
  -- EXECUTE IMMEDIATE 'TRUNCATE TABLE STAGING.' || TABLE_NAME;
  
  RETURN 'Merge Completed for ' || TABLE_NAME;
END;
$$;

-- Example Task to run the merge hourly
CREATE OR REPLACE TASK MERGE_ORDERS_TASK
  WAREHOUSE = COMPUTE_WH
  SCHEDULE = '60 MINUTE'
AS
CALL MERGE_DATA('ORDERS', 'order_id');

ALTER TASK MERGE_ORDERS_TASK RESUME;
