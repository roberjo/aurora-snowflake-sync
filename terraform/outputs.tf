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

output "dms_replication_instance_arn" {
  description = "DMS replication instance ARN"
  value       = module.dms.replication_instance_arn
}

output "dms_replication_task_arn" {
  description = "DMS replication task ARN"
  value       = module.dms.replication_task_arn
}

output "snowflake_storage_integration" {
  description = "The name of the Snowflake Storage Integration"
  value       = upper("${var.project_name}_s3_int")
}
