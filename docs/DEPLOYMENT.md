# Deployment Strategy

## CI/CD Pipeline Overview

We use a hybrid approach:
1.  **GitHub Actions**: For Continuous Integration (Build, Test, Lint, Package).
2.  **Harness**: For Continuous Delivery (Infrastructure Deployment, Lambda Deployment).

## GitHub Actions Workflow
File: `.github/workflows/ci.yml`

### Stages
1.  **Checkout**: Pull code.
2.  **Setup Python**: Install dependencies.
3.  **Lint**: Run `flake8` and `black --check`.
4.  **Test**: Run `pytest` with coverage.
5.  **Package**:
    *   Create a ZIP file of the `lambda/` directory and dependencies.
    *   Upload artifact to S3 (Build Artifact Bucket) or JFrog Artifactory.
6.  **Terraform Validate**: Run `terraform validate` to check IaC syntax.

## Harness Pipeline
Harness orchestrates the deployment to Dev, Stage, and Prod environments.

### Pipeline Stages
1.  **Infrastructure (Terraform)**:
    *   Harness pulls the Terraform code.
    *   Runs `terraform plan`.
    *   **Manual Approval** (Prod only).
    *   Runs `terraform apply`.
2.  **Lambda Code Update**:
    *   Harness pulls the ZIP artifact from S3/Artifactory.
    *   Updates the Lambda function code using AWS API or Terraform `aws_lambda_function` update.

## Lambda Packaging
To ensure all dependencies (like `psycopg2` binary) work on AWS Lambda (Amazon Linux 2), we use Docker for packaging.

### Packaging Script
```bash
# scripts/package_lambda.sh
docker run --rm -v $(pwd):/var/task public.ecr.aws/sam/build-python3.9:latest /bin/sh -c "pip install -r lambda/python/requirements.txt -t lambda/python/ && cd lambda/python && zip -r ../../terraform/modules/compute/exporter.zip ."
```

## Environment Strategy
*   **DEV**: Deploys on every commit to `develop`.
*   **STAGE**: Deploys on release tags.
*   **PROD**: Deploys on approval of STAGE verification.

## Rollback
*   **Infrastructure**: `terraform apply` the previous state.
*   **Code**: Harness can roll back the Lambda to the previous version/alias.
