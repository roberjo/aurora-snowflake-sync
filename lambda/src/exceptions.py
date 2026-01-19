"""Custom exceptions for the CDC Lambda export."""


class CDCExportError(Exception):
    """Base exception for CDC export errors."""

    pass


class WatermarkError(CDCExportError):
    """Error reading or updating watermark state."""

    pass


class ExtractionError(CDCExportError):
    """Error extracting data from Aurora."""

    pass


class WriterError(CDCExportError):
    """Error writing data to S3."""

    pass


class ConfigurationError(CDCExportError):
    """Invalid or missing configuration."""

    pass


class TimeoutApproachingError(CDCExportError):
    """Lambda timeout is approaching, graceful shutdown needed."""

    pass
