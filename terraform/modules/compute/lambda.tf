# ---------------------------------------------------------------------------------------------------------------------
# COMPUTE MODULE: AWS LAMBDA
# ---------------------------------------------------------------------------------------------------------------------
# This module defines the AWS Lambda function responsible for the data synchronization logic.
# It includes the function definition, IAM roles and policies for permissions, and the
# EventBridge schedule to trigger the function periodically.

variable "project_name" {
  description = "Name of the project, used for tagging and naming resources."
}
variable "vpc_id" {
  description = "ID of the VPC where the Lambda will run."
}
variable "subnet_ids" { 
  type = list(string) 
  description = "List of private subnet IDs for the Lambda function."
}
variable "security_group_ids" { 
  type = list(string) 
  description = "List of security group IDs to attach to the Lambda."
}
variable "s3_bucket_id" {
  description = "ID of the S3 bucket for data staging."
}
variable "s3_bucket_arn" {
  description = "ARN of the S3 bucket for IAM policy permissions."
}
variable "vault_address" {
  description = "Address of the Hashicorp Vault server."
}

# Zip the Python code for the Lambda function
# This automatically creates a deployment package from the source file.
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/../../lambda/exporter.py"
  output_path = "${path.module}/exporter.zip"
}

# IAM Role for Lambda
# Defines the identity that the Lambda function assumes during execution.
resource "aws_iam_role" "lambda_role" {
  name = "${var.project_name}-lambda-role"

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
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "lambda_vpc" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# Custom IAM Policy
# Grants specific permissions required by the application logic:
# - S3 access to read/write exported data.
resource "aws_iam_policy" "lambda_custom" {
  name = "${var.project_name}-lambda-policy"

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

resource "aws_iam_role_policy_attachment" "lambda_custom_attach" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_custom.arn
}

# Lambda Function Resource
# Deploys the actual function code and configuration.
# - Runs inside the VPC to access internal resources.
# - Has environment variables for configuration.
resource "aws_lambda_function" "exporter" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "${var.project_name}-exporter"
  role             = aws_iam_role.lambda_role.arn
  handler          = "exporter.lambda_handler"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  runtime          = "python3.9"
  timeout          = 300 # 5 minutes

  vpc_config {
    subnet_ids         = var.subnet_ids
    security_group_ids = var.security_group_ids
  }

  environment {
    variables = {
      S3_BUCKET   = var.s3_bucket_id
      VAULT_ADDR  = var.vault_address
      # VAULT_TOKEN would be injected securely, not here in plaintext ideally
    }
  }
}

# EventBridge Schedule
# Triggers the Lambda function every hour.
resource "aws_cloudwatch_event_rule" "schedule" {
  name                = "${var.project_name}-schedule"
  description         = "Schedule for Aurora to Snowflake sync"
  schedule_expression = "rate(1 hour)"
}

resource "aws_cloudwatch_event_target" "lambda_target" {
  rule      = aws_cloudwatch_event_rule.schedule.name
  target_id = "SendToLambda"
  arn       = aws_lambda_function.exporter.arn
}

# Permission for EventBridge to invoke Lambda
resource "aws_lambda_permission" "allow_cloudwatch" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.exporter.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.schedule.arn
}
