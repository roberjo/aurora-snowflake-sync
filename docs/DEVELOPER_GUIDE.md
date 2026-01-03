# Developer Guide

## Getting Started

### Prerequisites
*   **Terraform**: 1.0+
*   **AWS CLI**: Configured with dev credentials.
*   **SnowSQL**: For Snowflake interaction.

### Repository Structure
```
.
├── .github/                # GitHub Actions workflows
├── docs/                   # Documentation
├── terraform/
│   └── modules/
│       └── dms/             # DMS CDC resources
├── scripts/                # SQL and helper scripts
├── terraform/              # Infrastructure as Code
└── README.md
```

## Local Development

## Testing & Quality Assurance
No automated application tests are defined for the CDC pipeline. Validate changes via Terraform validation and Snowflake smoke checks.

### 2. Linting
Ensure Terraform is formatted with `terraform fmt` before opening a PR.

### 3. Terraform Validation
Validate the syntax and configuration of Infrastructure as Code.

**Run Validation:**
```bash
cd terraform
terraform init -backend=false
terraform validate
```

**Expected Output:**
```text
Success! The configuration is valid.
```

## Security Scanning

### 1. Vulnerability Scanning (Checkov)
We recommend using [Checkov](https://www.checkov.io/) to scan Terraform code for security misconfigurations.

**Installation:**
```bash
pip install checkov
```

**Run Scan:**
```bash
checkov -d terraform/
```

**Expected Output:**
Checkov will report passed/failed checks (e.g., ensuring S3 buckets are encrypted, Security Groups are restricted).

### 2. Secret Scanning (Gitleaks)
Prevent secrets from being committed using [Gitleaks](https://github.com/gitleaks/gitleaks).

**Installation:**
Follow instructions for your OS (e.g., `brew install gitleaks` or download binary).

**Run Scan:**
```bash
gitleaks detect --source . -v
```

**Expected Output:**
```text
    ○
    │╲
    │ ○
    ○ ░
    ░    gitleaks

NO LEAKS FOUND
```

## Branching Strategy
*   **main**: Production-ready code.
*   **develop**: Integration branch.
*   **feature/**: Feature branches.

Pull Requests require:
*   Passing CI checks (Lint, Test).
*   1 Approval.
