# Aurora to Snowflake Sync

This project implements a serverless, batch-oriented data synchronization pipeline from AWS Aurora PostgreSQL to Snowflake.

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

1.  **Orchestrator**: AWS Lambda (triggered by EventBridge).
2.  **Extraction**: Aurora `aws_s3` extension exports incremental data to S3.
3.  **Staging**: S3 Bucket.
4.  **Ingestion**: Snowflake Snowpipe (Auto-Ingest).
5.  **Transformation**: Snowflake Tasks (Merge/Deduplicate).

## Quick Start

### Prerequisites
*   Terraform >= 1.0
*   AWS Account
*   Snowflake Account
*   Hashicorp Vault

### Quality & Security

### Testing
Run unit tests to verify logic:
```bash
pip install pytest
pytest tests/
```

### Validation
Validate Terraform configuration:
```bash
cd terraform
terraform validate
```

### Security Scans
*   **Secrets**: Run `gitleaks detect` to ensure no credentials are committed.
*   **IaC Security**: Run `checkov -d terraform/` to scan for infrastructure misconfigurations.

## Configuration

Edit `config/sync_config.json` to add tables:
```json
{
  "tables": [
    {
      "table_name": "public.orders",
      "watermark_col": "updated_at"
    }
  ]
}
```

### Setup
1.  **Configure Variables**: Copy `terraform/terraform.tfvars.example` to `terraform/terraform.tfvars`.
2.  **Deploy Infrastructure**: `terraform apply`.
3.  **Configure Aurora**: Enable `aws_s3` extension.
4.  **Deploy Snowflake Objects**: Run `scripts/setup_snowflake.sql`.

See [Developer Guide](docs/DEVELOPER_GUIDE.md) for detailed setup instructions.
