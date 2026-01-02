# ---------------------------------------------------------------------------------------------------------------------
# SNOWFLAKE MODULE
# ---------------------------------------------------------------------------------------------------------------------
# This module manages the Snowflake resources required for the data ingestion pipeline.
# It sets up the database, schema, and the integration with AWS S3 (Storage Integration, Stage, Pipe).

terraform {
  required_providers {
    snowflake = {
      source  = "Snowflake-Labs/snowflake"
    }
    aws = {
      source  = "hashicorp/aws"
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
  description = "Map of staging table names to expected S3 prefixes for auto ingest."
  type = map(object({
    prefix = string
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

# Storage Integration
# A secure object that stores the generated IAM user ARN and external ID for accessing S3.
# This allows Snowflake to access the S3 bucket without using long-term AWS credentials.
resource "snowflake_storage_integration" "s3_int" {
  name    = upper("${var.project_name}_s3_int")
  comment = "Storage integration for S3"
  type    = "EXTERNAL_STAGE"

  enabled = true

  storage_provider         = "S3"
  storage_aws_role_arn     = var.storage_aws_role_arn
  # After the integration is created, use the generated STORAGE_AWS_IAM_USER_ARN and
  # STORAGE_AWS_EXTERNAL_ID outputs to update the AWS IAM role trust policy.
  
  storage_allowed_locations = [var.s3_bucket_url]
}

# File Format
# Defines how the CSV files in S3 should be parsed (delimiters, headers, etc.).
resource "snowflake_file_format" "csv_format" {
  name        = "CSV_FORMAT"
  database    = snowflake_database.main.name
  schema      = snowflake_schema.staging.name
  format_type = "CSV"
  compression = "AUTO"
  record_delimiter = "\n"
  field_delimiter = ","
  file_extension = "csv"
  skip_header = 1
}

# External Stage
# A named stage object that references the S3 bucket via the storage integration.
# This simplifies loading commands by referring to '@S3_STAGE' instead of the full URL and credentials.
resource "snowflake_stage" "main" {
  name        = "S3_STAGE"
  url         = var.s3_bucket_url
  database    = snowflake_database.main.name
  schema      = snowflake_schema.staging.name
  storage_integration = snowflake_storage_integration.s3_int.name
  file_format = snowflake_file_format.csv_format.name
}

# Pipes
# Create one pipe per table to route each S3 prefix into the correct staging table.
resource "snowflake_pipe" "table_pipes" {
  for_each = var.table_definitions

  database = snowflake_database.main.name
  schema   = snowflake_schema.staging.name
  name     = upper("${each.key}_PIPE")

  comment     = "Auto-ingest for ${each.key}"
  auto_ingest = true

  copy_statement = "COPY INTO ${snowflake_database.main.name}.${snowflake_schema.staging.name}.${each.key} FROM @${snowflake_database.main.name}.${snowflake_schema.staging.name}.${snowflake_stage.main.name}/${each.value.prefix} FILE_FORMAT=(FORMAT_NAME=${snowflake_database.main.name}.${snowflake_schema.staging.name}.${snowflake_file_format.csv_format.name})"
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
      filter_prefix = "${var.table_definitions[queue.key].prefix}/"
    }
  }
}
