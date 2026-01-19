# ---------------------------------------------------------------------------------------------------------------------
# LAMBDA MODULE: MAIN
# ---------------------------------------------------------------------------------------------------------------------
# Provisions Lambda functions, IAM roles, layers, and DLQ for CDC export.

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

# ---------------------------------------------------------------------------------------------------------------------
# IAM ROLE FOR LAMBDA
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_iam_role" "lambda" {
  name = "${var.project_name}-lambda-cdc-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = var.tags
}

# CloudWatch Logs policy
resource "aws_iam_role_policy" "lambda_logs" {
  name = "${var.project_name}-lambda-logs"
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"
      }
    ]
  })
}

# VPC network interface policy
resource "aws_iam_role_policy" "lambda_vpc" {
  name = "${var.project_name}-lambda-vpc"
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateNetworkInterface",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DeleteNetworkInterface",
          "ec2:AssignPrivateIpAddresses",
          "ec2:UnassignPrivateIpAddresses"
        ]
        Resource = "*"
      }
    ]
  })
}

# S3 access policy
resource "aws_iam_role_policy" "lambda_s3" {
  name = "${var.project_name}-lambda-s3"
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          var.s3_bucket_arn,
          "${var.s3_bucket_arn}/*"
        ]
      }
    ]
  })
}

# KMS policy (if KMS key is provided)
resource "aws_iam_role_policy" "lambda_kms" {
  count = var.kms_key_arn != null ? 1 : 0

  name = "${var.project_name}-lambda-kms"
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "kms:Encrypt",
          "kms:GenerateDataKey"
        ]
        Resource = var.kms_key_arn
      }
    ]
  })
}

# DynamoDB policy
resource "aws_iam_role_policy" "lambda_dynamodb" {
  name = "${var.project_name}-lambda-dynamodb"
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem"
        ]
        Resource = var.dynamodb_table_arn
      }
    ]
  })
}

# Secrets Manager policy
resource "aws_iam_role_policy" "lambda_secrets" {
  name = "${var.project_name}-lambda-secrets"
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = var.aurora_secret_arn
      }
    ]
  })
}

# SQS DLQ policy
resource "aws_iam_role_policy" "lambda_dlq" {
  name = "${var.project_name}-lambda-dlq"
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sqs:SendMessage"
        ]
        Resource = aws_sqs_queue.dlq.arn
      }
    ]
  })
}

# ---------------------------------------------------------------------------------------------------------------------
# DEAD LETTER QUEUE
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_sqs_queue" "dlq" {
  name = "${var.project_name}-cdc-dlq"

  message_retention_seconds  = 1209600 # 14 days
  visibility_timeout_seconds = 300

  sqs_managed_sse_enabled = true

  tags = merge(
    {
      Name = "${var.project_name}-cdc-dlq"
    },
    var.tags
  )
}

# ---------------------------------------------------------------------------------------------------------------------
# LAMBDA LAYER
# ---------------------------------------------------------------------------------------------------------------------

# Note: The layer ZIP should be built externally using `make layer` in the lambda/ directory.
# This assumes the layer is uploaded to S3 or provided as a local file.

resource "aws_lambda_layer_version" "dependencies" {
  layer_name          = "${var.project_name}-cdc-dependencies"
  description         = "Python dependencies for CDC Lambda (pandas, pyarrow, psycopg2)"
  compatible_runtimes = ["python3.11"]

  # Use S3 or local file - adjust as needed
  filename         = "${path.module}/../../../lambda/build/lambda-layer.zip"
  source_code_hash = fileexists("${path.module}/../../../lambda/build/lambda-layer.zip") ? filebase64sha256("${path.module}/../../../lambda/build/lambda-layer.zip") : null

  lifecycle {
    create_before_destroy = true
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# LAMBDA FUNCTIONS (one per table)
# ---------------------------------------------------------------------------------------------------------------------

data "archive_file" "lambda_code" {
  type        = "zip"
  source_dir  = "${path.module}/../../../lambda/src"
  output_path = "${path.module}/../../../lambda/build/lambda-function.zip"
}

resource "aws_lambda_function" "cdc" {
  for_each = var.table_definitions

  function_name = "${var.project_name}-cdc-${lower(replace(each.key, "_", "-"))}"
  description   = "CDC export for ${each.key}"
  role          = aws_iam_role.lambda.arn
  handler       = "handler.lambda_handler"
  runtime       = "python3.11"

  filename         = data.archive_file.lambda_code.output_path
  source_code_hash = data.archive_file.lambda_code.output_base64sha256

  layers = [aws_lambda_layer_version.dependencies.arn]

  timeout     = each.value.timeout_seconds
  memory_size = each.value.memory_mb

  vpc_config {
    subnet_ids         = var.subnet_ids
    security_group_ids = [var.lambda_sg_id]
  }

  dead_letter_config {
    target_arn = aws_sqs_queue.dlq.arn
  }

  environment {
    variables = {
      TABLE_NAME           = each.key
      AURORA_HOST          = var.aurora_host
      AURORA_PORT          = tostring(var.aurora_port)
      AURORA_DATABASE      = var.aurora_database
      AURORA_SECRET_ARN    = var.aurora_secret_arn
      SOURCE_SCHEMA        = each.value.source_schema
      SOURCE_TABLE         = each.value.source_table
      SOURCE_COLUMNS       = join(",", each.value.source_columns)
      WATERMARK_COLUMN     = each.value.watermark_column
      CREATED_AT_COLUMN    = coalesce(each.value.created_at_column, "")
      S3_BUCKET            = var.s3_bucket_name
      S3_PREFIX            = each.value.s3_prefix
      KMS_KEY_ID           = coalesce(var.kms_key_arn, "")
      DYNAMODB_TABLE       = var.dynamodb_table_name
      BATCH_SIZE           = tostring(each.value.batch_size)
      TIMEOUT_BUFFER_SECONDS = "60"
    }
  }

  tags = merge(
    {
      Name  = "${var.project_name}-cdc-${each.key}"
      Table = each.key
    },
    var.tags
  )

  depends_on = [
    aws_iam_role_policy.lambda_logs,
    aws_iam_role_policy.lambda_vpc,
    aws_iam_role_policy.lambda_s3,
    aws_iam_role_policy.lambda_dynamodb,
    aws_iam_role_policy.lambda_secrets,
    aws_iam_role_policy.lambda_dlq,
  ]
}

# CloudWatch Log Groups
resource "aws_cloudwatch_log_group" "lambda" {
  for_each = var.table_definitions

  name              = "/aws/lambda/${var.project_name}-cdc-${lower(replace(each.key, "_", "-"))}"
  retention_in_days = var.log_retention_days

  tags = var.tags
}
