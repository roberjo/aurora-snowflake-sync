# ---------------------------------------------------------------------------------------------------------------------
# STORAGE MODULE: S3
# ---------------------------------------------------------------------------------------------------------------------
# This module creates the S3 bucket used as the intermediate storage (staging area)
# for data exported from Aurora before it is ingested into Snowflake.

variable "project_name" {
  description = "Project name used for bucket naming."
}
variable "force_destroy" {
  description = "Allow bucket destroy even if non-empty (use only for dev)."
  type        = bool
  default     = false
}
variable "enable_access_logging" {
  description = "Enable S3 server access logging to a dedicated log bucket."
  type        = bool
  default     = true
}
variable "storage_integration_role_arn" {
  description = "AWS IAM role Snowflake assumes for the storage integration (granted read access via bucket policy)."
  type        = string
  default     = null
}

resource "aws_kms_key" "data_lake" {
  description             = "KMS key for ${var.project_name} data lake bucket"
  deletion_window_in_days = 7
  enable_key_rotation     = true
}

# S3 Bucket
# The primary storage location for the exported CDC files.
resource "aws_s3_bucket" "data_lake" {
  bucket_prefix = "${var.project_name}-datalake-"
  force_destroy = var.force_destroy

  tags = {
    Name = "${var.project_name}-datalake"
  }
}

# Block any form of public access to avoid accidental exposure of exported data.
resource "aws_s3_bucket_public_access_block" "data_lake" {
  bucket                  = aws_s3_bucket.data_lake.id
  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

# Enforce bucket-level ownership to prevent ACL takeovers and to ensure uploads land
# under the bucket owner's account by default.
resource "aws_s3_bucket_ownership_controls" "data_lake" {
  bucket = aws_s3_bucket.data_lake.id

  rule {
    object_ownership = "BucketOwnerEnforced"
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
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.data_lake.arn
    }
  }
}

resource "aws_s3_bucket" "data_lake_logs" {
  count = var.enable_access_logging ? 1 : 0

  bucket_prefix = "${var.project_name}-datalake-logs-"
  force_destroy = var.force_destroy

  tags = {
    Name = "${var.project_name}-datalake-logs"
  }
}

resource "aws_s3_bucket_public_access_block" "data_lake_logs" {
  count = var.enable_access_logging ? 1 : 0

  bucket                  = aws_s3_bucket.data_lake_logs[0].id
  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "data_lake_logs" {
  count = var.enable_access_logging ? 1 : 0

  bucket = aws_s3_bucket.data_lake_logs[0].id

  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "data_lake_logs" {
  count = var.enable_access_logging ? 1 : 0

  bucket = aws_s3_bucket.data_lake_logs[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

data "aws_iam_policy_document" "data_lake_logs" {
  count = var.enable_access_logging ? 1 : 0

  statement {
    sid = "AllowS3Logging"

    principals {
      type        = "Service"
      identifiers = ["logging.s3.amazonaws.com"]
    }

    actions = ["s3:PutObject"]

    resources = ["${aws_s3_bucket.data_lake_logs[0].arn}/*"]

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = [aws_s3_bucket.data_lake.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "data_lake_logs" {
  count = var.enable_access_logging ? 1 : 0

  bucket = aws_s3_bucket.data_lake_logs[0].id
  policy = data.aws_iam_policy_document.data_lake_logs[0].json
}

resource "aws_s3_bucket_logging" "data_lake" {
  count = var.enable_access_logging ? 1 : 0

  bucket        = aws_s3_bucket.data_lake.id
  target_bucket = aws_s3_bucket.data_lake_logs[0].id
  target_prefix = "access-logs/"
}

# Apply a simple lifecycle policy so transient staging data is automatically cleaned up
# after 30 days. Production deployments can tune this window per table if needed.
resource "aws_s3_bucket_lifecycle_configuration" "data_lake" {
  bucket = aws_s3_bucket.data_lake.id

  rule {
    id     = "expire-staging-data"
    status = "Enabled"

    expiration {
      days = 30
    }
  }
}

data "aws_iam_policy_document" "data_lake" {
  statement {
    sid = "DenyInsecureTransport"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions   = ["s3:*"]
    resources = [
      aws_s3_bucket.data_lake.arn,
      "${aws_s3_bucket.data_lake.arn}/*"
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }

  dynamic "statement" {
    for_each = var.storage_integration_role_arn == null ? [] : [var.storage_integration_role_arn]

    content {
      sid = "AllowSnowflakeRead"

      principals {
        type        = "AWS"
        identifiers = [statement.value]
      }

      actions = [
        "s3:GetObject",
        "s3:ListBucket"
      ]

      resources = [
        aws_s3_bucket.data_lake.arn,
        "${aws_s3_bucket.data_lake.arn}/*"
      ]
    }
  }
}

resource "aws_s3_bucket_policy" "data_lake" {
  bucket = aws_s3_bucket.data_lake.id
  policy = data.aws_iam_policy_document.data_lake.json
}

# Event notification will be configured in Snowflake module or via Snowpipe directly,
# but we need to ensure the bucket exists first.

# Outputs
# Exposes the bucket name and ARN for use in other modules (e.g., DMS permissions, Snowflake integration).
output "bucket_id" {
  value = aws_s3_bucket.data_lake.id
}

output "bucket_arn" {
  value = aws_s3_bucket.data_lake.arn
}
