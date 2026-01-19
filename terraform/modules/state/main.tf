# ---------------------------------------------------------------------------------------------------------------------
# STATE MODULE: DYNAMODB WATERMARK TABLE
# ---------------------------------------------------------------------------------------------------------------------
# Provisions DynamoDB table for storing CDC watermark state with optimistic locking.

resource "aws_dynamodb_table" "watermarks" {
  name         = "${var.project_name}-watermarks"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "table_name"

  attribute {
    name = "table_name"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled = true
  }

  tags = merge(
    {
      Name = "${var.project_name}-watermarks"
    },
    var.tags
  )
}
