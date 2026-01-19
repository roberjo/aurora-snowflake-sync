# ---------------------------------------------------------------------------------------------------------------------
# SNOWFLAKE MODULE
# ---------------------------------------------------------------------------------------------------------------------
# This module manages the Snowflake resources required for the data ingestion pipeline.
# It sets up the database, schema, and the integration with AWS S3 (Storage Integration, Stage, Pipe).

terraform {
  required_providers {
    snowflake = {
      source = "Snowflake-Labs/snowflake"
    }
    aws = {
      source = "hashicorp/aws"
    }
  }
}

variable "project_name" {
  description = "Project name used for naming Snowflake resources."
}
variable "s3_bucket_url" {
  description = "URL of the S3 bucket (s3://bucket-name/) to read data from."
}
variable "s3_bucket_id" {
  description = "ID of the S3 bucket to configure event notifications."
}
variable "storage_aws_role_arn" {
  description = "ARN of the AWS IAM role Snowflake will assume for the storage integration."
}

variable "table_definitions" {
  description = "Map of table configs to wire Snowpipe + merge tasks."
  type = map(object({
    prefix        = string
    staging_table = string
    final_table   = string
    primary_keys  = list(string)
    columns = list(object({
      name = string
      type = string
    }))
    metadata = object({
      operation_column        = string
      commit_timestamp_column = string
    })
    task_schedule = string
  }))
  default = {}
}

# Snowflake Database
# The container for all schemas and tables related to this project.
resource "snowflake_database" "main" {
  name = upper("${var.project_name}_db")
}

# Staging Schema
# A dedicated schema for landing raw data before it is transformed/moved to production tables.
resource "snowflake_schema" "staging" {
  database = snowflake_database.main.name
  name     = "STAGING"
}

resource "snowflake_schema" "final" {
  database = snowflake_database.main.name
  name     = "FINAL"
}

resource "snowflake_warehouse" "ingest" {
  name            = upper("${var.project_name}_INGEST_WH")
  warehouse_size  = "XSMALL"
  auto_suspend    = 60
  auto_resume     = true
}

# Storage Integration
# A secure object that stores the generated IAM user ARN and external ID for accessing S3.
# This allows Snowflake to access the S3 bucket without using long-term AWS credentials.
resource "snowflake_storage_integration" "s3_int" {
  name    = upper("${var.project_name}_s3_int")
  comment = "Storage integration for S3"
  type    = "EXTERNAL_STAGE"

  enabled = true

  storage_provider     = "S3"
  storage_aws_role_arn = var.storage_aws_role_arn
  # After the integration is created, use the generated STORAGE_AWS_IAM_USER_ARN and
  # STORAGE_AWS_EXTERNAL_ID outputs to update the AWS IAM role trust policy.

  storage_allowed_locations = [var.s3_bucket_url]
}

# File Format
# Defines how the CSV files in S3 should be parsed (delimiters, headers, etc.).
resource "snowflake_file_format" "parquet_format" {
  name        = "PARQUET_FORMAT"
  database    = snowflake_database.main.name
  schema      = snowflake_schema.staging.name
  format_type = "PARQUET"
  compression = "AUTO"
}

# External Stage
# A named stage object that references the S3 bucket via the storage integration.
# This simplifies loading commands by referring to '@S3_STAGE' instead of the full URL and credentials.
resource "snowflake_stage" "main" {
  name                = "S3_STAGE"
  url                 = var.s3_bucket_url
  database            = snowflake_database.main.name
  schema              = snowflake_schema.staging.name
  storage_integration = snowflake_storage_integration.s3_int.name
  file_format         = snowflake_file_format.parquet_format.name
}

locals {
  table_configs = {
    for name, def in var.table_definitions :
    name => {
      prefix        = def.prefix
      staging_table = upper(def.staging_table)
      final_table   = upper(def.final_table)
      op_col        = upper(def.metadata.operation_column)
      commit_col    = upper(def.metadata.commit_timestamp_column)
      primary_keys  = [for pk in def.primary_keys : upper(pk)]
      staging_columns = [
        for col in def.columns : {
          name = upper(col.name)
          type = col.type
        }
      ]
      final_columns = [
        for col in def.columns : {
          name = upper(col.name)
          type = col.type
        } if upper(col.name) != upper(def.metadata.operation_column)
      ]
      task_schedule = def.task_schedule
    }
  }
}

