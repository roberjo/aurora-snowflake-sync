# Antigravity Agent Instructions

## Project Overview
This is the **Aurora to Snowflake Sync** project - a production-grade, serverless data pipeline for batch synchronization from AWS Aurora PostgreSQL to Snowflake Data Lake.

### Architecture
```
EventBridge → Lambda (Python) → Aurora (aws_s3 export) → S3 → Snowpipe → Snowflake
```

### Key Components
- **Orchestrator:** AWS Lambda (Python 3.9+)
- **Infrastructure:** Terraform Cloud
- **Secrets:** Hashicorp Vault
- **Sync Frequency:** Hourly/Daily (configurable via EventBridge)
- **Data Flow:** Incremental (watermark-based via `updated_at` column)

## Development Standards

### Python (Lambda Functions)
**Required Tools:**
- Formatter: `black` (88 char line length)
- Linter: `flake8` (max complexity 10)
- Testing: `pytest` with mocking

**Code Patterns:**
```python
# ✅ Good: With context manager, specific exception, logging
try:
    with psycopg2.connect(**db_params) as conn:
        cur = conn.cursor()
        cur.execute(query)
        print(f"Exported {table_name} to S3")
except psycopg2.OperationalError as e:
    print(f"Export failed for {table_name}: {e}")
    raise

# ❌ Bad: No cleanup, bare except, silent failure
try:
    conn = psycopg2.connect(**db_params)
    cur = conn.cursor()
    cur.execute(query)
except:
    pass
```

**Function Documentation:**
```python
def function_name(param1: type1, param2: type2) -> return_type:
    """
    Brief one-line description.
    
    Longer description if needed. Explain the "why" and any
    non-obvious behavior.
    
    Args:
        param1: Description of param1
        param2: Description of param2
        
    Returns:
        Description of return value
        
    Raises:
        ExceptionType: When this specific error occurs
    """
```

### Terraform (Infrastructure)
**Organization:**
- Root: `main.tf`, `variables.tf`, `outputs.tf`
- Modules: `modules/<component>/<resource>.tf`

**Standards:**
```hcl
# Always include:
# 1. Type and description for variables
variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

# 2. Tags for all resources
resource "aws_s3_bucket" "data_lake" {
  tags = {
    Name        = "${var.project_name}-datalake"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# 3. Sensitive flag for secrets
variable "vault_token" {
  type      = string
  sensitive = true
}
```

### SQL (Snowflake)
**Style:**
- Keywords: UPPERCASE (`SELECT`, `MERGE`, `UPDATE`)
- Objects: UPPERCASE (`PUBLIC.ORDERS`)
- Columns: lowercase (`order_id`, `updated_at`)

## Security Requirements

### Critical Rules
1. **Never commit secrets** - Check with `gitleaks detect`
2. **All credentials in Vault** - No hardcoded passwords, tokens, API keys
3. **Least privilege IAM** - Only grant necessary permissions
4. **Validate input** - Sanitize all external input (config files, user input)
5. **Encrypt everything** - TLS 1.2+ (transit), AES-256 (at rest)

### Security Scans
Run before every commit:
```bash
gitleaks detect --source . -v
checkov -d terraform/
```

## Testing Strategy

### Unit Tests
**Location:** `tests/` (mirrors `lambda/` structure)
**Coverage:** All business logic, error paths, edge cases

**Pattern:**
```python
@patch('exporter.external_dependency')
def test_descriptive_name(mock_dependency):
    # Arrange: Setup mocks and test data
    mock_dependency.return_value = expected_value
    
    # Act: Execute function under test
    result = function_under_test(input_data)
    
    # Assert: Verify outcome
    assert result == expected_outcome
    mock_dependency.assert_called_once()
```

### Running Tests
```bash
pytest tests/                    # Run all tests
pytest tests/test_exporter.py   # Run specific file
pytest -v                        # Verbose output
```

## Common Workflows

### Workflow 1: Adding a New Table to Sync
1. **Config:** Add to `config/sync_config.json`
   ```json
   {
     "table_name": "public.new_table",
     "watermark_col": "updated_at",
     "primary_key": "id"
   }
   ```
2. **Snowflake:** Create staging and final tables
3. **Snowflake:** Create merge task (see `scripts/setup_snowflake.sql`)
4. **Test:** Trigger Lambda manually, verify data flow

