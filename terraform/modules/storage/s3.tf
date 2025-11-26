# ---------------------------------------------------------------------------------------------------------------------
# STORAGE MODULE: S3
# ---------------------------------------------------------------------------------------------------------------------
# This module creates the S3 bucket used as the intermediate storage (staging area)
# for data exported from Aurora before it is ingested into Snowflake.

variable "project_name" {
  description = "Project name used for bucket naming."
}

# S3 Bucket
# The primary storage location for the exported CSV files.
# 'force_destroy' is enabled for easier cleanup in this demo environment.
resource "aws_s3_bucket" "data_lake" {
  bucket_prefix = "${var.project_name}-datalake-"
  force_destroy = true # For demo purposes; be careful in prod

  tags = {
    Name = "${var.project_name}-datalake"
  }
}

# Bucket Versioning
# Enables versioning to keep a history of object changes and protect against accidental deletions.
resource "aws_s3_bucket_versioning" "data_lake" {
  bucket = aws_s3_bucket.data_lake.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Server-Side Encryption
# Encrypts data at rest using S3-managed keys (SSE-S3) for security compliance.
resource "aws_s3_bucket_server_side_encryption_configuration" "data_lake" {
  bucket = aws_s3_bucket.data_lake.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Event notification will be configured in Snowflake module or via Snowpipe directly,
# but we need to ensure the bucket exists first.

# Outputs
# Exposes the bucket name and ARN for use in other modules (e.g., Lambda permissions, Snowflake integration).
output "bucket_id" {
  value = aws_s3_bucket.data_lake.id
}

output "bucket_arn" {
  value = aws_s3_bucket.data_lake.arn
}
