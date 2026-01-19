# ---------------------------------------------------------------------------------------------------------------------
# LAMBDA MODULE: VARIABLES
# ---------------------------------------------------------------------------------------------------------------------

variable "project_name" {
  description = "Project name used for naming resources."
  type        = string
}

variable "subnet_ids" {
  description = "Private subnet IDs for Lambda VPC configuration."
  type        = list(string)
}

variable "lambda_sg_id" {
  description = "Security group ID for Lambda functions."
  type        = string
}

variable "aurora_host" {
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
  description = "ARN of the Secrets Manager secret containing Aurora credentials."
  type        = string
}

variable "s3_bucket_name" {
  description = "S3 bucket name for CDC output."
  type        = string
}

variable "s3_bucket_arn" {
  description = "S3 bucket ARN for IAM permissions."
  type        = string
}

variable "kms_key_arn" {
  description = "KMS key ARN for S3 encryption."
  type        = string
  default     = null
}

variable "dynamodb_table_name" {
  description = "DynamoDB table name for watermark state."
  type        = string
}

variable "dynamodb_table_arn" {
  description = "DynamoDB table ARN for IAM permissions."
  type        = string
}

variable "table_definitions" {
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
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days."
  type        = number
  default     = 30
}

variable "alarm_sns_topic_arn" {
  description = "SNS topic ARN for CloudWatch alarms."
  type        = string
  default     = null
}

variable "tags" {
  description = "Additional tags to apply to resources."
  type        = map(string)
  default     = {}
}
