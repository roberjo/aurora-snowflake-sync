import pytest
from unittest.mock import MagicMock, patch
import os
import sys

"""
Exporter Lambda Unit Tests
--------------------------
This module contains unit tests for the exporter Lambda function.

Purpose:
    To verify the logic of the synchronization process in isolation, mocking external
    dependencies like Hashicorp Vault, Snowflake, and Aurora. This ensures that the
    orchestration logic (retrieving secrets, looping through tables, handling errors)
    works as expected without needing actual database connections.
"""

# Add lambda dir to path to allow importing the lambda code
sys.path.append(os.path.join(os.path.dirname(__file__), '../lambda'))

from exporter import lambda_handler

@patch('exporter.get_secrets')
@patch('exporter.get_snowflake_watermark')
@patch('exporter.export_from_aurora')
def test_lambda_handler_success(mock_export, mock_watermark, mock_secrets):
    """
    Test the happy path where all external calls succeed.

    Scenario:
        - Secrets are successfully retrieved.
        - Watermark is successfully retrieved for all tables.
        - Export function is called for all tables.

    Expected Result:
        - Status code 200.
        - Export function called twice (once for each table in the mock config).
    """
    # Setup Mocks with valid return values
    mock_secrets.return_value = {
        'aurora_host': 'host', 'aurora_db': 'db', 'aurora_user': 'u', 'aurora_password': 'p',
        'snowflake_user': 'u', 'snowflake_password': 'p', 'snowflake_account': 'a'
    }
    mock_watermark.return_value = '2023-01-01 00:00:00'
    
    # Mock the S3 bucket environment variable
    os.environ['S3_BUCKET'] = 'test-bucket'
    
    # Execute the handler
    response = lambda_handler({}, {})
    
    # Verify the response and side effects
    assert response['statusCode'] == 200
    assert mock_export.call_count == 2 # Expecting 2 calls because there are 2 tables in the config
    mock_watermark.assert_called()

@patch('exporter.get_secrets')
def test_lambda_handler_failure(mock_secrets):
    """
    Test the failure scenario where secrets cannot be retrieved.

    Scenario:
        - Vault is unreachable or authentication fails.

    Expected Result:
        - Status code 500.
        - Error message containing the exception details.
    """
    # Setup Mocks to raise exception immediately when getting secrets
    mock_secrets.side_effect = Exception("Vault Down")
    
    os.environ['S3_BUCKET'] = 'test-bucket'
    
    # Execute
    response = lambda_handler({}, {})
    
    # Verify error handling
    assert response['statusCode'] == 500
    assert "Vault Down" in response['body']

@patch('exporter.get_secrets')
@patch('exporter.get_snowflake_watermark')
@patch('exporter.export_from_aurora')
def test_lambda_handler_partial_failure(mock_export, mock_watermark, mock_secrets):
    """
    Test that if one table fails, the whole process catches the exception.
    
    Scenario:
        - Secrets and Watermark retrieval succeed.
        - Export fails for the first table.

    Expected Result:
        - Status code 500.
        - Execution stops (fail-fast behavior).
    """
    mock_secrets.return_value = {
        'aurora_host': 'host', 'aurora_db': 'db', 'aurora_user': 'u', 'aurora_password': 'p',
        'snowflake_user': 'u', 'snowflake_password': 'p', 'snowflake_account': 'a'
    }
    mock_watermark.return_value = '2023-01-01'
    
    # Simulate export failure for the first table
    mock_export.side_effect = Exception("Aurora Connection Failed")
    
    os.environ['S3_BUCKET'] = 'test-bucket'
    
    response = lambda_handler({}, {})
    
    assert response['statusCode'] == 500
    assert "Aurora Connection Failed" in response['body']

@patch('exporter.get_secrets')
@patch('exporter.get_snowflake_watermark')
@patch('exporter.export_from_aurora')
def test_lambda_handler_empty_watermark(mock_export, mock_watermark, mock_secrets):
    """
    Test fallback when watermark is None or default (new table).

    Scenario:
        - Snowflake returns a default date (e.g., 1970-01-01) indicating no data.

    Expected Result:
        - Export proceeds with the default date.
        - Status code 200.
    """
    mock_secrets.return_value = {
        'aurora_host': 'host', 'aurora_db': 'db', 'aurora_user': 'u', 'aurora_password': 'p',
        'snowflake_user': 'u', 'snowflake_password': 'p', 'snowflake_account': 'a'
    }
    
    # Simulate Snowflake returning the default date (logic handled in get_snowflake_watermark, 
    # but here we mock the return of that function)
    mock_watermark.return_value = '1970-01-01 00:00:00'
    
    os.environ['S3_BUCKET'] = 'test-bucket'
    
    response = lambda_handler({}, {})
    
    assert response['statusCode'] == 200
    mock_export.assert_called()

