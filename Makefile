.PHONY: setup test lint format package clean

setup:
	bash scripts/setup_dev_env.sh

test:
	pytest

lint:
	flake8 lambda
	black --check lambda

format:
	black lambda

package:
	bash scripts/package_lambda.sh

security:
	# Requires checkov and gitleaks installed
	checkov -d terraform/
	gitleaks detect --source . -v

clean:
	rm -rf build
	rm -rf lambda/lib
	rm -rf venv
