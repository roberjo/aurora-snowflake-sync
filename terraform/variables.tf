# ---------------------------------------------------------------------------------------------------------------------
# VARIABLES
# ---------------------------------------------------------------------------------------------------------------------
# This file defines the input variables for the Terraform configuration.
# These variables allow for customization of the deployment (e.g., region, project name, credentials).

variable "aws_region" {
  description = "AWS Region"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name for resource tagging"
  type        = string
  default     = "aurora-snowflake-sync"
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "snowflake_account" {
  description = "Snowflake Account URL"
  type        = string
  sensitive   = true
}

variable "snowflake_user" {
  description = "Snowflake User"
  type        = string
  sensitive   = true
}

variable "snowflake_password" {
  description = "Snowflake Password"
  type        = string
  sensitive   = true
}

variable "snowflake_role" {
  description = "Snowflake Role"
  type        = string
  default     = "SYSADMIN"
}

variable "vault_address" {
  description = "Vault Server Address"
  type        = string
}

variable "vault_token" {
  description = "Vault Token"
  type        = string
  sensitive   = true
}
