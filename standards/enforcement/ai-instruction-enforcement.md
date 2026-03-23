# AI Instruction Enforcement Standard

This document defines mechanisms to detect and prevent AI developers from ignoring project instructions.

## The Problem

AI developers will ignore instructions when:

1. Instructions are only documented, not enforced
2. There's no consequence for violation
3. The AI "forgets" mid-session
4. Instructions conflict with AI's training patterns

**Core principle**: If a rule is only documented, it will be ignored. Rules must be machine-enforced.

## Enforcement Layers

### Layer 1: Pre-Commit Hooks (Blocking)

Rules enforced at commit time. AI cannot commit code that violates these.

#### Python Pre-Commit Enforcement

```yaml
# .pre-commit-config.yaml
repos:
  - repo: local
    hooks:
      # Block TODO/FIXME comments
      - id: no-todos
        name: No TODO/FIXME comments
        entry: bash -c 'if grep -rn "TODO\|FIXME\|XXX\|HACK" --include="*.py" src/; then echo "ERROR: Remove TODO/FIXME comments before committing"; exit 1; fi'
        language: system
        pass_filenames: false

      # Block print statements (must use logging)
      - id: no-print
        name: No print statements
        entry: bash -c 'if grep -rn "^\s*print(" --include="*.py" src/; then echo "ERROR: Use logging instead of print()"; exit 1; fi'
        language: system
        pass_filenames: false

      # Block bare except clauses
      - id: no-bare-except
        name: No bare except clauses
        entry: bash -c 'if grep -rn "except:" --include="*.py" src/ | grep -v "except:.*#.*noqa"; then echo "ERROR: Catch specific exceptions"; exit 1; fi'
        language: system
        pass_filenames: false

      # Block placeholder implementations
      - id: no-placeholders
        name: No placeholder code
        entry: bash -c 'if grep -rn "NotImplementedError\|pass\s*$\|\.\.\.$$" --include="*.py" src/; then echo "ERROR: No placeholder implementations"; exit 1; fi'
        language: system
        pass_filenames: false
```

#### Node.js Pre-Commit Enforcement

```yaml
repos:
  - repo: local
    hooks:
      # Block TODO/FIXME comments
      - id: no-todos
        name: No TODO/FIXME comments
        entry: bash -c 'if grep -rn "TODO\|FIXME\|XXX\|HACK" --include="*.ts" src/; then echo "ERROR: Remove TODO/FIXME comments"; exit 1; fi'
        language: system
        pass_filenames: false

      # Block console.log (must use logger)
      - id: no-console-log
        name: No console.log
        entry: bash -c 'if grep -rn "console\.log\|console\.debug\|console\.info" --include="*.ts" src/; then echo "ERROR: Use logger instead of console"; exit 1; fi'
        language: system
        pass_filenames: false

      # Block any type
      - id: no-any
        name: No any type
        entry: bash -c 'if grep -rn ": any\|as any\|<any>" --include="*.ts" src/; then echo "ERROR: No any types allowed"; exit 1; fi'
        language: system
        pass_filenames: false
```

### Layer 2: Ruff/ESLint Configuration

Extend linting to catch CLAUDE.md violations.

#### Python (ruff)

```toml
# pyproject.toml
[tool.ruff.lint]
select = [
    "E", "W",      # pycodestyle
    "F",           # pyflakes
    "I",           # isort
    "B",           # flake8-bugbear
    "C4",          # flake8-comprehensions
    "UP",          # pyupgrade
    "S",           # flake8-bandit (security)
    "T20",         # flake8-print (blocks print statements)
    "SIM",         # flake8-simplify
    "TCH",         # flake8-type-checking
    "ERA",         # eradicate (removes commented code)
    "FIX",         # flake8-fixme (blocks TODO/FIXME)
    "TD",          # flake8-todos (blocks TODOs)
    "PL",          # pylint
    "RUF",         # ruff-specific
]

[tool.ruff.lint.flake8-fixme]
# Block ALL fixme-like comments
check = ["FIXME", "TODO", "XXX", "HACK", "BUG"]

[tool.ruff.lint.pylint]
max-args = 5
max-branches = 12
max-returns = 6
max-statements = 50
```

#### TypeScript (ESLint)

```javascript
// eslint.config.js
export default [
  {
    rules: {
      // Block TODO/FIXME
      "no-warning-comments": ["error", {
        terms: ["todo", "fixme", "xxx", "hack", "bug"],
        location: "anywhere"
      }],

      // Block console
      "no-console": "error",

      // Block any
      "@typescript-eslint/no-explicit-any": "error",

      // Block non-null assertions
      "@typescript-eslint/no-non-null-assertion": "error",

      // Require return types
      "@typescript-eslint/explicit-function-return-type": "error",
    }
  }
];
```

### Layer 3: CI Verification

CI runs comprehensive checks that cannot be bypassed.

