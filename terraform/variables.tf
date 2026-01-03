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

variable "table_definitions" {
  description = "Map of CDC staging table names to S3 prefixes for Snowpipe auto-ingest."
  type = map(object({
    prefix = string
  }))
  default = {
    ORDERS_CDC    = { prefix = "dms/public/orders" }
    CUSTOMERS_CDC = { prefix = "dms/public/customers" }
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
  default     = false
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
    "EnableLogging": true
  }
}
SETTINGS
}
