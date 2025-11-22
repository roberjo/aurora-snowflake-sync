#!/bin/bash
set -e

# Directory setup
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
PROJECT_ROOT="$SCRIPT_DIR/.."
BUILD_DIR="$PROJECT_ROOT/build"
LAMBDA_DIR="$PROJECT_ROOT/lambda"

# Clean build dir
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

echo "Packaging Lambda function..."

# Use Docker to install dependencies compatible with Amazon Linux 2
# This ensures binary compatibility for libraries like psycopg2
docker run --rm -v "$PROJECT_ROOT":/var/task public.ecr.aws/sam/build-python3.9:latest /bin/sh -c "
    pip install -r lambda/requirements.txt -t lambda/lib && 
    cd lambda && 
    zip -r ../build/exporter.zip . -x 'lib/*__pycache__*'
"

echo "Package created at $BUILD_DIR/exporter.zip"