```yaml
# .github/workflows/ci.yml
- name: Verify CLAUDE.md compliance
  run: |
    echo "Checking for CLAUDE.md violations..."

    # Check for TODO/FIXME
    if grep -rn "TODO\|FIXME\|XXX\|HACK" --include="*.py" --include="*.ts" src/; then
      echo "::error::TODO/FIXME comments found - remove before merge"
      exit 1
    fi

    # Check for print/console.log
    if grep -rn "^\s*print(" --include="*.py" src/; then
      echo "::error::print() found - use logging"
      exit 1
    fi
    if grep -rn "console\.log" --include="*.ts" src/; then
      echo "::error::console.log found - use logger"
      exit 1
    fi

    # Check for bare except
    if grep -rn "except:" --include="*.py" src/ | grep -v "noqa"; then
      echo "::error::Bare except found - catch specific exceptions"
      exit 1
    fi

    # Check for placeholder code
    if grep -rn "NotImplementedError\|raise NotImplementedError" --include="*.py" src/; then
      echo "::error::NotImplementedError found - implement fully"
      exit 1
    fi

    # Check for any type
    if grep -rn ": any\|as any" --include="*.ts" src/; then
      echo "::error::any type found - use proper types"
      exit 1
    fi

    echo "All CLAUDE.md compliance checks passed"
```

### Layer 4: Pattern Detection

Detect when AI uses patterns that aren't registered.

```bash
#!/bin/bash
# tools/detect-unregistered-patterns.sh

# Check for common patterns that must be registered

# Redis usage
if grep -rn "redis\|Redis\|REDIS" --include="*.py" --include="*.ts" src/; then
  if ! grep -q "caching:.*redis" .tim-patterns.yaml; then
    echo "ERROR: Redis usage detected but not registered in .tim-patterns.yaml"
    exit 1
  fi
fi

# WebSocket usage
if grep -rn "websocket\|WebSocket\|socket\.io" --include="*.py" --include="*.ts" src/; then
  if ! grep -q "realtime:" .tim-patterns.yaml; then
    echo "ERROR: WebSocket usage detected but not registered"
    exit 1
  fi
fi

# Background task patterns
if grep -rn "celery\|Celery\|BackgroundTasks" --include="*.py" src/; then
  if ! grep -q "background_tasks:" .tim-patterns.yaml; then
    echo "ERROR: Background task pattern detected but not registered"
    exit 1
  fi
fi
```

## Common AI Violations and Detection

| Violation | Detection Method | Enforcement Point |
|-----------|-----------------|-------------------|
| TODO/FIXME comments | grep + FIX rule | Pre-commit, CI |
| print() instead of logging | T20 rule + grep | Pre-commit, CI |
| Bare except clauses | B001 rule | Pre-commit, CI |
| any type in TypeScript | ESLint rule | Pre-commit, CI |
| console.log | ESLint rule | Pre-commit, CI |
| Placeholder code | grep for NotImplementedError | Pre-commit, CI |
| Missing type hints | mypy --strict | Pre-commit, CI |
| Unregistered patterns | Pattern detector | CI, Deploy |
| Commented-out code | ERA rule | Pre-commit, CI |

## Session Acknowledgment

For Claude Code specifically, include this in the project's CLAUDE.md:

```markdown
## AI Developer Acknowledgment

Before making any changes, confirm you have read and will follow:
1. All rules in this CLAUDE.md file
2. The test naming convention (test_what_when_then)
3. The file size limits (500 lines max)
4. The requirement to use tim-lib for common patterns

If you are uncertain about any rule, ASK before proceeding.

Rules you MUST follow:
- NO TODO/FIXME comments - implement fully or don't add
- NO print() - use logging module
- NO bare except - catch specific exceptions
- NO placeholder code - implement completely
- ALL functions need type hints and return types
```

## Enforcement Priority

Implement in this order:

1. **Pre-commit hooks** (blocks at source)
2. **Ruff/ESLint configuration** (detailed error messages)
3. **CI checks** (server-side enforcement, unbypassed)
4. **Pattern detection** (catches architectural violations)

## Escalation When Violations Detected

When AI code fails enforcement:

1. **Immediate block** - Cannot commit/merge
2. **Clear error message** - Explains what rule was violated
3. **Reference to standard** - Links to documentation
4. **No exceptions** - Must fix, cannot bypass

## Measuring Effectiveness

Track these metrics:

| Metric | Target | Measurement |
|--------|--------|-------------|
| Pre-commit violations/week | Decreasing | Git hook logs |
| CI failures from CLAUDE.md rules | < 5% of PRs | CI metrics |
| Unregistered pattern detections | 0 | Pattern detector logs |
| Human escalations for confusion | Decreasing | Escalation tracking |

## See Also

- [AI Review Checklist](ai-review-checklist.md)
- [Gates](gates.md)
- [Strict Compliance](strict-compliance.md)
