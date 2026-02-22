# Legacy Project Onboarding Playbook

This document provides a step-by-step playbook for bringing existing TIM projects into full compliance with design standards.

## Overview

Legacy projects typically have:

- Working code that doesn't meet current standards
- Tests that pass but don't follow naming conventions
- Missing type hints, inconsistent patterns
- No pre-commit hooks or CI gates

This playbook provides a phased approach to achieve compliance without breaking production.

## Prerequisites

Before starting migration:

1. **Stakeholder alignment** - Everyone agrees migration is priority
2. **No major features in flight** - Clear runway for refactoring
3. **Working CI** - Even if not compliant, tests should run
4. **Backup/rollback plan** - Ability to revert if needed

## Migration Timeline

| Phase | Duration | Focus |
|-------|----------|-------|
| 0. Assessment | 1-2 days | Understand current state |
| 1. Infrastructure | 2-3 days | Set up gates, tools |
| 2. Quick Wins | 3-5 days | Low-risk improvements |
| 3. Test Migration | 5-10 days | Rename, type-hint tests |
| 4. Code Compliance | 5-10 days | Type hints, patterns |
| 5. Full Enforcement | 1-2 days | Enable hard blocks |

**Total: 3-4 weeks** for typical project.

## Phase 0: Assessment

### 0.1 Run Compliance Check

```bash
# Clone tim if not already
git clone <tim_repo>

# Run compliance checker
./tim/tools/tim-compliance-check.sh /path/to/project
```

### 0.2 Generate Assessment Report

Create `MIGRATION.md` in project root:

```markdown
# Migration Assessment: [Project Name]

**Date**: YYYY-MM-DD
**Assessed by**: [Name]

## Current State

### Files
- Total Python/TS files: ___
- Files > 400 lines: ___
- Avg file size: ___ lines

### Type Coverage
- Python: ___% (mypy --strict errors: ___)
- TypeScript: ___% (tsc strict errors: ___)

### Test Coverage
- Line coverage: ___%
- Branch coverage: ___%
- Tests with compliant names: ___/___

### Dependencies
- Using tim-lib/shared library: Yes/No
- Outdated dependencies: ___

### CI/CD
- Pre-commit hooks: Yes/No
- CI pipeline: Yes/No
- Gate 1 (local): Passing/Failing/Missing
- Gate 2 (CI): Passing/Failing/Missing
- Gate 3 (deploy): Passing/Failing/Missing

## Priority Issues

1. [Most critical issue]
2. [Second priority]
3. [Third priority]

## Estimated Effort

- Phase 1 (Infrastructure): ___ days
- Phase 2 (Quick Wins): ___ days
- Phase 3 (Test Migration): ___ days
- Phase 4 (Code Compliance): ___ days
- Phase 5 (Full Enforcement): ___ days

**Total**: ___ days
```

### 0.3 Create Migration Tracking

```yaml
# .migration/status.yaml
project: "project-name"
started: "2025-01-15"
target_completion: "2025-02-15"
current_phase: 0

phases:
  assessment:
    status: "in_progress"
    started: "2025-01-15"
    completed: null

  infrastructure:
    status: "pending"
    started: null
    completed: null

  quick_wins:
    status: "pending"
    started: null
    completed: null

  test_migration:
    status: "pending"
    started: null
    completed: null

  code_compliance:
    status: "pending"
    started: null
    completed: null

  full_enforcement:
    status: "pending"
    started: null
    completed: null

blockers: []
```

## Phase 1: Infrastructure

### 1.1 Copy Required Files

```bash
# Copy CLAUDE.md
cp tim/CLAUDE.md ./

# Copy template configs
cp tim/templates/python/pyproject.toml ./  # or node/package.json
cp tim/templates/python/.pre-commit-config.yaml ./
```

### 1.2 Install Shared Library

**Python:**

```bash
# Add to pyproject.toml dependencies
poetry add tim-lib@path/to/tim/libs/python
# or
pip install path/to/tim/libs/python
```

**Node.js:**

```bash
npm install path/to/tim/libs/node
```

### 1.3 Configure Pre-commit (Warn Mode)

Initially, run hooks in warn mode to avoid blocking developers:

```yaml
# .pre-commit-config.yaml
default_stages: [commit]
fail_fast: false  # Don't fail on first error during migration

repos:
  - repo: local
    hooks:
      - id: ruff-check
        name: ruff check (warn only)
        entry: ruff check --fix
        language: system
        types: [python]
        # Remove 'fail_fast: true' during migration
```

### 1.4 Set Up CI (Reporting Mode)

Configure CI to report violations without blocking:

```yaml
# .github/workflows/ci.yml
- name: Type Check (reporting only)
  run: mypy src --strict || echo "::warning::Type check failed"
  continue-on-error: true  # Don't block during migration

- name: Coverage Check (reporting only)
  run: pytest --cov --cov-report=term
  continue-on-error: true  # Don't block during migration
```

### 1.5 Create Pattern Registry

```yaml
# .tim-patterns.yaml
patterns:
  # Mark current patterns as MIGRATION
  authentication:
    standard: "MIGRATION"
    current_implementation: "custom-jwt"
    target_standard: "jwt-bearer"
    migration_deadline: "2025-02-15"

  database_access:
    standard: "MIGRATION"
    current_implementation: "raw-sql"
    target_standard: "sqlalchemy-async"
    migration_deadline: "2025-02-28"
```

## Phase 2: Quick Wins

Focus on changes that improve compliance without risk.

### 2.1 Add Type Hints to New Code

**Rule**: All new code must have type hints. Existing code is grandfathered temporarily.