locals {
  merge_statements = {
    for name, cfg in local.table_configs :
    name => format(
      "MERGE INTO %s.%s.%s AS T USING (SELECT * FROM %s.%s.%s QUALIFY ROW_NUMBER() OVER (PARTITION BY %s ORDER BY %s DESC) = 1) AS S ON %s WHEN MATCHED AND S.%s = 'D' THEN DELETE WHEN MATCHED AND S.%s IN ('U','I') THEN UPDATE SET %s WHEN NOT MATCHED AND S.%s IN ('I','U') THEN INSERT (%s) VALUES (%s)",
      snowflake_database.main.name,
      snowflake_schema.final.name,
      cfg.final_table,
      snowflake_database.main.name,
      snowflake_schema.staging.name,
      cfg.staging_table,
      join(", ", cfg.primary_keys),
      cfg.commit_col,
      join(" AND ", [for pk in cfg.primary_keys : "T.${pk} = S.${pk}"]),
      cfg.op_col,
      cfg.op_col,
      join(", ", [for col in cfg.final_columns : "T.${col.name} = S.${col.name}" if col.name != cfg.op_col]),
      cfg.op_col,
      join(", ", [for col in cfg.final_columns : col.name]),
      join(", ", [for col in cfg.final_columns : "S.${col.name}"])
    )
  }
}

resource "snowflake_table" "staging_tables" {
  for_each = local.table_configs

  database = snowflake_database.main.name
  schema   = snowflake_schema.staging.name
  name     = each.value.staging_table

  dynamic "column" {
    for_each = each.value.staging_columns

    content {
      name = column.value.name
      type = column.value.type
    }
  }
}

resource "snowflake_table" "final_tables" {
  for_each = local.table_configs

  database = snowflake_database.main.name
  schema   = snowflake_schema.final.name
  name     = each.value.final_table

  dynamic "column" {
    for_each = each.value.final_columns

    content {
      name = column.value.name
      type = column.value.type
    }
  }
}

# Pipes
# Create one pipe per table to route each S3 prefix into the correct staging table.
resource "snowflake_pipe" "table_pipes" {
  for_each = local.table_configs

  database = snowflake_database.main.name
  schema   = snowflake_schema.staging.name
  name     = upper("${each.value.staging_table}_PIPE")

  comment     = "Auto-ingest for ${each.value.staging_table}"
  auto_ingest = true

  copy_statement = "COPY INTO ${snowflake_database.main.name}.${snowflake_schema.staging.name}.${each.value.staging_table} FROM @${snowflake_database.main.name}.${snowflake_schema.staging.name}.${snowflake_stage.main.name}/${each.value.prefix} FILE_FORMAT=(FORMAT_NAME=${snowflake_database.main.name}.${snowflake_schema.staging.name}.${snowflake_file_format.parquet_format.name})"

  depends_on = [snowflake_table.staging_tables]
}

resource "snowflake_task" "merge_tasks" {
  for_each = local.table_configs

  database = snowflake_database.main.name
  schema   = snowflake_schema.staging.name
  name     = upper("${each.value.final_table}_MERGE_TASK")

  warehouse     = snowflake_warehouse.ingest.name
  schedule      = each.value.task_schedule
  sql_statement = local.merge_statements[each.key]
  enabled       = true

  depends_on = [
    snowflake_table.staging_tables,
    snowflake_table.final_tables
  ]
}

# Configure S3 to send notifications to Snowpipe SQS
# S3 Bucket Notification
# Configures the S3 bucket to send an event notification to the Snowpipe SQS queue
# whenever a new object is created. This triggers the auto-ingestion.
resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = var.s3_bucket_id

  dynamic "queue" {
    for_each = snowflake_pipe.table_pipes

    content {
      queue_arn     = queue.value.notification_channel
      events        = ["s3:ObjectCreated:*"]
      filter_prefix = "${local.table_configs[queue.key].prefix}/"
    }
  }
}
