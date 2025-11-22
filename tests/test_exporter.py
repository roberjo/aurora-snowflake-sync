import pytest
from unittest.mock import MagicMock, patch
import os
import sys

# Add lambda dir to path
sys.path.append(os.path.join(os.path.dirname(__file__), '../lambda'))

from exporter import lambda_handler

@patch('exporter.get_secrets')
@patch('exporter.get_snowflake_watermark')
@patch('exporter.export_from_aurora')
def test_lambda_handler_success(mock_export, mock_watermark, mock_secrets):
    # Setup Mocks
    mock_secrets.return_value = {
        'aurora_host': 'host', 'aurora_db': 'db', 'aurora_user': 'u', 'aurora_password': 'p',
        'snowflake_user': 'u', 'snowflake_password': 'p', 'snowflake_account': 'a'
    }
    mock_watermark.return_value = '2023-01-01 00:00:00'
    
    os.environ['S3_BUCKET'] = 'test-bucket'
    
    # Execute
    response = lambda_handler({}, {})
    
    # Verify
    assert response['statusCode'] == 200
    assert mock_export.call_count == 2 # 2 tables in config
    mock_watermark.assert_called()

@patch('exporter.get_secrets')
def test_lambda_handler_failure(mock_secrets):
    # Setup Mocks to raise exception
    mock_secrets.side_effect = Exception("Vault Down")
    
    os.environ['S3_BUCKET'] = 'test-bucket'
    
    # Execute
    response = lambda_handler({}, {})
    
    # Verify
    assert response['statusCode'] == 500
    assert "Vault Down" in response['body']

@patch('exporter.get_secrets')
@patch('exporter.get_snowflake_watermark')
@patch('exporter.export_from_aurora')
def test_lambda_handler_partial_failure(mock_export, mock_watermark, mock_secrets):
    """
    Test that if one table fails, the whole process catches the exception (or we could design it to continue).
    Current implementation catches top level, so let's verify that.
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
    Test fallback when watermark is None (new table).
    """
    mock_secrets.return_value = {
        'aurora_host': 'host', 'aurora_db': 'db', 'aurora_user': 'u', 'aurora_password': 'p',
        'snowflake_user': 'u', 'snowflake_password': 'p', 'snowflake_account': 'a'
    }
    # Simulate Snowflake returning None (no rows in table)
    mock_watermark.return_value = None 
    
    os.environ['S3_BUCKET'] = 'test-bucket'
    
    response = lambda_handler({}, {})
    
    assert response['statusCode'] == 200
    # In the code, we handle None inside get_snowflake_watermark, but if it returned None here, 
    # we'd want to ensure export is still called.
    # However, our mock returns None, so let's see how the code handles it.
    # The code: `return row[0] if row and row[0] else '1970-01-01 00:00:00'`
    # So the mock for get_snowflake_watermark should actually return the default if we want to test the logic *inside* that function,
    # but since we are mocking that function, we are testing the handler's reaction to its output.
    # If we want to test the handler receiving a specific value:
    
    mock_watermark.return_value = '1970-01-01 00:00:00'
    response = lambda_handler({}, {})
    assert response['statusCode'] == 200
    mock_export.assert_called()

