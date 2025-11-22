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

### 2. Running Tests
Unit tests are located in `tests/` (create if missing).
```bash
pytest
```

### 3. Linting & Formatting
We use `black` for formatting and `flake8` for linting.
```bash
black lambda/
flake8 lambda/
```

### 4. Local Lambda Invocation
You can use `python-lambda-local` to test the handler locally, provided you have set up the necessary environment variables and network access (VPN/Tunnel) to the database.
```bash
export VAULT_ADDR="https://vault.example.com"
export VAULT_TOKEN="dev-token"
python-lambda-local -f lambda_handler lambda/exporter.py event.json
```

## Adding New Tables
1.  **Update Config**: Add the table definition to `config/sync_config.json`.
    ```json
    {
      "table_name": "public.new_table",
      "watermark_col": "updated_at"
    }
    ```
2.  **Snowflake Setup**:
    *   Create the target table in Snowflake.
    *   Create the staging table.
    *   Create the Merge Task (see `scripts/setup_snowflake.sql`).

## Infrastructure Changes
1.  Navigate to `terraform/`.
2.  Make changes to `.tf` files.
3.  Validate: `terraform validate`.
4.  Format: `terraform fmt -recursive`.
5.  Plan: `terraform plan`.

## Branching Strategy
*   **main**: Production-ready code.
*   **develop**: Integration branch.
*   **feature/**: Feature branches.

Pull Requests require:
*   Passing CI checks (Lint, Test).
*   1 Approval.
