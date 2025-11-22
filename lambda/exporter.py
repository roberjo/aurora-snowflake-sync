import os
import json
import boto3
import psycopg2
import snowflake.connector
import hvac
from datetime import datetime

def get_secrets():
    """
    Retrieve secrets from Hashicorp Vault.
    Assumes Vault is accessible and authenticated via IAM or Token.
    """
    vault_addr = os.environ.get('VAULT_ADDR')
    vault_token = os.environ.get('VAULT_TOKEN') # Or use AWS Auth
    
    client = hvac.Client(url=vault_addr, token=vault_token)
    
    # Example path
    secrets = client.secrets.kv.v2.read_secret_version(path='aurora-snowflake-sync')
    return secrets['data']['data']

def get_snowflake_watermark(conn_params, table_name, watermark_col):
    """
    Query Snowflake to find the maximum watermark value for the table.
    """
    ctx = snowflake.connector.connect(
        user=conn_params['user'],
        password=conn_params['password'],
        account=conn_params['account'],
        warehouse=conn_params['warehouse'],
        database=conn_params['database'],
        schema=conn_params['schema']
    )
    cs = ctx.cursor()
    try:
        cs.execute(f"SELECT MAX({watermark_col}) FROM {table_name}")
        row = cs.fetchone()
        return row[0] if row and row[0] else '1970-01-01 00:00:00'
    finally:
        cs.close()
        ctx.close()

def export_from_aurora(db_params, s3_bucket, table_config, watermark):
    """
    Execute aws_s3.query_export_to_s3 on Aurora.
    """
    conn = psycopg2.connect(**db_params)
    cur = conn.cursor()
    
    table = table_config['table_name']
    col = table_config['watermark_col']
    s3_prefix = f"{table}/{datetime.now().strftime('%Y/%m/%d/%H')}"
    
    query = f"SELECT * FROM {table} WHERE {col} > '{watermark}'"
    
    # Aurora aws_s3 extension query
    export_sql = f"""
    SELECT * from aws_s3.query_export_to_s3(
        '{query}', 
        aws_commons.create_s3_uri('{s3_bucket}', '{s3_prefix}', 'us-east-1')
    );
    """
    
    print(f"Executing export for {table} with watermark > {watermark}")
    try:
        cur.execute(export_sql)
        conn.commit()
        print(f"Export successful to s3://{s3_bucket}/{s3_prefix}")
    except Exception as e:
        conn.rollback()
        print(f"Export failed: {e}")
        raise
    finally:
        cur.close()
        conn.close()

def lambda_handler(event, context):
    print("Starting sync process...")
    
    # Load Config
    # In a real app, this might come from S3 or Env Vars
    config = {
        "tables": [
            {"table_name": "orders", "watermark_col": "updated_at"},
            {"table_name": "customers", "watermark_col": "updated_at"}
        ]
    }
    
    s3_bucket = os.environ['S3_BUCKET']
    
    try:
        secrets = get_secrets()
        
        aurora_params = {
            'host': secrets['aurora_host'],
            'database': secrets['aurora_db'],
            'user': secrets['aurora_user'],
            'password': secrets['aurora_password']
        }
        
        snowflake_params = {
            'user': secrets['snowflake_user'],
            'password': secrets['snowflake_password'],
            'account': secrets['snowflake_account'],
            'warehouse': 'COMPUTE_WH',
            'database': 'SYNC_DB',
            'schema': 'STAGING'
        }
        
        for table_cfg in config['tables']:
            watermark = get_snowflake_watermark(
                snowflake_params, 
                table_cfg['table_name'], 
                table_cfg['watermark_col']
            )
            
            export_from_aurora(aurora_params, s3_bucket, table_cfg, watermark)
            
        return {
            'statusCode': 200,
            'body': json.dumps('Sync completed successfully')
        }
        
    except Exception as e:
        print(f"Error: {e}")
        return {
            'statusCode': 500,
            'body': json.dumps(f"Error: {str(e)}")
        }
