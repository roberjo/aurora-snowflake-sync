"""Tests for watermark management."""

from datetime import datetime, timezone
from unittest.mock import MagicMock

import pytest
from botocore.exceptions import ClientError

from src.exceptions import WatermarkError
from src.watermark import WatermarkManager


class TestWatermarkManager:
    """Tests for WatermarkManager."""

    def test_get_watermark_exists(self):
        """Test getting an existing watermark."""
        mock_client = MagicMock()
        mock_client.get_item.return_value = {
            "Item": {
                "table_name": {"S": "ORDERS_CDC"},
                "watermark": {"S": "2024-01-15T10:00:00+00:00"},
                "rows_exported": {"N": "1000"},
            }
        }

        manager = WatermarkManager("test-table", mock_client)
        result = manager.get_watermark("ORDERS_CDC")

        assert result == datetime(2024, 1, 15, 10, 0, 0, tzinfo=timezone.utc)
        mock_client.get_item.assert_called_once()

    def test_get_watermark_not_exists(self):
        """Test getting watermark when none exists."""
        mock_client = MagicMock()
        mock_client.get_item.return_value = {}

        manager = WatermarkManager("test-table", mock_client)
        result = manager.get_watermark("NEW_TABLE")

        assert result is None

    def test_get_watermark_error(self):
        """Test error handling when getting watermark."""
        mock_client = MagicMock()
        mock_client.get_item.side_effect = ClientError(
            {"Error": {"Code": "InternalError", "Message": "Test error"}},
            "GetItem",
        )

        manager = WatermarkManager("test-table", mock_client)

        with pytest.raises(WatermarkError):
            manager.get_watermark("ORDERS_CDC")

    def test_update_watermark_first_run(self):
        """Test updating watermark on first run."""
        mock_client = MagicMock()

        manager = WatermarkManager("test-table", mock_client)
        new_wm = datetime(2024, 1, 15, 12, 0, 0, tzinfo=timezone.utc)

        manager.update_watermark(
            table_name="ORDERS_CDC",
            new_watermark=new_wm,
            rows_exported=500,
            execution_id="abc123",
            duration_seconds=30.5,
            previous_watermark=None,
        )

        mock_client.put_item.assert_called_once()
        call_args = mock_client.put_item.call_args
        assert call_args.kwargs["ConditionExpression"] == "attribute_not_exists(table_name)"

    def test_update_watermark_subsequent_run(self):
        """Test updating watermark with optimistic locking."""
        mock_client = MagicMock()

        manager = WatermarkManager("test-table", mock_client)
        prev_wm = datetime(2024, 1, 15, 10, 0, 0, tzinfo=timezone.utc)
        new_wm = datetime(2024, 1, 15, 12, 0, 0, tzinfo=timezone.utc)

        manager.update_watermark(
            table_name="ORDERS_CDC",
            new_watermark=new_wm,
            rows_exported=500,
            execution_id="abc123",
            duration_seconds=30.5,
            previous_watermark=prev_wm,
        )

        call_args = mock_client.put_item.call_args
        assert call_args.kwargs["ConditionExpression"] == "watermark = :prev"

    def test_update_watermark_concurrent_modification(self):
        """Test handling concurrent modification."""
        mock_client = MagicMock()
        mock_client.put_item.side_effect = ClientError(
            {"Error": {"Code": "ConditionalCheckFailedException", "Message": ""}},
            "PutItem",
        )

        manager = WatermarkManager("test-table", mock_client)
        prev_wm = datetime(2024, 1, 15, 10, 0, 0, tzinfo=timezone.utc)
        new_wm = datetime(2024, 1, 15, 12, 0, 0, tzinfo=timezone.utc)

        with pytest.raises(WatermarkError) as exc_info:
            manager.update_watermark(
                table_name="ORDERS_CDC",
                new_watermark=new_wm,
                rows_exported=500,
                execution_id="abc123",
                duration_seconds=30.5,
                previous_watermark=prev_wm,
            )

        assert "Concurrent modification" in str(exc_info.value)

    def test_get_state(self):
        """Test getting full state information."""
        mock_client = MagicMock()
        mock_client.get_item.return_value = {
            "Item": {
                "table_name": {"S": "ORDERS_CDC"},
                "watermark": {"S": "2024-01-15T10:00:00+00:00"},
                "rows_exported": {"N": "1000"},
                "execution_id": {"S": "abc123"},
                "duration_seconds": {"N": "30.5"},
                "updated_at": {"S": "2024-01-15T10:05:00+00:00"},
            }
        }

        manager = WatermarkManager("test-table", mock_client)
        state = manager.get_state("ORDERS_CDC")

        assert state["table_name"] == "ORDERS_CDC"
        assert state["rows_exported"] == 1000
        assert state["execution_id"] == "abc123"
        assert state["duration_seconds"] == 30.5