```python
# mypy.ini - ignore existing files during migration
[mypy]
strict = true

[mypy-app.legacy.*]
ignore_errors = true
```

### 2.2 Fix Formatting

Formatting is safe - doesn't change behavior:

```bash
# Python
ruff format src tests

# Node.js
npx prettier --write "src/**/*.ts" "tests/**/*.ts"
```

### 2.3 Remove Dead Code

```bash
# Find unused imports
ruff check --select=F401 src

# Find unused variables
ruff check --select=F841 src
```

### 2.4 Add Missing Docstrings (Public APIs Only)

Focus on public APIs, skip internal functions:

```python
# Before
def create_user(email, password):
    ...

# After
def create_user(email: str, password: str) -> User:
    """Create a new user with the given credentials.

    Args:
        email: User's email address.
        password: User's password (will be hashed).

    Returns:
        The created user object.

    Raises:
        UserExistsError: If email is already registered.
    """
    ...
```

### 2.5 Update Dependencies

```bash
# Check for outdated
poetry show --outdated  # or npm outdated

# Update patch versions (safe)
poetry update --patch  # or npm update
```

## Phase 3: Test Migration

See [Test Migration Standard](../testing/test-migration.md) for detailed process.

### Summary

1. Rename tests to `test_what_when_then` format
2. Add type hints to all fixtures and tests
3. Remove print statements
4. Consolidate fixtures in conftest.py
5. Verify all tests still pass

## Phase 4: Code Compliance

### 4.1 Add Type Hints (Incremental)

Use a priority order:

1. **Public APIs** - Most important for consumers
2. **Service layer** - Business logic
3. **Models** - Data structures
4. **Utilities** - Helper functions
5. **Internal functions** - Least priority

Track progress:

```bash
# Count typed vs untyped functions
mypy src --strict 2>&1 | grep "error:" | wc -l
```

### 4.2 Split Large Files

Files > 400 lines must be split:

1. Identify logical groupings in the file
2. Create new module structure
3. Move code incrementally
4. Update imports
5. Verify tests pass after each move

### 4.3 Reduce Function Complexity

Functions > 50 lines or complexity > 10:

1. Extract helper functions
2. Simplify conditionals
3. Use early returns
4. Remove duplicate logic

### 4.4 Migrate to Shared Library

Replace custom implementations with tim-lib:

```python
# Before
from app.utils.password import hash_password, verify_password

# After
from tim_lib import hash_password, verify_password
```

### 4.5 Update Pattern Registry

As patterns are migrated, update status:

```yaml
# .tim-patterns.yaml
patterns:
  authentication:
    standard: "jwt-bearer"  # Changed from MIGRATION
    reference: "standards/security/authentication.md"
    implemented: true
    migrated_date: "2025-02-10"
```

## Phase 5: Full Enforcement

### 5.1 Enable Pre-commit Blocking

```yaml
# .pre-commit-config.yaml
default_stages: [commit]
fail_fast: true  # Now fail on errors

repos:
  - repo: local
    hooks:
      - id: ruff-check
        name: ruff check
        entry: ruff check --fix
        language: system
        types: [python]
        fail_fast: true  # Block on failure
```

### 5.2 Enable CI Blocking

```yaml
# .github/workflows/ci.yml
- name: Type Check
  run: mypy src --strict
  # Remove continue-on-error

- name: Coverage Check
  run: pytest --cov
  # Remove continue-on-error
```

### 5.3 Verify All Gates Pass

```bash
# Gate 1: Local
pre-commit run --all-files

# Gate 2: CI (run locally to verify)
mypy src --strict
ruff check src tests
pytest --cov

# Gate 3: Deploy gates
./ops.sh health-check
```

### 5.4 Update Migration Status

```yaml
# .migration/status.yaml
project: "project-name"
started: "2025-01-15"
completed: "2025-02-14"
current_phase: "complete"

phases:
  # ... all phases completed
```

### 5.5 Remove Migration Artifacts

```bash
rm -rf .migration/
rm MIGRATION.md
# Update .tim-patterns.yaml to remove MIGRATION statuses
```

## Rollback Procedures

### If Tests Start Failing

1. Identify which change broke tests
2. Revert that specific change
3. Analyze why it broke
4. Fix properly before re-applying

### If Production Issues Arise

1. Rollback deployment immediately
2. Disable new gates (revert to warn mode)
3. Investigate root cause
4. Fix and re-enable gates

### If Migration Stalls

1. Document current state
2. Identify blockers
3. Request human decision on priority
4. Consider partial compliance (with exceptions)

## Exception Process During Migration

During migration, projects may need temporary exceptions:

```yaml
# .tim-patterns.yaml
exceptions:
  - rule: "coverage-reporting"
    current_value: "not configured"
    target_value: "reported"
    reason: "Legacy code migration in progress"
    deadline: "2025-02-28"
    approved_by: "human@example.com"
    approved_date: "2025-01-15"
```

See [Gates - Exception Process](../enforcement/gates.md#exception-process) for full requirements.

## Metrics to Track

| Metric | Start | Target | Current |
|--------|-------|--------|---------|
| Type coverage | ___% | 100% | ___% |
| Test coverage | ___% | Reported | ___% |
| Files > 400 lines | ___ | 0 | ___ |
| Functions > 50 lines | ___ | 0 | ___ |
| Pre-commit passing | No | Yes | ___ |
| CI gates passing | No | Yes | ___ |

## See Also

- [Test Migration](../testing/test-migration.md)
- [AI Coordination](ai-coordination.md)
- [Gates](../enforcement/gates.md)
- [Strict Compliance](../enforcement/strict-compliance.md)
