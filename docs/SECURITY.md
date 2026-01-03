# Security Architecture

## Authentication & Authorization

### AWS IAM
*   **DMS Role**:
    *   `s3:PutObject`: Only to the specific Data Lake bucket.
    *   `s3:ListBucket`, `s3:GetBucketLocation`: Required for S3 target access.
*   **Snowflake Role (AWS)**:
    *   `s3:GetObject`, `s3:ListBucket`: Strictly scoped to the Data Lake bucket.

### Database Authentication
*   **Aurora**: DMS uses a dedicated replication username/password (prefer AWS Secrets Manager).
*   **Snowflake**: Uses Key Pair authentication or Username/Password for the Snowflake provider.

## Network Security
*   **VPC**: DMS runs in private subnets.
*   **Security Groups**:
    *   **DMS SG**: Egress to Aurora (5432), Egress to HTTPS (443) for AWS APIs/S3.
    *   **Aurora SG**: Ingress from DMS SG only.
*   **Encryption**:
    *   **In-Transit**: TLS 1.2+ for all connections (Aurora, Snowflake, S3).
    *   **At-Rest**:
        *   S3: SSE-S3 or SSE-KMS.
        *   Aurora: EBS Encryption (KMS).
        *   Snowflake: Managed encryption.

## Secrets Management
*   **Tool**: AWS Secrets Manager (recommended).
*   **Rotation**: Rotate replication credentials every 90 days and update DMS endpoint credentials.

## Compliance
*   **Audit Logging**:
    *   AWS CloudTrail enabled for all API calls.
    *   Snowflake Access History enabled.
*   **PII Data**: If syncing PII, ensure S3 bucket policies restrict access and Snowflake Column Level Security (Masking Policies) is applied in the Final tables.
