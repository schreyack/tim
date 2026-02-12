# Test Migration Standard

This document defines how to migrate existing tests to TIM standards without breaking functionality.

## Overview

Legacy projects often have tests that work but don't comply with TIM standards:

- Non-standard naming (`test_login` instead of `test_login_with_valid_credentials_returns_token`)
- Missing type hints
- Print statements instead of logging
- Inconsistent fixtures
- Poor organization

This standard provides a safe migration path.

## Migration Principles

1. **Never break working tests** - Refactor preserves functionality
2. **Incremental migration** - One file or module at a time
3. **Verify after each change** - Run tests after every refactor
4. **Track progress** - Maintain migration checklist per project

## Migration Phases

### Phase 1: Assessment (Day 1)

**Goal**: Understand current state, create migration plan.

1. **Count tests**

   ```bash
   # Python
   pytest --collect-only | grep "test session starts" -A 1000 | grep "<Function" | wc -l

   # Node.js
   npx vitest --run --reporter=verbose 2>&1 | grep "✓\|✗" | wc -l
   ```

2. **Identify non-compliant naming**

   ```bash
   # Python - find tests not using test_what_when_then
   grep -r "def test_" tests/ | grep -v "_with_\|_when_\|_returns_\|_raises_\|_creates_"

   # Node.js
   grep -r "it\('" tests/ | grep -v "should_\|_with_\|_when_\|_returns_"
   ```

3. **Check for print statements**

   ```bash
   grep -r "print(" tests/ --include="*.py"
   grep -r "console.log" tests/ --include="*.ts"
   ```

4. **Generate migration checklist**

   ```yaml
   # tests/MIGRATION.yaml
   total_tests: 150
   compliant_tests: 45
   target_date: "2025-02-15"

   files:
     - path: "tests/unit/test_auth.py"
       tests: 12
       compliant: 3
       priority: high
       status: pending

     - path: "tests/unit/test_user.py"
       tests: 8
       compliant: 0
       priority: high
       status: pending
   ```

### Phase 2: Infrastructure (Days 2-3)

**Goal**: Set up compliant test infrastructure before migrating tests.

1. **Create/update conftest.py**
   - Add standard fixtures
   - Add type hints to all fixtures
   - Remove any print-based debugging

2. **Organize test directories**

   ```text
   tests/
   ├── conftest.py           # Shared fixtures
   ├── unit/                  # Unit tests (isolated)
   │   ├── conftest.py        # Unit-specific fixtures
   │   └── ...
   └── integration/           # Integration tests
       ├── conftest.py        # Integration fixtures
       └── ...
   ```

3. **Add pytest configuration**

   ```toml
   # pyproject.toml
   [tool.pytest.ini_options]
   asyncio_mode = "auto"
   testpaths = ["tests"]
   python_files = ["test_*.py"]
   python_functions = ["test_*"]
   addopts = "-v --tb=short"
   ```

### Phase 3: Naming Migration (Days 4-7)

**Goal**: Rename all tests to `test_what_when_then` format.

#### Naming Patterns

| Old Name | New Name |
|----------|----------|
| `test_login` | `test_login_with_valid_credentials_returns_token` |
| `test_login_fail` | `test_login_with_invalid_password_returns_401` |
| `test_create_user` | `test_create_user_with_valid_data_returns_user` |
| `test_bad_email` | `test_create_user_with_invalid_email_raises_validation_error` |

#### Safe Rename Process

1. **Rename one test at a time**
2. **Run tests after each rename** - Ensure nothing broke
3. **Update any test references** - If tests call each other
4. **Commit after each file** - Atomic changes

#### Automation Script

```python
#!/usr/bin/env python3
"""Suggest test name improvements."""

import re
import sys
from pathlib import Path

PATTERNS = [
    (r"test_(\w+)_fail$", r"test_\1_with_invalid_input_raises_error"),
    (r"test_(\w+)_success$", r"test_\1_with_valid_input_returns_result"),
    (r"test_(\w+)_error$", r"test_\1_with_invalid_input_raises_error"),
]

def suggest_rename(test_name: str) -> str | None:
    for pattern, replacement in PATTERNS:
        if re.match(pattern, test_name):
            return re.sub(pattern, replacement, test_name)
    return None

def analyze_file(path: Path) -> None:
    content = path.read_text()
    for match in re.finditer(r"def (test_\w+)\(", content):
        old_name = match.group(1)
        suggestion = suggest_rename(old_name)
        if suggestion:
            print(f"{path}:{old_name} → {suggestion}")

if __name__ == "__main__":
    for path in Path("tests").rglob("test_*.py"):
        analyze_file(path)
```

