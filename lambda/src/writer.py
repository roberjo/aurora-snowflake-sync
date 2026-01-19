"""S3 Parquet writer for CDC data."""

import io
import logging
from datetime import datetime, timezone
from typing import Any, Optional

import boto3
import pandas as pd
import pyarrow as pa
import pyarrow.parquet as pq

from .config import S3Config, TableConfig
from .exceptions import WriterError

logger = logging.getLogger(__name__)


class S3ParquetWriter:
    """Writes CDC data to S3 in Parquet format."""

    def __init__(
        self,
        s3_config: S3Config,
        table_config: TableConfig,
        execution_id: str,
        s3_client=None,
    ):
        """Initialize the S3 writer.

        Args:
            s3_config: S3 output configuration.
            table_config: Table configuration for path building.
            execution_id: Unique execution identifier.
            s3_client: Optional boto3 S3 client (for testing).
        """
        self.s3_config = s3_config
        self.table_config = table_config
        self.execution_id = execution_id
        self.s3 = s3_client or boto3.client("s3")
        self._batch_counter = 0

    def _generate_key(self, timestamp: datetime) -> str:
        """Generate S3 key for a Parquet file.

        Pattern: {prefix}/{schema}/{table}/LOAD{timestamp}_{execution_id}_{batch}.parquet
        """
        ts_str = timestamp.strftime("%Y%m%dT%H%M%S")
        self._batch_counter += 1

        key = (
            f"{self.s3_config.prefix}/"
            f"{self.table_config.source_schema}/"
            f"{self.table_config.source_table}/"
            f"LOAD{ts_str}_{self.execution_id}_{self._batch_counter:04d}.parquet"
        )
        return key

    def _convert_to_arrow(self, rows: list[dict[str, Any]]) -> pa.Table:
        """Convert rows to PyArrow table.

        Args:
            rows: List of row dictionaries.

        Returns:
            PyArrow Table.
        """
        if not rows:
            raise WriterError("Cannot write empty batch")

        df = pd.DataFrame(rows)

        # Ensure consistent column order and types
        for col in df.columns:
            if df[col].dtype == "object":
                # Check if it's a datetime column stored as string
                if col in ("commit_ts", "updated_at", "created_at"):
                    df[col] = pd.to_datetime(df[col], utc=True)

        return pa.Table.from_pandas(df, preserve_index=False)

    def write_batch(
        self,
        rows: list[dict[str, Any]],
        timestamp: Optional[datetime] = None,
    ) -> str:
        """Write a batch of rows to S3 as Parquet.

        Args:
            rows: List of row dictionaries to write.
            timestamp: Optional timestamp for the file (uses current time if None).

        Returns:
            The S3 key where the file was written.
        """
        if not rows:
            logger.warning("Skipping empty batch")
            return ""

        timestamp = timestamp or datetime.now(timezone.utc)
        key = self._generate_key(timestamp)

        try:
            # Convert to Arrow table
            table = self._convert_to_arrow(rows)

            # Write to buffer
            buffer = io.BytesIO()
            pq.write_table(
                table,
                buffer,
                compression="snappy",
                use_dictionary=True,
            )
            buffer.seek(0)

            # Upload to S3
            extra_args = {}
            if self.s3_config.kms_key_id:
                extra_args = {
                    "ServerSideEncryption": "aws:kms",
                    "SSEKMSKeyId": self.s3_config.kms_key_id,
                }

            self.s3.put_object(
                Bucket=self.s3_config.bucket,
                Key=key,
                Body=buffer.getvalue(),
                ContentType="application/octet-stream",
                **extra_args,
            )

            logger.info(
                "Wrote %d rows to s3://%s/%s",
                len(rows),
                self.s3_config.bucket,
                key,
            )
            return key

        except Exception as e:
            raise WriterError(f"Failed to write batch to S3: {e}") from e

    def get_written_files(self) -> int:
        """Get the number of files written so far."""
        return self._batch_counter
