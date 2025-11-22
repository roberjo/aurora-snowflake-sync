#!/bin/bash
echo "Setting up development environment..."

# Check for Python
if ! command -v python3 &> /dev/null; then
    echo "Python 3 is not installed."
    exit 1
fi

# Create Venv
if [ ! -d "venv" ]; then
    python3 -m venv venv
    echo "Virtual environment created."
fi

# Activate
source venv/bin/activate || source venv/Scripts/activate

# Install Deps
pip install --upgrade pip
pip install -r lambda/requirements.txt
pip install pytest black flake8

echo "Dependencies installed."
echo "Run 'source venv/bin/activate' to start developing."
