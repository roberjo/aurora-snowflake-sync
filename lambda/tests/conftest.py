"""Pytest fixtures for CDC Lambda tests."""

import os
from datetime import datetime, timezone
from unittest.mock import MagicMock, patch

import pytest

from src.config import AuroraConfig, LambdaConfig, S3Config, TableConfig


@pytest.fixture
def aurora_config():
    """Sample Aurora configuration."""
    return AuroraConfig(
        host="test-aurora.cluster.us-east-1.rds.amazonaws.com",
        port=5432,
        database="testdb",
        username="testuser",
        password="testpass",
    )


@pytest.fixture
def table_config():
    """Sample table configuration."""
    return TableConfig(
        table_name="ORDERS_CDC",
        source_schema="public",
        source_table="orders",
        source_columns=["order_id", "customer_id", "status", "updated_at"],
        watermark_column="updated_at",
        created_at_column="created_at",
        batch_size=1000,
        s3_prefix="cdc",
    )


@pytest.fixture
def s3_config():
    """Sample S3 configuration."""
    return S3Config(
        bucket="test-bucket",
        prefix="cdc",
        kms_key_id=None,
    )


@pytest.fixture
def lambda_config(aurora_config, table_config, s3_config):
    """Complete Lambda configuration."""
    return LambdaConfig(
        aurora=aurora_config,
        table=table_config,
        s3=s3_config,
        dynamodb_table="test-watermarks",
        timeout_buffer_seconds=60,
        dry_run=False,
    )


@pytest.fixture
def sample_rows():
    """Sample data rows."""
    return [
        {
            "order_id": 1,
            "customer_id": 100,
            "status": "pending",
            "updated_at": datetime(2024, 1, 15, 10, 0, 0, tzinfo=timezone.utc),
            "commit_ts": datetime(2024, 1, 15, 10, 0, 0, tzinfo=timezone.utc),
            "op": "I",
        },
        {
            "order_id": 2,
            "customer_id": 101,
            "status": "shipped",
            "updated_at": datetime(2024, 1, 15, 11, 0, 0, tzinfo=timezone.utc),
            "commit_ts": datetime(2024, 1, 15, 11, 0, 0, tzinfo=timezone.utc),
            "op": "U",
        },
    ]


@pytest.fixture
def mock_dynamodb():
    """Mock DynamoDB client."""
    with patch("boto3.client") as mock:
        client = MagicMock()
        mock.return_value = client
        yield client


@pytest.fixture
def mock_s3():
    """Mock S3 client."""
    client = MagicMock()
    return client


@pytest.fixture
def env_vars():
    """Set required environment variables."""
    env = {
        "AURORA_HOST": "test-aurora.cluster.us-east-1.rds.amazonaws.com",
        "AURORA_PORT": "5432",
        "AURORA_DATABASE": "testdb",
        "AURORA_SECRET_ARN": "arn:aws:secretsmanager:us-east-1:123456789012:secret:test",
        "SOURCE_SCHEMA": "public",
        "SOURCE_TABLE": "orders",
        "SOURCE_COLUMNS": "order_id,customer_id,status,updated_at",
        "WATERMARK_COLUMN": "updated_at",
        "S3_BUCKET": "test-bucket",
        "S3_PREFIX": "cdc",
        "DYNAMODB_TABLE": "test-watermarks",
    }
    with patch.dict(os.environ, env):
        yield env
