"""Tests for S3 Parquet writer."""

from datetime import datetime, timezone
from unittest.mock import MagicMock

import pytest

from src.exceptions import WriterError
from src.writer import S3ParquetWriter


class TestS3ParquetWriter:
    """Tests for S3ParquetWriter."""

    @pytest.fixture
    def writer(self, s3_config, table_config, mock_s3):
        """Create a writer with mock S3 client."""
        return S3ParquetWriter(
            s3_config=s3_config,
            table_config=table_config,
            execution_id="test123",
            s3_client=mock_s3,
        )

    def test_generate_key(self, writer):
        """Test S3 key generation."""
        timestamp = datetime(2024, 1, 15, 10, 30, 0, tzinfo=timezone.utc)
        key = writer._generate_key(timestamp)

        assert key.startswith("cdc/public/orders/")
        assert "LOAD20240115T103000_test123_" in key
        assert key.endswith(".parquet")

    def test_generate_key_increments(self, writer):
        """Test that batch counter increments."""
        timestamp = datetime(2024, 1, 15, 10, 30, 0, tzinfo=timezone.utc)

        key1 = writer._generate_key(timestamp)
        key2 = writer._generate_key(timestamp)

        assert "_0001.parquet" in key1
        assert "_0002.parquet" in key2

    def test_write_batch(self, writer, sample_rows, mock_s3):
        """Test writing a batch to S3."""
        timestamp = datetime(2024, 1, 15, 10, 30, 0, tzinfo=timezone.utc)
        key = writer.write_batch(sample_rows, timestamp)

        assert key.startswith("cdc/public/orders/")
        mock_s3.put_object.assert_called_once()

        call_args = mock_s3.put_object.call_args
        assert call_args.kwargs["Bucket"] == "test-bucket"
        assert call_args.kwargs["ContentType"] == "application/octet-stream"

    def test_write_batch_with_kms(self, table_config, mock_s3):
        """Test writing with KMS encryption."""
        from src.config import S3Config

        s3_config = S3Config(
            bucket="test-bucket",
            prefix="cdc",
            kms_key_id="arn:aws:kms:us-east-1:123456789012:key/test-key",
        )

        writer = S3ParquetWriter(
            s3_config=s3_config,
            table_config=table_config,
            execution_id="test123",
            s3_client=mock_s3,
        )

        sample_rows = [
            {"order_id": 1, "status": "pending", "commit_ts": datetime.now(timezone.utc), "op": "I"}
        ]
        writer.write_batch(sample_rows)

        call_args = mock_s3.put_object.call_args
        assert call_args.kwargs["ServerSideEncryption"] == "aws:kms"
        assert "test-key" in call_args.kwargs["SSEKMSKeyId"]

    def test_write_empty_batch(self, writer):
        """Test that empty batches are skipped."""
        result = writer.write_batch([])
        assert result == ""

    def test_get_written_files(self, writer, sample_rows):
        """Test file count tracking."""
        assert writer.get_written_files() == 0

        writer.write_batch(sample_rows)
        assert writer.get_written_files() == 1

        writer.write_batch(sample_rows)
        assert writer.get_written_files() == 2

    def test_convert_to_arrow(self, writer, sample_rows):
        """Test conversion to Arrow table."""
        table = writer._convert_to_arrow(sample_rows)

        assert table.num_rows == 2
        assert "order_id" in table.column_names
        assert "op" in table.column_names

    def test_convert_empty_raises(self, writer):
        """Test that empty data raises error."""
        with pytest.raises(WriterError):
            writer._convert_to_arrow([])
