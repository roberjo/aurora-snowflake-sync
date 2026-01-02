# ---------------------------------------------------------------------------------------------------------------------
# ROOT MODULE
# ---------------------------------------------------------------------------------------------------------------------
# This is the entry point for the Terraform configuration.
# It defines the required providers (AWS, Snowflake, Vault) and orchestrates the deployment
# by calling child modules for Network, Storage, Compute, and Snowflake resources.

terraform {
  # Terraform Cloud configuration for state management
  cloud {
    organization = "my-org"
    workspaces {
      name = "aurora-snowflake-sync"
    }
  }

  required_providers {
    # AWS Provider: Used to create VPC, Lambda, S3, etc.
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    # Snowflake Provider: Used to create Snowflake resources (Storage Integration, Pipes, etc.)
    snowflake = {
      source  = "Snowflake-Labs/snowflake"
      version = "~> 0.87"
    }
    # Vault Provider: Used to interact with Hashicorp Vault for secrets management
    vault = {
      source  = "hashicorp/vault"
      version = "~> 3.25"
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

provider "vault" {
  address = var.vault_address
  token   = var.vault_token
}

# ---------------------------------------------------------------------------------------------------------------------
# MODULES
# ---------------------------------------------------------------------------------------------------------------------

# Network Module
# Creates the VPC, Subnets, and Security Groups required for the Lambda function
# to run securely and connect to other resources.
module "network" {
  source = "./modules/network"
  
  vpc_cidr = var.vpc_cidr
  project_name = var.project_name
}

# Storage Module
# Creates the S3 bucket used as a staging area for data exported from Aurora
# before it is loaded into Snowflake.
module "storage" {
  source = "./modules/storage"
  
  project_name = var.project_name
}

# Compute Module
# Deploys the AWS Lambda function that orchestrates the sync process.
# It needs access to the VPC (to reach Vault/Aurora) and S3 (to write data).
module "compute" {
  source = "./modules/compute"

  project_name       = var.project_name
  vpc_id             = module.network.vpc_id
  subnet_ids         = module.network.private_subnet_ids
  security_group_ids = [module.network.lambda_sg_id]
  s3_bucket_id       = module.storage.bucket_id
  s3_bucket_arn      = module.storage.bucket_arn
  vault_address      = var.vault_address
}

# Snowflake Module
# Configures Snowflake resources including the Storage Integration to allow Snowflake
# to read from the S3 bucket, and the Snowpipe for auto-ingestion (optional/future).
module "snowflake" {
  source = "./modules/snowflake"

  project_name           = var.project_name
  s3_bucket_url          = "s3://${module.storage.bucket_id}/"
  s3_bucket_id           = module.storage.bucket_id
  storage_aws_role_arn   = var.storage_integration_role_arn
  table_definitions      = var.table_definitions
}
