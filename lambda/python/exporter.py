import os
import json
import boto3
import psycopg2
import snowflake.connector
import hvac
from datetime import datetime

"""
Exporter Lambda Function
------------------------
This script is the core logic for the Aurora to Snowflake synchronization
process. It is designed to run as an AWS Lambda function triggered on a
schedule (e.g., via EventBridge).

Purpose:
    To incrementally export data from an Amazon Aurora PostgreSQL database to
    an S3 bucket, based on a watermark (timestamp) retrieved from the
    destination Snowflake data warehouse.
    This ensures only new or updated records are processed.

Key Components:
    - Hashicorp Vault: Used for secure retrieval of database credentials.
    - Snowflake Connector: Connects to Snowflake to query the current state
      (watermark).
    - Psycopg2: Connects to Aurora PostgreSQL to execute the export command.
    - AWS S3 Extension for PostgreSQL: Utilized within Aurora to offload data
      directly to S3.

Logic Flow:
    1. Retrieve credentials from Vault.
    2. For each configured table:
        a. Query Snowflake for the max 'updated_at' timestamp (watermark).
        b. Connect to Aurora.
        c. Execute a query to export records newer than the watermark to S3.
"""


def get_secrets():
    """
    Retrieve secrets from Hashicorp Vault.

    Why this is needed:
        Hardcoding credentials is a security risk. Vault provides a secure,
        centralized way to manage secrets. This function fetches the necessary
        database credentials (Aurora and Snowflake) at runtime.

    Returns:
        dict: A dictionary containing the secrets (host, user, password, etc.).
    """
    # Retrieve Vault address and token from environment variables
    # These are set in the Lambda configuration
    vault_addr = os.environ.get("VAULT_ADDR")
    vault_token = os.environ.get("VAULT_TOKEN")

    # Initialize the Vault client
    client = hvac.Client(url=vault_addr)

    if vault_token:
        client.token = vault_token
    else:
        role = os.environ.get("VAULT_ROLE")
        session = boto3.Session()
        creds = session.get_credentials().get_frozen_credentials()
        login = client.auth.aws.iam_login(
            access_key=creds.access_key,
            secret_key=creds.secret_key,
            session_token=creds.token,
            role=role,
        )
        client.token = login["auth"]["client_token"]

    secrets_path = os.environ.get("VAULT_SECRET_PATH", "aurora-snowflake-sync")
    secrets = client.secrets.kv.v2.read_secret_version(path=secrets_path)

    # Return the actual data dictionary from the response
    return secrets["data"]["data"]


def load_table_config():
    """
    Load table configuration from SSM Parameter Store or environment.
    """
    param_name = os.environ.get("TABLE_CONFIG_PARAM")
    if param_name:
        ssm = boto3.client("ssm")
        param = ssm.get_parameter(Name=param_name, WithDecryption=True)
        return json.loads(param["Parameter"]["Value"])

    inline_config = os.environ.get("TABLE_CONFIG_JSON")
    if inline_config:
        return json.loads(inline_config)

    return {
        "tables": [
            {"table_name": "orders", "watermark_col": "updated_at"},
            {"table_name": "customers", "watermark_col": "updated_at"},
        ]
    }


def get_snowflake_watermark(conn_params, table_name, watermark_col):
    """
    Query Snowflake to find the maximum watermark value for the table.

    Why this is needed:
        To implement incremental loading, we need to know the last record
        processed in the destination (Snowflake). This prevents re-processing
        old data.

    Args:
        conn_params (dict): Connection parameters for Snowflake.
        table_name (str): The name of the table to query.
        watermark_col (str): The column name representing the timestamp/
            watermark.

    Returns:
        str: The maximum timestamp found, or a default epoch if the table is
            empty.
    """
    # Establish connection to Snowflake
    ctx = snowflake.connector.connect(
        user=conn_params["user"],
        password=conn_params["password"],
        account=conn_params["account"],
        warehouse=conn_params["warehouse"],
        database=conn_params["database"],
        schema=conn_params["schema"],
    )
    cs = ctx.cursor()
    try:
        # Execute query to get the max timestamp
        # This determines the starting point for the next batch of data from
        # Aurora.
        cs.execute(f"SELECT MAX({watermark_col}) FROM {table_name}")
        row = cs.fetchone()

        # Return the result or a default date if the table is empty
        # (initial load).
        return row[0] if row and row[0] else "1970-01-01 00:00:00"
    finally:
        # Ensure resources are closed properly
        cs.close()
        ctx.close()


def export_from_aurora(db_params, s3_bucket, table_config, watermark):
    """
    Execute aws_s3.query_export_to_s3 on Aurora.

    Why this is needed:
        This function performs the actual data extraction. Instead of pulling
        data into the Lambda memory (which is slow and memory-constrained), it
        instructs Aurora to write the query results directly to S3 using the
        'aws_s3' extension.

    Args:
        db_params (dict): Connection parameters for Aurora PostgreSQL.
        s3_bucket (str): Target S3 bucket name.
        table_config (dict): Configuration for the specific table (name,
            columns).
        watermark (str): The timestamp to filter data against.
    """
    conn = psycopg2.connect(**db_params)
    cur = conn.cursor()

    table = table_config["table_name"]
    col = table_config["watermark_col"]
    # Define S3 prefix with date partitioning for better organization/perf.
    s3_prefix = f"{table}/{datetime.now().strftime('%Y/%m/%d/%H')}"

    # Construct the query to select new data
    query = f"SELECT * FROM {table} " f"WHERE {col} > '{watermark}'"

    # Aurora aws_s3 extension query
    # This function call executes entirely on the database server
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
    """
    Main Lambda Entry Point.

    Function:
        Orchestrates the entire synchronization process.

    Logic:
        1. Loads configuration (tables to sync).
        2. Retrieves secrets.
        3. Iterates through each table:
            - Gets the high-water mark from Snowflake.
            - Triggers the export from Aurora to S3.

    Args:
        event: Lambda event data (unused in this scheduled trigger).
        context: Lambda context data.
    """
    print("Starting sync process...")

    config = load_table_config()

    s3_bucket = os.environ["S3_BUCKET"]

    try:
        # 1. Get Secrets
        secrets = get_secrets()

        # Prepare Aurora connection parameters
        aurora_params = {
            "host": secrets["aurora_host"],
            "database": secrets["aurora_db"],
            "user": secrets["aurora_user"],
            "password": secrets["aurora_password"],
        }

        # Prepare Snowflake connection parameters
        snowflake_params = {
            "user": secrets["snowflake_user"],
            "password": secrets["snowflake_password"],
            "account": secrets["snowflake_account"],
            "warehouse": "COMPUTE_WH",
            "database": "SYNC_DB",
            "schema": "STAGING",
        }

        # 2. Iterate and Sync
        for table_cfg in config["tables"]:
            # Get the last sync timestamp
            watermark = get_snowflake_watermark(
                snowflake_params,
                table_cfg["table_name"],
                table_cfg["watermark_col"],
            )

            # Export new data to S3
            export_from_aurora(aurora_params, s3_bucket, table_cfg, watermark)

        return {
            "statusCode": 200,
            "body": json.dumps("Sync completed successfully"),
        }

    except Exception as e:
        print(f"Error: {e}")
        return {
            "statusCode": 500,
            "body": json.dumps(f"Error: {str(e)}"),
        }
