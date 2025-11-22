output "vpc_id" {
  description = "The ID of the VPC"
  value       = module.network.vpc_id
}

output "s3_bucket_id" {
  description = "The name of the S3 bucket used for the data lake"
  value       = module.storage.bucket_id
}

output "lambda_function_name" {
  description = "The name of the Lambda function"
  value       = "${var.project_name}-exporter"
}

output "snowflake_storage_integration" {
  description = "The name of the Snowflake Storage Integration"
  value       = upper("${var.project_name}_s3_int")
}