### Workflow 2: Modifying Lambda Function
1. **Code:** Make changes to `lambda/exporter.py`
2. **Tests:** Update/add tests in `tests/test_exporter.py`
3. **Lint:** Run `black lambda/ && flake8 lambda/`
4. **Test:** Run `pytest tests/`
5. **Package:** Run `make package` (uses Docker for binary compatibility)

### Workflow 3: Infrastructure Changes
1. **Edit:** Modify `.tf` files in `terraform/` or `terraform/modules/`
2. **Format:** Run `terraform fmt -recursive`
3. **Validate:** Run `terraform validate`
4. **Security:** Run `checkov -d terraform/`
5. **Plan:** Run `terraform plan` (review changes)
6. **Apply:** Run `terraform apply` (after approval)

## File Structure Context

```
.
├── .github/                    # CI/CD, PR templates, code review guidelines
│   ├── workflows/ci.yml       # GitHub Actions (lint, test, package)
│   ├── CODE_REVIEW_GUIDELINES.md
│   └── CODING_STANDARDS.md
├── config/
│   └── sync_config.json       # Tables to sync (read by Lambda)
├── docs/                      # Architecture, runbooks, security
├── lambda/
│   ├── exporter.py           # Main Lambda handler
│   └── requirements.txt      # Python dependencies
├── scripts/
│   ├── package_lambda.sh     # Docker-based packaging for Lambda
│   └── setup_snowflake.sql   # Snowflake initialization
├── terraform/
│   ├── main.tf               # Root module
│   ├── modules/              # Network, Compute, Storage, Snowflake
│   └── *.tf                  # Variables, outputs
└── tests/                     # Unit tests (pytest)
```

## Performance Considerations

### Lambda Limits
- **Timeout:** 5 minutes (design for < 4 min to allow buffer)
- **Memory:** 3GB default (increase if processing large exports)
- **Payload:** 6MB max (use S3 for larger data)

### Aurora Export Optimization
- Export runs **on Aurora engine** (not Lambda) - no memory limits
- Use `aws_s3` extension for fast, parallel writes to S3
- Watermark queries should use indexed columns

### Snowflake Optimization
- Snowpipe auto-scales for file ingestion
- Merge tasks can use larger warehouses for big batches
- Use clustering keys for large tables (>1TB)

## Debugging Tips

### Lambda Not Running
1. Check EventBridge rule: `aws events describe-rule --name <rule-name>`
2. Check Lambda permissions: Ensure EventBridge can invoke
3. Check CloudWatch Logs: `/aws/lambda/aurora-snowflake-sync-exporter`

### Export Failing
1. Check Aurora logs for errors
2. Verify IAM role attached to Aurora cluster (for S3 write)
3. Check S3 bucket permissions
4. Verify watermark query doesn't return NULL (use fallback)

### Snowpipe Not Loading
1. Check S3 event notifications: `aws s3api get-bucket-notification-configuration`
2. Check Snowpipe status: `SELECT SYSTEM$PIPE_STATUS('DB.SCHEMA.PIPE');`
3. Check COPY_HISTORY: `SELECT * FROM TABLE(INFORMATION_SCHEMA.COPY_HISTORY(...));`

## Code Review Checklist

When reviewing PRs:
- [ ] Tests added/updated and passing
- [ ] `black` and `flake8` passing
- [ ] No secrets in code or git history
- [ ] Terraform validates and formats
- [ ] Checkov security scan passing
- [ ] Documentation updated (if needed)
- [ ] Error handling for external calls
- [ ] Logging includes context (table names, timestamps)

## Anti-Patterns to Flag

If you see these in code review, request changes:
- `SELECT *` in production queries
- Hardcoded credentials, endpoints, table names
- Bare `except:` (use specific exceptions)
- Missing error handling on DB/API calls
- Committing `.tfvars` with real secrets
- Creating resources in default VPC
- Lambda functions without timeouts on external calls

## Resources
- [Architecture](docs/ARCHITECTURE.md)
- [Developer Guide](docs/DEVELOPER_GUIDE.md)
- [Runbook](docs/RUNBOOK.md)
- [Security](docs/SECURITY.md)
