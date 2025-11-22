# Code Review Guidelines

## Purpose
This document provides a structured approach for peer code reviews to ensure code quality, security, and maintainability.

## Review Checklist

### 1. Code Quality (Must Pass)
- [ ] **Follows coding standards**: Python follows PEP 8, Terraform is formatted, SQL uses UPPERCASE keywords
- [ ] **No hardcoded values**: Secrets, endpoints, table names are configurable
- [ ] **Proper error handling**: Try-except blocks around external calls with specific exceptions
- [ ] **Clear variable names**: Self-documenting, no single letters except loop counters
- [ ] **Functions are focused**: Single Responsibility Principle (one function, one purpose)
- [ ] **Comments where needed**: Complex logic has explanatory comments
- [ ] **No dead code**: Unused imports, functions, or commented-out blocks removed

### 2. Testing (Must Pass)
- [ ] **Unit tests added/updated**: New code has corresponding tests
- [ ] **Tests pass locally**: Reviewer has run `pytest tests/` successfully
- [ ] **Edge cases covered**: Tests include error scenarios, empty data, null values
- [ ] **Mocks used appropriately**: External dependencies (DB, AWS) are mocked
- [ ] **Test names are descriptive**: `test_lambda_handler_with_invalid_credentials` not `test_1`

### 3. Security (Critical)
- [ ] **No secrets in code**: No API keys, passwords, tokens in source
- [ ] **No secrets in git history**: Checked with `gitleaks detect`
- [ ] **IAM permissions are minimal**: Least privilege principle applied
- [ ] **Input validation**: User/config input is validated and sanitized
- [ ] **SQL injection prevention**: No string concatenation for SQL queries (use parameterized queries)
- [ ] **Dependencies are secure**: No known vulnerabilities (run `pip-audit` or `safety check`)

### 4. Infrastructure (IaC)
- [ ] **Terraform validates**: `terraform validate` passes
- [ ] **Resources are tagged**: All AWS resources include `Name` and project tags
- [ ] **State is managed**: Backend configuration is correct
- [ ] **Checkov scan passes**: No critical security issues (`checkov -d terraform/`)
- [ ] **Outputs documented**: Important resource IDs are exposed as outputs

### 5. Documentation
- [ ] **README updated**: If feature changes setup or usage
- [ ] **Docstrings added**: All new public functions have Google-style docstrings
- [ ] **PR description is clear**: Includes "Why", "What", and "How"
- [ ] **CHANGELOG updated**: For notable changes
- [ ] **Runbook updated**: If operational procedures change

### 6. Performance & Scalability
- [ ] **No N+1 queries**: Batch operations where possible
- [ ] **Timeouts configured**: Network calls have reasonable timeouts
- [ ] **Memory usage considered**: Large datasets are streamed, not loaded fully into memory
- [ ] **Lambda limits respected**: Execution under 5 minutes, payload under 6MB

### 7. Observability
- [ ] **Logging added**: Important operations are logged with context
- [ ] **Log levels appropriate**: Use INFO for normal flow, ERROR for failures
- [ ] **No sensitive data in logs**: Don't log passwords, tokens, PII
- [ ] **Metrics considered**: For critical paths, consider CloudWatch metrics

## Review Severity Levels

### 🔴 Critical (Must Fix Before Merge)
- Security vulnerabilities
- Hardcoded secrets
- Breaking changes without migration path
- Data loss risk
- Production-impacting bugs

### 🟡 Major (Should Fix Before Merge)
- Code quality issues (complexity, duplication)
- Missing tests for new features
- Performance concerns
- Incomplete error handling
- Documentation gaps

### 🟢 Minor (Nice to Have)
- Code style inconsistencies (if linters pass)
- Optimization opportunities
- Better naming suggestions
- Additional test coverage

## How to Review

### Step 1: Understand the Context
1. Read the PR description and linked issues
2. Understand the "why" before the "how"
3. Check the diff size (if >500 lines, ask for split)

### Step 2: Automated Checks
1. Verify CI/CD passed (GitHub Actions)
2. Check test coverage hasn't decreased
3. Review security scan results (Checkov, Gitleaks)

### Step 3: Manual Review
1. **Read the code**: Don't just scan, understand the logic
2. **Think about edge cases**: What could go wrong?
3. **Consider the user**: Will this be easy to operate/debug?
4. **Check documentation**: Is this change documented?

### Step 4: Provide Feedback
1. **Be specific**: "This lambda will timeout if >10k rows" not "Performance issue"
2. **Explain why**: Give reasoning, not just directives
3. **Suggest alternatives**: Offer solutions when pointing out problems
4. **Be kind**: Assume good intent, review code not people
5. **Use GitHub suggestions**: Propose code changes inline when possible

### Step 5: Approve or Request Changes
- **Approve**: If no critical issues and minor issues are noted
- **Request Changes**: If critical or multiple major issues
- **Comment**: If asking questions or providing info without blocking

## Python-Specific Review Points
- Ensure `black` formatting applied (should be enforced by CI)
- Check for proper use of context managers (`with` statements for files, connections)
- Verify exception types are specific, not bare `except:`
- Look for proper use of list comprehensions vs loops (readability first)
- Check imports are organized (standard, third-party, local)

## Terraform-Specific Review Points
- Ensure `terraform fmt` applied
- Verify variables have types and descriptions
- Check for use of data sources over hardcoded values
- Look for proper use of `depends_on` for ordering
- Verify sensitive variables are marked `sensitive = true`

## Examples of Good Feedback

### ✅ Good
> **File: lambda/exporter.py:45**  
> Consider adding a retry mechanism here. If Aurora is momentarily unavailable, the entire sync will fail. Suggest using `tenacity` library with exponential backoff.
> ```python
> from tenacity import retry, stop_after_attempt, wait_exponential
> 
> @retry(stop=stop_after_attempt(3), wait=wait_exponential(multiplier=1, min=2, max=10))
> def export_from_aurora(...):
> ```

### ❌ Poor
> This won't work.

## Approval Criteria
A PR can be merged when:
1. At least 1 approval from a team member
2. All CI checks passing (tests, lints, security scans)
3. No unresolved "Request Changes" reviews
4. All conversations resolved or explicitly marked as "won't fix"

## Special Cases

### Hotfixes
- Can be merged with 1 approval
- Must still pass CI
- Follow up with full review post-deployment

### Documentation-Only Changes
- Can be merged with 1 approval
- No need for full test suite

### Experimental/POC Branches
- Different standards may apply
- Clearly label as `[POC]` in PR title
- Must be refactored before merging to main

## Resources
- [Developer Guide](../docs/DEVELOPER_GUIDE.md)
- [Security Guidelines](../docs/SECURITY.md)
- [Architecture Docs](../docs/ARCHITECTURE.md)
