# GitHub Copilot Instructions - Aurora to Snowflake Sync

## Project Overview
This is a serverless data pipeline that syncs AWS Aurora PostgreSQL to Snowflake using Lambda, S3, and Snowpipe. The system is designed for batch processing (hourly/daily) with minimal infrastructure costs.

## Technology Stack
- **Python 3.9+**: Lambda functions
- **Terraform**: Infrastructure as Code
- **AWS Services**: Lambda, S3, EventBridge, VPC
- **Snowflake**: Storage Integration, Snowpipe, Tasks
- **Hashicorp Vault**: Secrets management

## Coding Standards

### Python
- **Style**: Follow PEP 8
- **Formatting**: Use `black` with default settings (88 char line length)
- **Linting**: Must pass `flake8` with max complexity 10
- **Type Hints**: Encouraged for function signatures
- **Docstrings**: Required for all public functions (Google style)
- **Error Handling**: Always wrap external calls (DB, API) in try-except with specific exceptions
- **Logging**: Use `print()` for Lambda (goes to CloudWatch). Include context (table name, timestamps)

### Terraform
- **Style**: Use `terraform fmt` for formatting
- **Naming**: Use lowercase with underscores (snake_case)
- **Modules**: Organize by logical component (network, compute, storage)
- **Variables**: Always provide descriptions and types
- **Outputs**: Document important resource identifiers
- **Security**: Never hardcode secrets; use Vault or AWS Secrets Manager

### SQL (Snowflake)
- **Style**: Uppercase keywords, lowercase identifiers
- **Naming**: Use UPPER_CASE for Snowflake objects (DATABASE, SCHEMA, TABLE)
- **Comments**: Document complex MERGE logic and business rules

## Architectural Patterns

### Lambda Function Design
- **Stateless**: Lambda should query Snowflake for watermarks, not maintain state
- **Idempotent**: Re-running the same sync should not cause data duplication
- **Timeout**: Design for 5-minute max execution
- **Error Handling**: Fail fast with clear error messages

### Security Principles
- **Least Privilege IAM**: Only grant necessary permissions
- **Secrets in Vault**: Never commit credentials or API keys
- **VPC Isolation**: Lambda in private subnet, egress through NAT
- **Encryption**: All data in transit (TLS 1.2+) and at rest (AES-256)

### Testing Requirements
- **Unit Tests**: Mock external dependencies (AWS, Snowflake, Vault)
- **Config Validation**: Test JSON schema validation
- **Error Paths**: Test failure scenarios (DB down, timeout, schema mismatch)

## Common Patterns to Follow

### When adding a new table:
1. Add entry to `config/sync_config.json`
2. Create Snowflake staging and final tables
3. Create Snowflake merge task
4. Update documentation

### When modifying Lambda code:
1. Update unit tests in `tests/`
2. Run `black` and `flake8` before commit
3. Test locally if possible (mock DB connections)
4. Update docstrings

### When changing infrastructure:
1. Run `terraform validate` and `terraform fmt`
2. Run `checkov -d terraform/` for security scan
3. Document changes in PR description
4. Plan before apply in production

## Anti-Patterns to Avoid
- ❌ Don't use `SELECT *` in production queries (specify columns)
- ❌ Don't commit `.tfvars` files with real credentials
- ❌ Don't use hardcoded table names or schemas (use config)
- ❌ Don't ignore exceptions or use bare `except:` clauses
- ❌ Don't create resources in default VPC
- ❌ Don't use `chmod 777` or overly permissive IAM policies

## File Naming Conventions
- Python modules: `lowercase_with_underscores.py`
- Terraform files: `resource_type.tf` (e.g., `lambda.tf`, `s3.tf`)
- Scripts: `verb_noun.sh` (e.g., `package_lambda.sh`)
- Docs: `UPPERCASE.md` (e.g., `RUNBOOK.md`)

## Dependencies
- Pin major versions in `requirements.txt` (e.g., `boto3>=1.26.0,<2.0.0`)
- Use Docker for Lambda packaging to ensure binary compatibility
- Test with actual dependency versions used in Lambda runtime

## When Suggesting Code
When GitHub Copilot suggests code for this project:
- Prefer simplicity over cleverness
- Include error handling and logging
- Follow the established patterns in existing code
- Suggest unit tests alongside implementation
- Consider the serverless execution environment (timeouts, memory limits)
