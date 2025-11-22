import pytest
import json
import os

def test_config_validation():
    """
    Validate that the sync_config.json file is valid JSON and has the required structure.
    """
    config_path = os.path.join(os.path.dirname(__file__), '../config/sync_config.json')
    
    with open(config_path, 'r') as f:
        config = json.load(f)
        
    assert 'tables' in config
    assert isinstance(config['tables'], list)
    assert len(config['tables']) > 0
    
    for table in config['tables']:
        assert 'table_name' in table
        assert 'watermark_col' in table
        assert isinstance(table['table_name'], str)
        assert isinstance(table['watermark_col'], str)
