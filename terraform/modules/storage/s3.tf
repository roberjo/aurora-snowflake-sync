variable "project_name" {}

resource "aws_s3_bucket" "data_lake" {
  bucket_prefix = "${var.project_name}-datalake-"
  force_destroy = true # For demo purposes; be careful in prod

  tags = {
    Name = "${var.project_name}-datalake"
  }
}

resource "aws_s3_bucket_versioning" "data_lake" {
  bucket = aws_s3_bucket.data_lake.id
  versioning_configuration {
    status = "Enabled"
  }
}

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

output "bucket_id" {
  value = aws_s3_bucket.data_lake.id
}

output "bucket_arn" {
  value = aws_s3_bucket.data_lake.arn
}
