.PHONY: install install-dev test lint format clean build layer

PYTHON := python3
PIP := pip3
LAYER_DIR := build/layer
PACKAGE_DIR := build/package

# Install production dependencies
install:
	$(PIP) install -r requirements.txt

# Install development dependencies
install-dev:
	$(PIP) install -r requirements-dev.txt

# Run tests
test:
	$(PYTHON) -m pytest tests/ -v --cov=src --cov-report=term-missing

# Run tests with coverage report
test-cov:
	$(PYTHON) -m pytest tests/ -v --cov=src --cov-report=html

# Run linting
lint:
	flake8 src/ tests/ --max-line-length=100
	black --check src/ tests/
	isort --check-only src/ tests/
	mypy src/ --ignore-missing-imports

# Format code
format:
	black src/ tests/
	isort src/ tests/

# Clean build artifacts
clean:
	rm -rf build/
	rm -rf dist/
	rm -rf *.egg-info
	rm -rf .pytest_cache/
	rm -rf .coverage
	rm -rf htmlcov/
	find . -type d -name __pycache__ -exec rm -rf {} +
	find . -type f -name "*.pyc" -delete

# Build Lambda layer
layer: clean
	mkdir -p $(LAYER_DIR)/python
	$(PIP) install \
		--platform manylinux2014_x86_64 \
		--target $(LAYER_DIR)/python \
		--implementation cp \
		--python-version 3.11 \
		--only-binary=:all: \
		-r requirements.txt
	cd $(LAYER_DIR) && zip -r ../lambda-layer.zip python/

# Build Lambda package
build: clean
	mkdir -p $(PACKAGE_DIR)
	cp -r src/* $(PACKAGE_DIR)/
	cd $(PACKAGE_DIR) && zip -r ../lambda-function.zip .

# Build everything
all: layer build
