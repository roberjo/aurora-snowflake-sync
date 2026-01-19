"""Tests for data extraction."""

from datetime import datetime, timezone
from unittest.mock import MagicMock, patch

import pytest

from src.config import AuroraConfig, TableConfig
from src.extractor import DataExtractor


class TestDataExtractor:
    """Tests for DataExtractor."""

    @pytest.fixture
    def extractor(self, aurora_config, table_config):
        """Create a DataExtractor with mock connection."""
        return DataExtractor(aurora_config, table_config)

    def test_build_query_full_load(self, extractor):
        """Test query building for full load."""
        query, params = extractor.build_query(watermark=None)

        assert "SELECT" in query
        assert "FROM public.orders" in query
        assert "ORDER BY updated_at" in query
        assert "'I' AS op" in query
        assert params == {}

    def test_build_query_incremental(self, extractor):
        """Test query building for incremental load."""
        watermark = datetime(2024, 1, 15, 10, 0, 0, tzinfo=timezone.utc)
        query, params = extractor.build_query(watermark=watermark)

        assert "WHERE updated_at > %(watermark)s" in query
        assert params["watermark"] == watermark

    def test_build_query_with_created_at(self, aurora_config):
        """Test query building with created_at column."""
        table_config = TableConfig(
            table_name="ORDERS_CDC",
            source_schema="public",
            source_table="orders",
            source_columns=["order_id", "status", "updated_at"],
            watermark_column="updated_at",
            created_at_column="created_at",
        )

        extractor = DataExtractor(aurora_config, table_config)
        watermark = datetime(2024, 1, 15, 10, 0, 0, tzinfo=timezone.utc)
        query, _ = extractor.build_query(watermark)

        assert "CASE" in query
        assert "WHEN created_at = updated_at THEN 'I'" in query

    @patch("src.extractor.get_connection")
    def test_get_row_count_full(self, mock_get_conn, extractor):
        """Test row count for full load."""
        mock_conn = MagicMock()
        mock_cursor = MagicMock()
        mock_cursor.fetchone.return_value = (1000,)
        mock_conn.cursor.return_value.__enter__ = MagicMock(return_value=mock_cursor)
        mock_conn.cursor.return_value.__exit__ = MagicMock(return_value=False)
        mock_get_conn.return_value = mock_conn

        count = extractor.get_row_count()

        assert count == 1000
        mock_cursor.execute.assert_called_once()

    @patch("src.extractor.get_connection")
    def test_get_row_count_incremental(self, mock_get_conn, extractor):
        """Test row count for incremental load."""
        mock_conn = MagicMock()
        mock_cursor = MagicMock()
        mock_cursor.fetchone.return_value = (50,)
        mock_conn.cursor.return_value.__enter__ = MagicMock(return_value=mock_cursor)
        mock_conn.cursor.return_value.__exit__ = MagicMock(return_value=False)
        mock_get_conn.return_value = mock_conn

        watermark = datetime(2024, 1, 15, 10, 0, 0, tzinfo=timezone.utc)
        count = extractor.get_row_count(watermark)

        assert count == 50


class TestTableConfig:
    """Tests for TableConfig."""

    def test_full_table_name(self, table_config):
        """Test full table name property."""
        assert table_config.full_table_name == "public.orders"

    def test_default_batch_size(self):
        """Test default batch size."""
        config = TableConfig(
            table_name="TEST",
            source_schema="public",
            source_table="test",
            source_columns=["id"],
            watermark_column="updated_at",
        )
        assert config.batch_size == 10000
