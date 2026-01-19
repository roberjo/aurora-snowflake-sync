# ---------------------------------------------------------------------------------------------------------------------
# ROOT MODULE
# ---------------------------------------------------------------------------------------------------------------------
# This is the entry point for the Terraform configuration.
# It defines the required providers (AWS, Snowflake) and orchestrates the deployment
# by calling child modules for Network, Storage, Lambda, State, and Snowflake resources.

terraform {
  # Terraform Cloud configuration for state management
  cloud {
    organization = "my-org"
    workspaces {
      name = "aurora-snowflake-sync"
    }
  }

  required_providers {
    # AWS Provider: Used to create VPC, Lambda, S3, DynamoDB, etc.
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    # Snowflake Provider: Used to create Snowflake resources (Storage Integration, Pipes, etc.)
    snowflake = {
      source  = "Snowflake-Labs/snowflake"
      version = "~> 0.87"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

provider "snowflake" {
  account  = var.snowflake_account
  user     = var.snowflake_user
  password = var.snowflake_password
  role     = var.snowflake_role
}

# ---------------------------------------------------------------------------------------------------------------------
# MODULES
# ---------------------------------------------------------------------------------------------------------------------

# Network Module
# Creates the VPC, Subnets, and Security Groups required for Lambda
# to run securely and connect to Aurora and other resources.
module "network" {
  source = "./modules/network"

  vpc_cidr     = var.vpc_cidr
  project_name = var.project_name
}

# Storage Module
# Creates the S3 bucket used as a staging area for data exported from Aurora
# before it is loaded into Snowflake.
module "storage" {
  source = "./modules/storage"

  project_name                 = var.project_name
  force_destroy                = var.s3_force_destroy
  enable_access_logging        = var.s3_enable_access_logging
  storage_integration_role_arn = var.storage_integration_role_arn
  lambda_role_arn              = module.lambda.lambda_role_arn
}

# State Module
# Creates the DynamoDB table for watermark state management.
module "state" {
  source = "./modules/state"

  project_name = var.project_name
}

# Lambda Module
# Creates Lambda functions for CDC export from Aurora to S3.
module "lambda" {
  source = "./modules/lambda"

  project_name        = var.project_name
  subnet_ids          = module.network.private_subnet_ids
  lambda_sg_id        = module.network.lambda_sg_id
  aurora_host         = var.aurora_endpoint
  aurora_port         = var.aurora_port
  aurora_database     = var.aurora_database
  aurora_secret_arn   = var.aurora_secret_arn
  s3_bucket_name      = module.storage.bucket_id
  s3_bucket_arn       = module.storage.bucket_arn
  kms_key_arn         = module.storage.kms_key_arn
  dynamodb_table_name = module.state.table_name
  dynamodb_table_arn  = module.state.table_arn
  table_definitions   = var.lambda_table_definitions
  log_retention_days  = var.lambda_log_retention_days
  alarm_sns_topic_arn = var.alarm_sns_topic_arn
  kms_key_arn              = var.dms_kms_key_arn
  log_retention_days       = var.dms_log_retention_days
}

# Snowflake Module
# Configures Snowflake resources including the Storage Integration to allow Snowflake
# to read from the S3 bucket, and the Snowpipe for auto-ingestion (optional/future).
module "snowflake" {
  source = "./modules/snowflake"

  project_name         = var.project_name
  s3_bucket_url        = "s3://${module.storage.bucket_id}/"
  s3_bucket_id         = module.storage.bucket_id
  storage_aws_role_arn = var.storage_integration_role_arn
  table_definitions    = var.table_definitions
}
