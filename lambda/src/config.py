"""Configuration dataclasses for the CDC Lambda export."""

import os
from dataclasses import dataclass, field
from typing import Optional

from .exceptions import ConfigurationError


@dataclass
class AuroraConfig:
    """Aurora PostgreSQL connection configuration."""

    host: str
    port: int
    database: str
    username: str
    password: str
    ssl_mode: str = "require"

    @classmethod
    def from_secret(cls, secret: dict, host: str, port: int, database: str) -> "AuroraConfig":
        """Create config from Secrets Manager secret."""
        return cls(
            host=host,
            port=port,
            database=database,
            username=secret["username"],
            password=secret["password"],
        )


@dataclass
class TableConfig:
    """Configuration for a single table export."""

    table_name: str
    source_schema: str
    source_table: str
    source_columns: list[str]
    watermark_column: str
    created_at_column: Optional[str] = None
    batch_size: int = 10000
    s3_prefix: str = "cdc"

    @property
    def full_table_name(self) -> str:
        """Return fully qualified table name."""
        return f"{self.source_schema}.{self.source_table}"


@dataclass
class S3Config:
    """S3 output configuration."""

    bucket: str
    prefix: str = "cdc"
    kms_key_id: Optional[str] = None


@dataclass
class LambdaConfig:
    """Overall Lambda configuration."""

    aurora: AuroraConfig
    table: TableConfig
    s3: S3Config
    dynamodb_table: str
    timeout_buffer_seconds: int = 60
    dry_run: bool = False

    @classmethod
    def from_env(cls) -> "LambdaConfig":
        """Create config from environment variables.

        This requires the Aurora secret to be fetched separately.
        """
        required_vars = [
            "AURORA_HOST",
            "AURORA_PORT",
            "AURORA_DATABASE",
            "SOURCE_SCHEMA",
            "SOURCE_TABLE",
            "SOURCE_COLUMNS",
            "WATERMARK_COLUMN",
            "S3_BUCKET",
            "S3_PREFIX",
            "DYNAMODB_TABLE",
        ]

        missing = [v for v in required_vars if not os.environ.get(v)]
        if missing:
            raise ConfigurationError(f"Missing required environment variables: {missing}")

        # Aurora config will be populated later with secrets
        aurora = AuroraConfig(
            host=os.environ["AURORA_HOST"],
            port=int(os.environ["AURORA_PORT"]),
            database=os.environ["AURORA_DATABASE"],
            username="",  # Populated from Secrets Manager
            password="",  # Populated from Secrets Manager
        )

        columns = [c.strip() for c in os.environ["SOURCE_COLUMNS"].split(",")]

        table = TableConfig(
            table_name=os.environ.get("TABLE_NAME", os.environ["SOURCE_TABLE"].upper() + "_CDC"),
            source_schema=os.environ["SOURCE_SCHEMA"],
            source_table=os.environ["SOURCE_TABLE"],
            source_columns=columns,
            watermark_column=os.environ["WATERMARK_COLUMN"],
            created_at_column=os.environ.get("CREATED_AT_COLUMN"),
            batch_size=int(os.environ.get("BATCH_SIZE", "10000")),
            s3_prefix=os.environ["S3_PREFIX"],
        )

        s3 = S3Config(
            bucket=os.environ["S3_BUCKET"],
            prefix=os.environ["S3_PREFIX"],
            kms_key_id=os.environ.get("KMS_KEY_ID"),
        )

        return cls(
            aurora=aurora,
            table=table,
            s3=s3,
            dynamodb_table=os.environ["DYNAMODB_TABLE"],
            timeout_buffer_seconds=int(os.environ.get("TIMEOUT_BUFFER_SECONDS", "60")),
            dry_run=os.environ.get("DRY_RUN", "false").lower() == "true",
        )
