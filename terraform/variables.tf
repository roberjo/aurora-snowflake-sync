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
      prefix        = "dms/public/orders"
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
      prefix        = "dms/public/customers"
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

variable "aurora_username" {
  description = "Aurora PostgreSQL replication username."
  type        = string
  sensitive   = true
}

variable "aurora_password" {
  description = "Aurora PostgreSQL replication password."
  type        = string
  sensitive   = true
}

variable "dms_s3_prefix" {
  description = "S3 prefix for DMS CDC output."
  type        = string
  default     = "dms"
}

variable "dms_replication_instance_class" {
  description = "DMS replication instance class."
  type        = string
  default     = "dms.t3.medium"
}

variable "dms_allocated_storage" {
  description = "DMS replication instance allocated storage (GB)."
  type        = number
  default     = 50
}

variable "dms_multi_az" {
  description = "Enable Multi-AZ for DMS replication instance."
  type        = bool
  default     = true
}
variable "dms_kms_key_arn" {
  description = "KMS key ARN for DMS replication instance/storage."
  type        = string
  default     = null
}
variable "dms_log_retention_days" {
  description = "CloudWatch log retention for DMS task logs."
  type        = number
  default     = 30
}

variable "dms_table_mappings" {
  description = "DMS table mappings JSON."
  type        = string
  default     = <<MAPPINGS
{
  "rules": [
    {
      "rule-type": "selection",
      "rule-id": "1",
      "rule-name": "all-public",
      "object-locator": {
        "schema-name": "public",
        "table-name": "%"
      },
      "rule-action": "include"
    }
  ]
}
MAPPINGS
}

variable "dms_replication_task_settings" {
  description = "DMS replication task settings JSON."
  type        = string
  default     = <<SETTINGS
{
  "Logging": {
    "EnableLogging": true,
    "LogComponents": [
      { "Id": "SOURCE_CAPTURE", "Severity": "LOGGER_SEVERITY_DEFAULT" },
      { "Id": "TARGET_APPLY", "Severity": "LOGGER_SEVERITY_DEFAULT" }
    ]
  },
  "ValidationSettings": {
    "EnableValidation": true,
    "ValidationMode": "RowLevel"
  },
  "ErrorBehavior": {
    "DataErrorPolicy": "LOG_ERROR",
    "DataTruncationErrorPolicy": "LOG_ERROR",
    "TableErrorPolicy": "SUSPEND_TABLE",
    "RecoverableErrorCount": -1,
    "RecoverableErrorInterval": 5,
    "RecoverableErrorThrottling": true,
    "RecoverableErrorThrottlingMax": 1800,
    "ApplyErrorDeletePolicy": "IGNORE_RECORD",
    "FailOnNoTablesCaptured": true
  },
  "FullLoadSettings": {
    "TargetTablePrepMode": "TRUNCATE_BEFORE_LOAD",
    "StopTaskCachedChangesApplied": true,
    "StopTaskCachedChangesNotApplied": false,
    "MaxFullLoadSubTasks": 8
  }
}
SETTINGS
}
