terraform {
  cloud {
    organization = "my-org"
    workspaces {
      name = "aurora-snowflake-sync"
    }
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    snowflake = {
      source  = "Snowflake-Labs/snowflake"
      version = "~> 0.87"
    }
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

module "network" {
  source = "./modules/network"
  
  vpc_cidr = var.vpc_cidr
  project_name = var.project_name
}

module "storage" {
  source = "./modules/storage"
  
  project_name = var.project_name
}

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

module "snowflake" {
  source = "./modules/snowflake"

  project_name  = var.project_name
  s3_bucket_url = "s3://${module.storage.bucket_id}/"
  s3_bucket_id  = module.storage.bucket_id
}
