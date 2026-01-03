# Deployment Strategy

## CI/CD Pipeline Overview

We use a hybrid approach:
1.  **GitHub Actions**: For Continuous Integration (Build, Test, Lint, Package).
2.  **Harness**: For Continuous Delivery (Infrastructure Deployment, DMS Task updates).

## GitHub Actions Workflow
File: `.github/workflows/ci.yml`

### Stages
1.  **Checkout**: Pull code.
2.  **Setup Python**: Install dependencies.
3.  **Lint**: Run `flake8` and `black --check`.
4.  **Test**: Run `pytest` with coverage.
5.  **Terraform Validate**: Run `terraform validate` to check IaC syntax.

## Harness Pipeline
Harness orchestrates the deployment to Dev, Stage, and Prod environments.

### Pipeline Stages
1.  **Infrastructure (Terraform)**:
    *   Harness pulls the Terraform code.
    *   Runs `terraform plan`.
    *   **Manual Approval** (Prod only).
    *   Runs `terraform apply`.
2.  **DMS Task Updates**:
    *   Apply updated task settings or table mappings via Terraform.
    *   Validate DMS task state (Running) after deploy.

## Environment Strategy
*   **DEV**: Deploys on every commit to `develop`.
*   **STAGE**: Deploys on release tags.
*   **PROD**: Deploys on approval of STAGE verification.

## Rollback
*   **Infrastructure**: `terraform apply` the previous state.
*   **Replication**: Revert DMS task settings or reload tables as needed.
