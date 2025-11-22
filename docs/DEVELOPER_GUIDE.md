# Developer Guide

## Getting Started

### Prerequisites
*   **Python**: 3.9+
*   **Terraform**: 1.0+
*   **Docker**: For local Lambda testing (optional).
*   **AWS CLI**: Configured with dev credentials.
*   **SnowSQL**: For Snowflake interaction.

### Repository Structure
```
.
├── .github/                # GitHub Actions workflows
├── config/                 # Application configuration
├── docs/                   # Documentation
├── lambda/                 # Python source code
│   ├── exporter.py
│   └── requirements.txt
├── scripts/                # SQL and helper scripts
├── terraform/              # Infrastructure as Code
└── README.md
```

## Local Development

### 1. Environment Setup
Create a virtual environment for Python development:
```bash
python -m venv venv
source venv/bin/activate  # Windows: venv\Scripts\activate
pip install -r lambda/requirements.txt
pip install pytest black flake8
```

## Testing & Quality Assurance

### 1. Unit Tests
We use `pytest` for unit testing the Python Lambda code.

**Run Tests:**
```bash
pytest tests/
```

**Expected Output:**
```text
================= test session starts ==================
platform win32 -- Python 3.9.x, pytest-7.x, pluggy-1.x
rootdir: D:\Github\aurora-snowflake-sync
collected 5 items

tests\test_config.py .                                   [ 20%]
tests\test_exporter.py ....                              [100%]

================== 5 passed in 0.45s ===================
```

### 2. Linting
Ensure code quality with `flake8` (logic) and `black` (formatting).

**Run Linting:**
```bash
flake8 lambda/
black --check lambda/
```

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
