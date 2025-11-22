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

variable "project_name" {}
variable "s3_bucket_url" {} # s3://bucket-name/
variable "s3_bucket_id" {}

resource "snowflake_database" "main" {
  name = upper("${var.project_name}_db")
}

resource "snowflake_schema" "staging" {
  database = snowflake_database.main.name
  name     = "STAGING"
}

resource "snowflake_storage_integration" "s3_int" {
  name    = upper("${var.project_name}_s3_int")
  comment = "Storage integration for S3"
  type    = "EXTERNAL_STAGE"

  enabled = true

  storage_provider         = "S3"
  storage_aws_role_arn     = "arn:aws:iam::123456789012:role/my-snowflake-role" # Placeholder, needs to be created or passed in
  # In reality, you create the integration, get the STORAGE_AWS_IAM_USER_ARN and STORAGE_AWS_EXTERNAL_ID, 
  # and then update the AWS IAM Role trust policy. 
  # For this plan, we assume the role exists or we'd need a two-step apply.
  
  storage_allowed_locations = [var.s3_bucket_url]
}

resource "snowflake_file_format" "csv_format" {
  name        = "CSV_FORMAT"
  database    = snowflake_database.main.name
  schema      = snowflake_schema.staging.name
  format_type = "CSV"
  csv_compression = "AUTO"
  record_delimiter = "\n"
  field_delimiter = ","
  file_extension = "csv"
  skip_header = 1
}

resource "snowflake_stage" "main" {
  name        = "S3_STAGE"
  url         = var.s3_bucket_url
  database    = snowflake_database.main.name
  schema      = snowflake_schema.staging.name
  storage_integration = snowflake_storage_integration.s3_int.name
  file_format = snowflake_file_format.csv_format.name
}

resource "snowflake_pipe" "main" {
  database = snowflake_database.main.name
  schema   = snowflake_schema.staging.name
  name     = "AUTO_INGEST_PIPE"
  
  comment = "Pipe to auto-ingest data from S3"
  auto_ingest = true
  
  # Example copy statement - in reality you might have one pipe per table
  copy_statement = "COPY INTO ${snowflake_database.main.name}.${snowflake_schema.staging.name}.MY_TABLE FROM @${snowflake_database.main.name}.${snowflake_schema.staging.name}.${snowflake_stage.main.name}"
}

# Configure S3 to send notifications to Snowpipe SQS
resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = var.s3_bucket_id

  queue {
    queue_arn     = snowflake_pipe.main.notification_channel
    events        = ["s3:ObjectCreated:*"]
  }
}
