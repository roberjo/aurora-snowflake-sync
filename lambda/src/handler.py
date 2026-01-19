"""Lambda handler for Aurora to S3 CDC export."""

import json
import logging
import os
import time
import uuid
from datetime import datetime, timezone
from typing import Any, Optional

import boto3

from .config import AuroraConfig, LambdaConfig, S3Config, TableConfig
from .exceptions import (
    CDCExportError,
    ConfigurationError,
    TimeoutApproachingError,
)
from .extractor import DataExtractor, close_connection
from .watermark import WatermarkManager
from .writer import S3ParquetWriter

logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Cache for secrets
_cached_secret: Optional[dict] = None


def get_aurora_secret(secret_arn: str) -> dict:
    """Retrieve Aurora credentials from Secrets Manager.

    Args:
        secret_arn: ARN of the secret.

    Returns:
        Dict with username and password.
    """
    global _cached_secret

    if _cached_secret is not None:
        return _cached_secret

    client = boto3.client("secretsmanager")
    response = client.get_secret_value(SecretId=secret_arn)
    _cached_secret = json.loads(response["SecretString"])
    return _cached_secret


def build_config(event: dict[str, Any]) -> LambdaConfig:
    """Build configuration from environment and event.

    Args:
        event: Lambda event payload.

    Returns:
        Complete LambdaConfig object.
    """
    # Get base config from environment
    config = LambdaConfig.from_env()

    # Override with event parameters
    if "batch_size" in event:
        config.table.batch_size = int(event["batch_size"])

    if "dry_run" in event:
        config.dry_run = event["dry_run"]

    # Get Aurora credentials from Secrets Manager
    secret_arn = os.environ.get("AURORA_SECRET_ARN")
    if not secret_arn:
        raise ConfigurationError("AURORA_SECRET_ARN environment variable not set")

    secret = get_aurora_secret(secret_arn)
    config.aurora.username = secret["username"]
    config.aurora.password = secret["password"]

    return config


def check_timeout(context, buffer_seconds: int) -> bool:
    """Check if Lambda timeout is approaching.

    Args:
        context: Lambda context object.
        buffer_seconds: Seconds to reserve before timeout.

    Returns:
        True if timeout is approaching.
    """
    if context is None:
        return False

    remaining_ms = context.get_remaining_time_in_millis()
    return remaining_ms < (buffer_seconds * 1000)


def handler(event: dict[str, Any], context: Any) -> dict[str, Any]:
    """Lambda entry point for CDC export.

    Event parameters:
        table_name: Table identifier (required, e.g., "ORDERS_CDC")
        force_full_load: If true, ignore existing watermark (optional)
        batch_size: Override batch size (optional)
        dry_run: If true, extract but don't write (optional)

    Args:
        event: Lambda event payload.
        context: Lambda context object.

    Returns:
        Dict with export results.
    """
    start_time = time.time()
    execution_id = str(uuid.uuid4())[:8]

    logger.info("Starting CDC export, execution_id=%s, event=%s", execution_id, event)

    # Validate event
    table_name = event.get("table_name")
    if not table_name:
        raise ConfigurationError("table_name is required in event payload")

    force_full_load = event.get("force_full_load", False)

    try:
        # Build configuration
        config = build_config(event)

        # Initialize components
        watermark_mgr = WatermarkManager(config.dynamodb_table)
        extractor = DataExtractor(config.aurora, config.table)
        writer = S3ParquetWriter(config.s3, config.table, execution_id)

        # Get current watermark
        if force_full_load:
            logger.info("Force full load requested, ignoring existing watermark")
            watermark = None
            previous_watermark = None
        else:
            watermark = watermark_mgr.get_watermark(table_name)
            previous_watermark = watermark

        # Count rows to export
        row_count = extractor.get_row_count(watermark)
        logger.info("Found %d rows to export for %s", row_count, table_name)

        if row_count == 0:
            return {
                "statusCode": 200,
                "body": {
                    "table_name": table_name,
                    "rows_exported": 0,
                    "files_written": 0,
                    "execution_id": execution_id,
                    "message": "No new rows to export",
                },
            }

        # Export in batches
        total_rows = 0
        max_watermark = watermark
        timeout_reached = False

        for batch, batch_max_wm in extractor.extract_batches(watermark):
            # Check timeout
            if check_timeout(context, config.timeout_buffer_seconds):
                logger.warning(
                    "Timeout approaching after %d rows, stopping gracefully",
                    total_rows,
                )
                timeout_reached = True
                break

            # Write batch
            if not config.dry_run:
                writer.write_batch(batch)
            else:
                logger.info("Dry run: would write %d rows", len(batch))

            total_rows += len(batch)

            # Track max watermark
            if batch_max_wm and (max_watermark is None or batch_max_wm > max_watermark):
                max_watermark = batch_max_wm

            logger.info("Processed %d/%d rows", total_rows, row_count)

        # Update watermark
        duration = time.time() - start_time

        if total_rows > 0 and max_watermark and not config.dry_run:
            watermark_mgr.update_watermark(
                table_name=table_name,
                new_watermark=max_watermark,
                rows_exported=total_rows,
                execution_id=execution_id,
                duration_seconds=duration,
                previous_watermark=previous_watermark,
            )

        result = {
            "statusCode": 200,
            "body": {
                "table_name": table_name,
                "rows_exported": total_rows,
                "files_written": writer.get_written_files(),
                "execution_id": execution_id,
                "duration_seconds": round(duration, 2),
                "new_watermark": max_watermark.isoformat() if max_watermark else None,
                "timeout_reached": timeout_reached,
                "dry_run": config.dry_run,
            },
        }

        if timeout_reached:
            result["body"]["message"] = "Partial export due to timeout"

        logger.info("CDC export completed: %s", result["body"])
        return result

    except CDCExportError as e:
        logger.error("CDC export failed: %s", str(e))
        raise

    except Exception as e:
        logger.exception("Unexpected error during CDC export")
        raise CDCExportError(f"Unexpected error: {e}") from e

    finally:
        # Don't close connection - keep it for warm starts
        pass


def lambda_handler(event: dict[str, Any], context: Any) -> dict[str, Any]:
    """AWS Lambda entry point."""
    return handler(event, context)
