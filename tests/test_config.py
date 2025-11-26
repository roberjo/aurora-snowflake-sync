import pytest
import json
import os

"""
Configuration Test Module
-------------------------
This module contains tests to validate the configuration files used by the application.

Purpose:
    Ensures that the external configuration (e.g., sync_config.json) is present,
    valid JSON, and contains the expected schema (tables, columns) required for the
    synchronization process to function correctly.
"""

def test_config_validation():
    """
    Validate that the sync_config.json file is valid JSON and has the required structure.

    Why this is needed:
        The application relies on this configuration file to know which tables to sync
        and which columns to use as watermarks. If this file is malformed or missing
        keys, the Lambda function will fail at runtime. This test catches such issues
        early in the CI/CD pipeline.

    Logic:
        1. Locate the config file relative to this test file.
        2. Load the JSON content.
        3. Assert that the 'tables' key exists and is a list.
        4. Iterate through each table entry and verify 'table_name' and 'watermark_col' exist and are strings.
    """
    # Construct the absolute path to the config file
    config_path = os.path.join(os.path.dirname(__file__), '../config/sync_config.json')
    
    # Open and load the JSON file
    with open(config_path, 'r') as f:
        config = json.load(f)
        
    # Verify the root structure
    assert 'tables' in config, "Config must contain 'tables' key"
    assert isinstance(config['tables'], list), "'tables' must be a list"
    assert len(config['tables']) > 0, "'tables' list must not be empty"
    
    # Verify the structure of each table definition
    for table in config['tables']:
        assert 'table_name' in table, "Each table config must have 'table_name'"
        assert 'watermark_col' in table, "Each table config must have 'watermark_col'"
        assert isinstance(table['table_name'], str), "'table_name' must be a string"
        assert isinstance(table['watermark_col'], str), "'watermark_col' must be a string"