### Phase 4: Type Hints (Days 8-10)

**Goal**: Add type hints to all test functions and fixtures.

#### Required Type Hints

```python
# Before
def test_create_user(client, db):
    ...

# After
def test_create_user_with_valid_data_returns_user(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    ...
```

#### Fixture Type Hints

```python
# Before
@pytest.fixture
def client():
    ...

# After
@pytest.fixture
async def client() -> AsyncGenerator[AsyncClient, None]:
    ...
```

### Phase 5: Cleanup (Days 11-14)

**Goal**: Remove non-standard patterns.

1. **Replace print with logging or remove**

   ```python
   # Before
   print(f"Created user: {user}")

   # After - remove debugging prints entirely
   # or use structlog if debugging is needed
   ```

2. **Remove commented-out tests**
   - If a test is commented, delete it
   - If it was important, it's in git history

3. **Remove duplicate tests**
   - Identify tests that test the same thing
   - Keep the better-named one

4. **Consolidate fixtures**
   - Move shared fixtures to conftest.py
   - Remove duplicate fixture definitions

### Phase 6: Verification (Day 15)

**Goal**: Confirm migration is complete.

1. **Run compliance check**

   ```bash
   # Check naming
   grep -r "def test_" tests/ | grep -v "_with_\|_when_\|_returns_\|_raises_"
   # Should return empty

   # Check type hints
   mypy tests/ --strict
   # Should pass

   # Check coverage
   pytest --cov --cov-fail-under=90
   # Should pass
   ```

2. **Update migration tracking**

   ```yaml
   # tests/MIGRATION.yaml
   migration_complete: true
   completed_date: "2025-02-15"
   final_compliance: 100%
   ```

## Common Migration Challenges

### Challenge: Tests with Side Effects

**Problem**: Tests that modify global state or depend on execution order.

**Solution**:

1. Identify interdependent tests
2. Add proper setup/teardown
3. Use fixtures with appropriate scope
4. Isolate database state per test

### Challenge: Slow Tests

**Problem**: Integration tests that take too long.

**Solution**:

1. Mark slow tests with `@pytest.mark.slow`
2. Run fast tests in CI, slow tests nightly
3. Consider converting some to unit tests with mocks

### Challenge: Flaky Tests

**Problem**: Tests that pass/fail randomly.

**Solution**:

1. Identify flaky tests: run 10x and track failures
2. Fix timing issues (add proper waits, remove sleeps)
3. Fix state issues (proper isolation)
4. If unfixable, quarantine and track

```python
@pytest.mark.flaky(reruns=3, reason="Database timing issue - JIRA-123")
def test_concurrent_writes_eventually_consistent():
    ...
```

### Challenge: Missing Assertions

**Problem**: Tests that don't actually verify anything.

**Solution**:

1. Find tests with no `assert` statements
2. Determine what should be verified
3. Add meaningful assertions

```bash
# Find tests without assertions
grep -L "assert" tests/unit/*.py
```

## Migration Metrics

Track progress with these metrics:

| Metric | Target | How to Measure |
|--------|--------|----------------|
| Naming compliance | 100% | Grep for non-compliant names |
| Type hint coverage | 100% | mypy --strict |
| Print statements | 0 | Grep for print/console.log |
| Commented tests | 0 | Grep for # def test_ |
| Duplicate tests | 0 | Manual review |

## Migration Checklist Template

```markdown
# Test Migration Checklist: [Project Name]

## Assessment
- [ ] Count total tests: ___
- [ ] Count compliant tests: ___
- [ ] Identify high-priority files
- [ ] Create MIGRATION.yaml

## Infrastructure
- [ ] Update conftest.py with standard fixtures
- [ ] Organize test directories (unit/integration)
- [ ] Add pytest configuration

## Naming (per file)
- [ ] tests/unit/test_auth.py
- [ ] tests/unit/test_user.py
- [ ] tests/unit/test_...
- [ ] tests/integration/test_...

## Type Hints
- [ ] All fixtures have return type hints
- [ ] All test functions return None
- [ ] mypy --strict passes

## Cleanup
- [ ] Remove all print statements
- [ ] Remove commented tests
- [ ] Remove duplicate tests
- [ ] Consolidate fixtures

## Verification
- [ ] All tests pass
- [ ] Coverage >= 90%
- [ ] Naming grep returns empty
- [ ] mypy --strict passes
```

## See Also

- [Test Requirements](requirements.md)
- [Test Helpers](test-helpers.md)
- [AI Coordination](../operations/ai-coordination.md)
