# ---------------------------------------------------------------------------------------------------------------------
# VARIABLES
# ---------------------------------------------------------------------------------------------------------------------
# This file defines the input variables for the Terraform configuration.
# These variables allow for customization of the deployment (e.g., region, project name, credentials).

variable "aws_region" {
  description = "AWS Region"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name for resource tagging"
  type        = string
  default     = "aurora-snowflake-sync"
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "snowflake_account" {
  description = "Snowflake Account URL"
  type        = string
  sensitive   = true
}

variable "snowflake_user" {
  description = "Snowflake User"
  type        = string
  sensitive   = true
}

variable "snowflake_password" {
  description = "Snowflake Password"
  type        = string
  sensitive   = true
}

variable "snowflake_role" {
  description = "Snowflake Role"
  type        = string
  default     = "SYSADMIN"
}

variable "storage_integration_role_arn" {
  description = "AWS IAM role ARN Snowflake should assume for the storage integration."
  type        = string
}

variable "s3_force_destroy" {
  description = "Allow S3 buckets to be destroyed when non-empty (dev only)."
  type        = bool
  default     = false
}

variable "s3_enable_access_logging" {
  description = "Enable server access logging for the data lake bucket."
  type        = bool
  default     = true
}

# ---------------------------------------------------------------------------------------------------------------------
# SNOWFLAKE TABLE DEFINITIONS
# ---------------------------------------------------------------------------------------------------------------------

variable "table_definitions" {
  description = "Per-table configuration for Snowpipe auto-ingest and merge tasks."
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
  default = {
    ORDERS_CDC = {
      prefix        = "cdc/public/orders"
      staging_table = "ORDERS_CDC"
      final_table   = "ORDERS"
      primary_keys  = ["ORDER_ID"]
      columns = [
        { name = "ORDER_ID", type = "NUMBER" },
        { name = "CUSTOMER_ID", type = "NUMBER" },
        { name = "STATUS", type = "STRING" },
        { name = "UPDATED_AT", type = "TIMESTAMP_NTZ" },
        { name = "COMMIT_TS", type = "TIMESTAMP_NTZ" },
        { name = "OP", type = "STRING" }
      ]
      metadata = {
        operation_column        = "OP"
        commit_timestamp_column = "COMMIT_TS"
      }
      task_schedule = "60 MINUTE"
    }
    CUSTOMERS_CDC = {
      prefix        = "cdc/public/customers"
      staging_table = "CUSTOMERS_CDC"
      final_table   = "CUSTOMERS"
      primary_keys  = ["CUSTOMER_ID"]
      columns = [
        { name = "CUSTOMER_ID", type = "NUMBER" },
        { name = "EMAIL", type = "STRING" },
        { name = "FIRST_NAME", type = "STRING" },
        { name = "LAST_NAME", type = "STRING" },
        { name = "UPDATED_AT", type = "TIMESTAMP_NTZ" },
        { name = "COMMIT_TS", type = "TIMESTAMP_NTZ" },
        { name = "OP", type = "STRING" }
      ]
      metadata = {
        operation_column        = "OP"
        commit_timestamp_column = "COMMIT_TS"
      }
      task_schedule = "60 MINUTE"
    }
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# AURORA CONFIGURATION
# ---------------------------------------------------------------------------------------------------------------------

variable "aurora_endpoint" {
  description = "Aurora PostgreSQL endpoint hostname."
  type        = string
}

variable "aurora_port" {
  description = "Aurora PostgreSQL port."
  type        = number
  default     = 5432
}

variable "aurora_database" {
  description = "Aurora PostgreSQL database name."
  type        = string
}

variable "aurora_secret_arn" {
  description = "ARN of the Secrets Manager secret containing Aurora credentials (username/password)."
  type        = string
}

# ---------------------------------------------------------------------------------------------------------------------
# LAMBDA CDC CONFIGURATION
# ---------------------------------------------------------------------------------------------------------------------

variable "lambda_table_definitions" {
  description = "Per-table configuration for Lambda CDC export."
  type = map(object({
    source_schema       = string
    source_table        = string
    source_columns      = list(string)
    watermark_column    = string
    created_at_column   = optional(string)
    s3_prefix           = string
    schedule_expression = optional(string, "rate(5 minutes)")
    batch_size          = optional(number, 10000)
    timeout_seconds     = optional(number, 300)
    memory_mb           = optional(number, 512)
  }))
  default = {
    ORDERS_CDC = {
      source_schema       = "public"
      source_table        = "orders"
      source_columns      = ["order_id", "customer_id", "status", "updated_at", "created_at"]
      watermark_column    = "updated_at"
      created_at_column   = "created_at"
      s3_prefix           = "cdc/public/orders"
      schedule_expression = "rate(5 minutes)"
      batch_size          = 10000
      timeout_seconds     = 300
      memory_mb           = 512
    }
    CUSTOMERS_CDC = {
      source_schema       = "public"
      source_table        = "customers"
      source_columns      = ["customer_id", "email", "first_name", "last_name", "updated_at", "created_at"]
      watermark_column    = "updated_at"
      created_at_column   = "created_at"
      s3_prefix           = "cdc/public/customers"
      schedule_expression = "rate(5 minutes)"
      batch_size          = 10000
      timeout_seconds     = 300
      memory_mb           = 512
    }
  }
}

variable "lambda_log_retention_days" {
  description = "CloudWatch log retention for Lambda function logs."
  type        = number
  default     = 30
}

variable "alarm_sns_topic_arn" {
  description = "SNS topic ARN for CloudWatch alarms (optional)."
  type        = string
  default     = null
}
