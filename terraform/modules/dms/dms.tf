# ---------------------------------------------------------------------------------------------------------------------
# DMS MODULE: AWS DATABASE MIGRATION SERVICE
# ---------------------------------------------------------------------------------------------------------------------
# Provisions the replication instance, endpoints, and task for Aurora -> S3 CDC.

variable "project_name" {
  description = "Project name used for tagging and naming resources."
}
variable "subnet_ids" {
  type        = list(string)
  description = "Private subnet IDs for the replication subnet group."
}
variable "security_group_ids" {
  type        = list(string)
  description = "Security group IDs for the DMS replication instance."
}
variable "aurora_endpoint" {
  description = "Aurora PostgreSQL endpoint hostname."
}
variable "aurora_port" {
  description = "Aurora PostgreSQL port."
  type        = number
  default     = 5432
}
variable "aurora_database" {
  description = "Aurora PostgreSQL database name."
}
variable "aurora_username" {
  description = "Aurora PostgreSQL replication username"
  sensitive   = true
}
variable "aurora_password" {
  description = "Aurora PostgreSQL replication password"
  sensitive   = true
}
variable "s3_bucket_name" {
  description = "Target S3 bucket for CDC files."
}
variable "s3_prefix" {
  description = "S3 prefix for CDC output (e.g., dms)."
  default     = "dms"
}
variable "replication_instance_class" {
  description = "DMS replication instance class."
  default     = "dms.t3.medium"
}
variable "allocated_storage" {
  description = "Allocated storage (GB) for the replication instance."
  default     = 50
}
variable "multi_az" {
  description = "Enable Multi-AZ for the replication instance."
  type        = bool
  default     = false
}
variable "table_mappings" {
  description = "DMS table mappings JSON string."
  type        = string
}
variable "replication_task_settings" {
  description = "DMS replication task settings JSON string."
  type        = string
  default     = <<SETTINGS
{
  "Logging": {
    "EnableLogging": true
  }
}
SETTINGS
}

resource "aws_iam_role" "dms_s3_access" {
  name = "${var.project_name}-dms-s3-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "dms.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "dms_s3_access" {
  name = "${var.project_name}-dms-s3-policy"
  role = aws_iam_role.dms_s3_access.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:AbortMultipartUpload",
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = [
          "arn:aws:s3:::${var.s3_bucket_name}",
          "arn:aws:s3:::${var.s3_bucket_name}/*"
        ]
      }
    ]
  })
}

resource "aws_dms_replication_subnet_group" "main" {
  replication_subnet_group_id          = "${var.project_name}-dms-subnets"
  replication_subnet_group_description = "DMS subnet group for ${var.project_name}"
  subnet_ids                           = var.subnet_ids
}

resource "aws_dms_replication_instance" "main" {
  replication_instance_id     = "${var.project_name}-dms"
  replication_instance_class  = var.replication_instance_class
  allocated_storage           = var.allocated_storage
  publicly_accessible         = false
  multi_az                    = var.multi_az
  vpc_security_group_ids      = var.security_group_ids
  replication_subnet_group_id = aws_dms_replication_subnet_group.main.id
}

resource "aws_dms_endpoint" "source" {
  endpoint_id   = "${var.project_name}-aurora-source"
  endpoint_type = "source"
  engine_name   = "aurora-postgresql"

  server_name   = var.aurora_endpoint
  port          = var.aurora_port
  database_name = var.aurora_database
  username      = var.aurora_username
  password      = var.aurora_password
  ssl_mode      = "require"
}

resource "aws_dms_endpoint" "target" {
  endpoint_id   = "${var.project_name}-s3-target"
  endpoint_type = "target"
  engine_name   = "s3"

  s3_settings {
    bucket_name             = var.s3_bucket_name
    bucket_folder           = var.s3_prefix
    data_format             = "parquet"
    parquet_version         = "parquet-1-0"
    include_op_for_full_load = true
    cdc_inserts_only        = false
    service_access_role_arn = aws_iam_role.dms_s3_access.arn
  }
}

resource "aws_dms_replication_task" "cdc" {
  replication_task_id       = "${var.project_name}-cdc"
  migration_type            = "full-load-and-cdc"
  replication_instance_arn  = aws_dms_replication_instance.main.replication_instance_arn
  source_endpoint_arn       = aws_dms_endpoint.source.endpoint_arn
  target_endpoint_arn       = aws_dms_endpoint.target.endpoint_arn
  table_mappings            = var.table_mappings
  replication_task_settings = var.replication_task_settings
}

output "replication_instance_arn" {
  value = aws_dms_replication_instance.main.replication_instance_arn
}

output "replication_task_arn" {
  value = aws_dms_replication_task.cdc.replication_task_arn
}
