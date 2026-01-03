# Repository Guidelines

## Project Structure & Module Organization
- `terraform/` defines infrastructure as code for AWS/Snowflake.
- `terraform/modules/dms/` provisions the DMS CDC pipeline.
- `scripts/` includes helper scripts (e.g., packaging and Snowflake setup).
- `docs/` contains architecture and operational documentation.

## Build, Test, and Development Commands
- `terraform validate` (from `terraform/`): validate IaC configuration.
- `make security`: run `checkov` and `gitleaks` scans.

## Coding Style & Naming Conventions
- Terraform uses 2-space indentation and is formatted with `terraform fmt`.
- Prefer descriptive, lowercase-with-hyphens names for AWS resources and DMS tasks.

## Testing Guidelines
- No automated tests are defined for the CDC infrastructure yet; validate with `terraform validate` and targeted smoke checks in Snowflake.

## Commit & Pull Request Guidelines
- Commit messages are short, imperative statements (e.g., “Add unit tests…”).
- Branch from `main`; use `feature/` branches for work in progress.
- PRs should include: summary, tests run, and doc updates for API changes.
- Ensure linting and tests pass; at least one approval is required.

## Security & Configuration Tips
- Secrets should never be committed; use `gitleaks detect --source . -v`.
- Run `checkov -d terraform/` before infra changes.
- Update `table_definitions` and DMS table mappings when adding tables.
