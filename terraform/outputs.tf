# ---------------------------------------------------------------------------------------------------------------------
# OUTPUTS
# ---------------------------------------------------------------------------------------------------------------------
# These outputs provide key information about the deployed infrastructure.
# They are useful for verification, integration with other systems, or for quick access to resource IDs.

output "vpc_id" {
  description = "The ID of the VPC"
  value       = module.network.vpc_id
}

output "s3_bucket_id" {
  description = "The name of the S3 bucket used for the data lake"
  value       = module.storage.bucket_id
}

output "dynamodb_table_name" {
  description = "DynamoDB table name for watermark state"
  value       = module.state.table_name
}

output "lambda_function_arns" {
  description = "ARNs of the Lambda CDC functions"
  value       = module.lambda.lambda_function_arns
}

output "lambda_function_names" {
  description = "Names of the Lambda CDC functions"
  value       = module.lambda.lambda_function_names
}

output "lambda_dlq_url" {
  description = "URL of the Lambda dead letter queue"
  value       = module.lambda.dlq_url
}

output "snowflake_storage_integration" {
  description = "The name of the Snowflake Storage Integration"
  value       = upper("${var.project_name}_s3_int")
}
