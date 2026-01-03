.PHONY: terraform-validate security

terraform-validate:
	cd terraform && terraform fmt -check && terraform validate

security:
	# Requires checkov and gitleaks installed
	checkov -d terraform/
	gitleaks detect --source . -v
