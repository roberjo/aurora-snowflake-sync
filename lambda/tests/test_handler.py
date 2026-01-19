"""Tests for Lambda handler."""

from datetime import datetime, timezone
from unittest.mock import MagicMock, patch

import pytest

from src.exceptions import ConfigurationError
from src.handler import check_timeout, handler


class TestCheckTimeout:
    """Tests for timeout checking."""

    def test_timeout_not_approaching(self):
        """Test when plenty of time remains."""
        context = MagicMock()
        context.get_remaining_time_in_millis.return_value = 300000  # 5 minutes

        assert check_timeout(context, 60) is False

    def test_timeout_approaching(self):
        """Test when timeout is approaching."""
        context = MagicMock()
        context.get_remaining_time_in_millis.return_value = 30000  # 30 seconds

        assert check_timeout(context, 60) is True

    def test_no_context(self):
        """Test with no context (local execution)."""
        assert check_timeout(None, 60) is False


class TestHandler:
    """Tests for main handler."""

    @patch("src.handler.build_config")
    @patch("src.handler.WatermarkManager")
    @patch("src.handler.DataExtractor")
    @patch("src.handler.S3ParquetWriter")
    def test_handler_no_rows(
        self, mock_writer_cls, mock_extractor_cls, mock_wm_cls, mock_build_config, lambda_config
    ):
        """Test handler when no rows to export."""
        mock_build_config.return_value = lambda_config

        mock_wm = MagicMock()
        mock_wm.get_watermark.return_value = datetime(2024, 1, 15, 10, 0, 0, tzinfo=timezone.utc)
        mock_wm_cls.return_value = mock_wm

        mock_extractor = MagicMock()
        mock_extractor.get_row_count.return_value = 0
        mock_extractor_cls.return_value = mock_extractor

        result = handler({"table_name": "ORDERS_CDC"}, None)

        assert result["statusCode"] == 200
        assert result["body"]["rows_exported"] == 0
        assert "No new rows" in result["body"]["message"]

    @patch("src.handler.build_config")
    @patch("src.handler.WatermarkManager")
    @patch("src.handler.DataExtractor")
    @patch("src.handler.S3ParquetWriter")
    def test_handler_with_rows(
        self,
        mock_writer_cls,
        mock_extractor_cls,
        mock_wm_cls,
        mock_build_config,
        lambda_config,
        sample_rows,
    ):
        """Test handler with data to export."""
        mock_build_config.return_value = lambda_config

        mock_wm = MagicMock()
        mock_wm.get_watermark.return_value = datetime(2024, 1, 15, 10, 0, 0, tzinfo=timezone.utc)
        mock_wm_cls.return_value = mock_wm

        mock_extractor = MagicMock()
        mock_extractor.get_row_count.return_value = 2
        mock_extractor.extract_batches.return_value = iter(
            [(sample_rows, datetime(2024, 1, 15, 11, 0, 0, tzinfo=timezone.utc))]
        )
        mock_extractor_cls.return_value = mock_extractor

        mock_writer = MagicMock()
        mock_writer.get_written_files.return_value = 1
        mock_writer_cls.return_value = mock_writer

        result = handler({"table_name": "ORDERS_CDC"}, None)

        assert result["statusCode"] == 200
        assert result["body"]["rows_exported"] == 2
        assert result["body"]["files_written"] == 1
        mock_wm.update_watermark.assert_called_once()

    @patch("src.handler.build_config")
    @patch("src.handler.WatermarkManager")
    @patch("src.handler.DataExtractor")
    @patch("src.handler.S3ParquetWriter")
    def test_handler_force_full_load(
        self, mock_writer_cls, mock_extractor_cls, mock_wm_cls, mock_build_config, lambda_config
    ):
        """Test handler with force full load."""
        mock_build_config.return_value = lambda_config

        mock_wm = MagicMock()
        mock_wm_cls.return_value = mock_wm

        mock_extractor = MagicMock()
        mock_extractor.get_row_count.return_value = 0
        mock_extractor_cls.return_value = mock_extractor

        handler({"table_name": "ORDERS_CDC", "force_full_load": True}, None)

        # Should not call get_watermark when force_full_load is True
        # Actually it still gets it but ignores it
        mock_extractor.get_row_count.assert_called_with(None)

    @patch("src.handler.build_config")
    @patch("src.handler.WatermarkManager")
    @patch("src.handler.DataExtractor")
    @patch("src.handler.S3ParquetWriter")
    def test_handler_dry_run(
        self,
        mock_writer_cls,
        mock_extractor_cls,
        mock_wm_cls,
        mock_build_config,
        lambda_config,
        sample_rows,
    ):
        """Test handler in dry run mode."""
        lambda_config.dry_run = True
        mock_build_config.return_value = lambda_config

        mock_wm = MagicMock()
        mock_wm.get_watermark.return_value = None
        mock_wm_cls.return_value = mock_wm

        mock_extractor = MagicMock()
        mock_extractor.get_row_count.return_value = 2
        mock_extractor.extract_batches.return_value = iter(
            [(sample_rows, datetime(2024, 1, 15, 11, 0, 0, tzinfo=timezone.utc))]
        )
        mock_extractor_cls.return_value = mock_extractor

        mock_writer = MagicMock()
        mock_writer.get_written_files.return_value = 0
        mock_writer_cls.return_value = mock_writer

        result = handler({"table_name": "ORDERS_CDC", "dry_run": True}, None)

        assert result["body"]["dry_run"] is True
        mock_writer.write_batch.assert_not_called()
        mock_wm.update_watermark.assert_not_called()

    def test_handler_missing_table_name(self):
        """Test handler with missing table_name."""
        with pytest.raises(ConfigurationError) as exc_info:
            handler({}, None)

        assert "table_name is required" in str(exc_info.value)

    @patch("src.handler.build_config")
    @patch("src.handler.WatermarkManager")
    @patch("src.handler.DataExtractor")
    @patch("src.handler.S3ParquetWriter")
    def test_handler_timeout_handling(
        self,
        mock_writer_cls,
        mock_extractor_cls,
        mock_wm_cls,
        mock_build_config,
        lambda_config,
        sample_rows,
    ):
        """Test handler graceful timeout handling."""
        mock_build_config.return_value = lambda_config

        mock_wm = MagicMock()
        mock_wm.get_watermark.return_value = None
        mock_wm_cls.return_value = mock_wm

        mock_extractor = MagicMock()
        mock_extractor.get_row_count.return_value = 1000

        # Return multiple batches
        def gen_batches():
            for i in range(10):
                yield (
                    sample_rows,
                    datetime(2024, 1, 15, 10 + i, 0, 0, tzinfo=timezone.utc),
                )

        mock_extractor.extract_batches.return_value = gen_batches()
        mock_extractor_cls.return_value = mock_extractor

        mock_writer = MagicMock()
        mock_writer.get_written_files.return_value = 1
        mock_writer_cls.return_value = mock_writer

        # Create a context that will trigger timeout after first batch
        context = MagicMock()
        call_count = [0]

        def remaining_time():
            call_count[0] += 1
            if call_count[0] > 1:
                return 30000  # 30 seconds - triggers timeout
            return 300000  # 5 minutes

        context.get_remaining_time_in_millis = remaining_time

        result = handler({"table_name": "ORDERS_CDC"}, context)

        assert result["body"]["timeout_reached"] is True
        assert "Partial export" in result["body"]["message"]
