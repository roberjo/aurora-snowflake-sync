# Security Architecture

## Authentication & Authorization

### AWS IAM
*   **Lambda Role**:
    *   `s3:PutObject`: Only to the specific Data Lake bucket.
    *   `secretsmanager:GetSecretValue` (or Vault access): Only for specific DB credentials.
    *   `ec2:CreateNetworkInterface`: For VPC access.
*   **Snowflake Role (AWS)**:
    *   `s3:GetObject`, `s3:ListBucket`: Strictly scoped to the Data Lake bucket.

### Database Authentication
*   **Aurora**: Lambda uses username/password retrieved from Vault. (Future: IAM Auth).
*   **Snowflake**: Lambda uses Key Pair authentication or Username/Password from Vault.

## Network Security
*   **VPC**: Lambda runs in a private subnet.
*   **Security Groups**:
    *   **Lambda SG**: Egress to Aurora (5432), Egress to HTTPS (443) for AWS APIs/Vault.
    *   **Aurora SG**: Ingress from Lambda SG only.
*   **Encryption**:
    *   **In-Transit**: TLS 1.2+ for all connections (Aurora, Snowflake, S3).
    *   **At-Rest**:
        *   S3: SSE-S3 or SSE-KMS.
        *   Aurora: EBS Encryption (KMS).
        *   Snowflake: Managed encryption.

## Secrets Management
*   **Tool**: Hashicorp Vault (Enterprise Standard).
*   **Path**: `secret/data/aurora-snowflake-sync/*`
*   **Rotation**: Credentials should be rotated every 90 days. The Lambda fetches secrets dynamically, so no redeployment is needed upon rotation.

## Compliance
*   **Audit Logging**:
    *   AWS CloudTrail enabled for all API calls.
    *   Snowflake Access History enabled.
*   **PII Data**: If syncing PII, ensure S3 bucket policies restrict access and Snowflake Column Level Security (Masking Policies) is applied in the Final tables.
