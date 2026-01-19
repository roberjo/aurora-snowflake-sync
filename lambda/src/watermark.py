"""DynamoDB watermark state management."""

import logging
from datetime import datetime, timezone
from decimal import Decimal
from typing import Any, Optional

import boto3
from botocore.exceptions import ClientError

from .exceptions import WatermarkError

logger = logging.getLogger(__name__)


class WatermarkManager:
    """Manages watermark state in DynamoDB with optimistic locking."""

    def __init__(self, table_name: str, dynamodb_client=None):
        """Initialize watermark manager.

        Args:
            table_name: DynamoDB table name for watermark storage.
            dynamodb_client: Optional boto3 DynamoDB client (for testing).
        """
        self.table_name = table_name
        self.dynamodb = dynamodb_client or boto3.client("dynamodb")

    def get_watermark(self, table_name: str) -> Optional[datetime]:
        """Get the current watermark for a table.

        Args:
            table_name: The table identifier (e.g., "ORDERS_CDC").

        Returns:
            The watermark datetime, or None if no watermark exists.
        """
        try:
            response = self.dynamodb.get_item(
                TableName=self.table_name,
                Key={"table_name": {"S": table_name}},
                ConsistentRead=True,
            )

            item = response.get("Item")
            if not item:
                logger.info("No watermark found for table %s, will do full load", table_name)
                return None

            watermark_str = item["watermark"]["S"]
            watermark = datetime.fromisoformat(watermark_str.replace("Z", "+00:00"))
            logger.info("Retrieved watermark for %s: %s", table_name, watermark)
            return watermark

        except ClientError as e:
            raise WatermarkError(f"Failed to get watermark: {e}") from e

    def update_watermark(
        self,
        table_name: str,
        new_watermark: datetime,
        rows_exported: int,
        execution_id: str,
        duration_seconds: float,
        previous_watermark: Optional[datetime] = None,
    ) -> None:
        """Update the watermark with optimistic locking.

        Args:
            table_name: The table identifier.
            new_watermark: The new watermark value.
            rows_exported: Number of rows exported in this run.
            execution_id: Unique execution identifier.
            duration_seconds: How long the export took.
            previous_watermark: Expected current watermark (for optimistic locking).
        """
        now = datetime.now(timezone.utc).isoformat()
        watermark_str = new_watermark.isoformat()

        item = {
            "table_name": {"S": table_name},
            "watermark": {"S": watermark_str},
            "rows_exported": {"N": str(rows_exported)},
            "execution_id": {"S": execution_id},
            "duration_seconds": {"N": str(Decimal(str(duration_seconds)))},
            "updated_at": {"S": now},
        }

        try:
            if previous_watermark is None:
                # First run - ensure we don't overwrite an existing watermark
                self.dynamodb.put_item(
                    TableName=self.table_name,
                    Item=item,
                    ConditionExpression="attribute_not_exists(table_name)",
                )
            else:
                # Update with optimistic locking
                previous_str = previous_watermark.isoformat()
                self.dynamodb.put_item(
                    TableName=self.table_name,
                    Item=item,
                    ConditionExpression="watermark = :prev",
                    ExpressionAttributeValues={":prev": {"S": previous_str}},
                )

            logger.info(
                "Updated watermark for %s: %s (exported %d rows)",
                table_name,
                new_watermark,
                rows_exported,
            )

        except ClientError as e:
            if e.response["Error"]["Code"] == "ConditionalCheckFailedException":
                raise WatermarkError(
                    f"Concurrent modification detected for {table_name}. "
                    "Another Lambda may have updated the watermark."
                ) from e
            raise WatermarkError(f"Failed to update watermark: {e}") from e

    def get_state(self, table_name: str) -> Optional[dict[str, Any]]:
        """Get full state information for a table.

        Args:
            table_name: The table identifier.

        Returns:
            Dict with watermark, rows_exported, execution_id, etc., or None.
        """
        try:
            response = self.dynamodb.get_item(
                TableName=self.table_name,
                Key={"table_name": {"S": table_name}},
                ConsistentRead=True,
            )

            item = response.get("Item")
            if not item:
                return None

            return {
                "table_name": item["table_name"]["S"],
                "watermark": datetime.fromisoformat(
                    item["watermark"]["S"].replace("Z", "+00:00")
                ),
                "rows_exported": int(item.get("rows_exported", {}).get("N", 0)),
                "execution_id": item.get("execution_id", {}).get("S"),
                "duration_seconds": float(item.get("duration_seconds", {}).get("N", 0)),
                "updated_at": item.get("updated_at", {}).get("S"),
            }

        except ClientError as e:
            raise WatermarkError(f"Failed to get state: {e}") from e
