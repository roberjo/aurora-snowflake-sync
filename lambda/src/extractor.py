"""Aurora PostgreSQL data extraction with server-side cursors."""

import logging
from contextlib import contextmanager
from datetime import datetime
from typing import Any, Generator, Optional

import psycopg2
import psycopg2.extras

from .config import AuroraConfig, TableConfig
from .exceptions import ExtractionError

logger = logging.getLogger(__name__)

# Global connection for Lambda warm starts
_connection = None


def get_connection(config: AuroraConfig) -> psycopg2.extensions.connection:
    """Get or create a database connection (reused across warm starts).

    Args:
        config: Aurora connection configuration.

    Returns:
        psycopg2 connection object.
    """
    global _connection

    if _connection is not None:
        try:
            # Test if connection is still alive
            with _connection.cursor() as cur:
                cur.execute("SELECT 1")
            return _connection
        except Exception:
            logger.info("Existing connection is stale, creating new one")
            try:
                _connection.close()
            except Exception:
                pass
            _connection = None

    try:
        _connection = psycopg2.connect(
            host=config.host,
            port=config.port,
            database=config.database,
            user=config.username,
            password=config.password,
            sslmode=config.ssl_mode,
            connect_timeout=10,
            options="-c statement_timeout=300000",  # 5 minute statement timeout
        )
        _connection.autocommit = True
        logger.info("Created new database connection to %s", config.host)
        return _connection
    except psycopg2.Error as e:
        raise ExtractionError(f"Failed to connect to Aurora: {e}") from e


def close_connection() -> None:
    """Close the global database connection."""
    global _connection
    if _connection is not None:
        try:
            _connection.close()
        except Exception:
            pass
        _connection = None


@contextmanager
def server_cursor(
    conn: psycopg2.extensions.connection, name: str, batch_size: int
) -> Generator[psycopg2.extensions.cursor, None, None]:
    """Create a server-side cursor for streaming large result sets.

    Args:
        conn: Database connection.
        name: Cursor name.
        batch_size: Number of rows to fetch per batch.

    Yields:
        psycopg2 cursor object.
    """
    cursor = conn.cursor(name=name, cursor_factory=psycopg2.extras.RealDictCursor)
    cursor.itersize = batch_size
    try:
        yield cursor
    finally:
        cursor.close()


class DataExtractor:
    """Extracts data from Aurora PostgreSQL using watermark-based queries."""

    def __init__(self, aurora_config: AuroraConfig, table_config: TableConfig):
        """Initialize the data extractor.

        Args:
            aurora_config: Aurora connection configuration.
            table_config: Table extraction configuration.
        """
        self.aurora_config = aurora_config
        self.table_config = table_config
        self._conn = None

    def _get_connection(self) -> psycopg2.extensions.connection:
        """Get database connection."""
        if self._conn is None:
            self._conn = get_connection(self.aurora_config)
        return self._conn

    def build_query(self, watermark: Optional[datetime]) -> tuple[str, dict[str, Any]]:
        """Build the extraction query.

        Args:
            watermark: The watermark timestamp (None for full load).

        Returns:
            Tuple of (query_string, parameters).
        """
        columns = ", ".join(self.table_config.source_columns)
        table = self.table_config.full_table_name
        wm_col = self.table_config.watermark_column
        created_col = self.table_config.created_at_column

        # Build OP column expression
        if created_col:
            op_expr = f"""
                CASE
                    WHEN {created_col} = {wm_col} THEN 'I'
                    ELSE 'U'
                END AS op
            """
        else:
            op_expr = "'U' AS op"

        if watermark is None:
            # Full load
            query = f"""
                SELECT {columns}, {wm_col} AS commit_ts, 'I' AS op
                FROM {table}
                ORDER BY {wm_col}
            """
            params = {}
        else:
            # Incremental load
            query = f"""
                SELECT {columns}, {wm_col} AS commit_ts, {op_expr}
                FROM {table}
                WHERE {wm_col} > %(watermark)s
                ORDER BY {wm_col}
            """
            params = {"watermark": watermark}

        return query, params

    def extract_batches(
        self, watermark: Optional[datetime], batch_size: Optional[int] = None
    ) -> Generator[tuple[list[dict[str, Any]], datetime], None, None]:
        """Extract data in batches using a server-side cursor.

        Args:
            watermark: The watermark timestamp (None for full load).
            batch_size: Override batch size (uses config default if None).

        Yields:
            Tuples of (batch_of_rows, max_watermark_in_batch).
        """
        batch_size = batch_size or self.table_config.batch_size
        query, params = self.build_query(watermark)
        wm_col = self.table_config.watermark_column

        conn = self._get_connection()

        try:
            with server_cursor(conn, "cdc_cursor", batch_size) as cursor:
                cursor.execute(query, params)

                batch = []
                max_watermark = watermark

                for row in cursor:
                    batch.append(dict(row))

                    # Track max watermark
                    row_wm = row.get("commit_ts") or row.get(wm_col.lower())
                    if row_wm and (max_watermark is None or row_wm > max_watermark):
                        max_watermark = row_wm

                    if len(batch) >= batch_size:
                        yield batch, max_watermark
                        batch = []

                # Yield remaining rows
                if batch:
                    yield batch, max_watermark

        except psycopg2.Error as e:
            raise ExtractionError(f"Failed to extract data: {e}") from e

    def get_row_count(self, watermark: Optional[datetime] = None) -> int:
        """Get count of rows to be extracted.

        Args:
            watermark: The watermark timestamp (None for full count).

        Returns:
            Number of rows.
        """
        table = self.table_config.full_table_name
        wm_col = self.table_config.watermark_column

        conn = self._get_connection()

        try:
            with conn.cursor() as cursor:
                if watermark is None:
                    cursor.execute(f"SELECT COUNT(*) FROM {table}")
                else:
                    cursor.execute(
                        f"SELECT COUNT(*) FROM {table} WHERE {wm_col} > %(watermark)s",
                        {"watermark": watermark},
                    )
                return cursor.fetchone()[0]
        except psycopg2.Error as e:
            raise ExtractionError(f"Failed to get row count: {e}") from e
