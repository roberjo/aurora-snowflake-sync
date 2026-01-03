# Aurora to Snowflake Sync

This project implements a CDC-driven data synchronization pipeline from AWS Aurora PostgreSQL to Snowflake.

## Documentation
*   [Architecture Design](docs/ARCHITECTURE.md)
*   [Developer Guide](docs/DEVELOPER_GUIDE.md)
*   [Deployment Strategy](docs/DEPLOYMENT.md)
*   [Operational Runbook](docs/RUNBOOK.md)
*   [Observability & Monitoring](docs/OBSERVABILITY.md)
*   [Security](docs/SECURITY.md)
*   [Export & Sync Process](docs/DATA_SYNC_PROCESS.md)
*   [FAQ](docs/FAQ.md)

## Architecture Overview

1.  **Change Capture**: AWS DMS (CDC from Aurora PostgreSQL).
2.  **Delivery**: DMS writes CDC files to S3.
3.  **Staging**: S3 Bucket.
4.  **Ingestion**: Snowflake Snowpipe (Auto-Ingest).
5.  **Transformation**: Snowflake Tasks (Merge/Deduplicate).

## Quick Start

### Prerequisites
*   Terraform >= 1.0
*   AWS Account
*   Snowflake Account

### Validation
Validate Terraform configuration:
```bash
cd terraform
terraform validate
```

### Security Scans
*   **Secrets**: Run `gitleaks detect` to ensure no credentials are committed.
*   **IaC Security**: Run `checkov -d terraform/` to scan for infrastructure misconfigurations.

### Setup
1.  **Configure Variables**: Copy `terraform/terraform.tfvars.example` to `terraform/terraform.tfvars`.
2.  **Deploy Infrastructure**: `terraform apply`.
3.  **Configure Aurora**: Enable logical replication for DMS CDC.
4.  **Deploy Snowflake Objects**: Run `scripts/setup_snowflake.sql`.

See [Developer Guide](docs/DEVELOPER_GUIDE.md) for detailed setup instructions.
