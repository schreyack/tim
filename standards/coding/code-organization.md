# Code Organization Standards

This document defines standards for code organization, file size limits, and complexity controls. These are **critical for AI-assisted development** because AI developers struggle with large, complex files.

## Why This Matters for AI Development

AI developers have specific limitations:

1. **Context window limits** - AI can only process ~200K tokens at once. Large files get truncated or summarized, leading to incomplete understanding.

2. **Edit accuracy degrades** - AI making changes to large files is more likely to:
   - Miss related code that needs updating
   - Make inconsistent changes across the file
   - Lose track of imports, variable names, or function signatures
   - Create merge conflicts with itself

3. **Review difficulty** - Humans reviewing AI changes in large files cannot effectively verify correctness.

4. **Hallucination risk** - In large files, AI may "remember" code that doesn't exist or forget code that does.

## File Size Limits

### Maximum Lines Per File

| File Type | Max Lines | Rationale |
|-----------|-----------|-----------|
| Source code (`.py`, `.ts`) | **400 lines** | AI accuracy degrades significantly above this |
| Test files | **500 lines** | Tests can be longer due to fixtures/setup |
| Configuration | **200 lines** | Split large configs into multiple files |
| Type definitions | **300 lines** | Group related types, split by domain |

### Enforcement

```yaml
# .pre-commit-config.yaml (Python)
repos:
  - repo: local
    hooks:
      - id: file-size-check
        name: Check file size
        entry: bash -c 'for f in $(find src -name "*.py"); do lines=$(wc -l < "$f"); if [ $lines -gt 400 ]; then echo "ERROR: $f has $lines lines (max 400)"; exit 1; fi; done'
        language: system
        pass_filenames: false
```

```yaml
# eslint.config.js (TypeScript) - using eslint-plugin-file-size
export default [
  {
    plugins: { "file-size": fileSizePlugin },
    rules: {
      "file-size/max-lines": ["error", { max: 400, skipBlankLines: true, skipComments: true }],
    },
  },
];
```

## Function/Method Limits

### Maximum Lines Per Function

| Metric | Limit | Rationale |
|--------|-------|-----------|
| Function body | **50 lines** | Fits in one screen, easy to understand |
| Cyclomatic complexity | **10** | More branches = more bugs |
| Cognitive complexity | **15** | Measures mental effort to understand |
| Parameters | **5** | More parameters = harder to call correctly |
| Nesting depth | **4** | Deep nesting is hard to follow |

### Python Enforcement (ruff)

```toml
# pyproject.toml
[tool.ruff.lint]
select = [
    "C901",  # McCabe complexity
    "PLR0911",  # Too many return statements
    "PLR0912",  # Too many branches
    "PLR0913",  # Too many arguments
    "PLR0915",  # Too many statements
]

[tool.ruff.lint.mccabe]
max-complexity = 10

[tool.ruff.lint.pylint]
max-args = 5
max-branches = 12
max-returns = 6
max-statements = 50
```

### TypeScript Enforcement (ESLint)

```javascript
// eslint.config.js
export default [
  {
    rules: {
      "max-lines-per-function": ["error", { max: 50, skipBlankLines: true, skipComments: true }],
      "max-depth": ["error", 4],
      "max-params": ["error", 5],
      "complexity": ["error", 10],
      "max-nested-callbacks": ["error", 3],
    },
  },
];
```

## File Organization Patterns

### Single Responsibility Principle

Each file should have ONE clear purpose:

```text
# GOOD: Clear separation
src/
├── models/
│   ├── user.py          # User model only
│   ├── project.py       # Project model only
│   └── stem.py          # Stem model only
├── services/
│   ├── user_service.py  # User business logic
│   └── audio_service.py # Audio processing
└── api/
    ├── users.py         # User endpoints
    └── projects.py      # Project endpoints

# BAD: Everything dumped together
src/
├── models.py            # 2000 lines, all models
├── services.py          # 1500 lines, all business logic
└── api.py               # 800 lines, all endpoints
```

### Splitting Large Files

When a file exceeds limits, split by:

1. **By domain/entity** - User code in one file, Project code in another
2. **By layer** - Models, services, API handlers separate
3. **By operation** - CRUD operations can be split (create, read, update, delete)
4. **By complexity** - Complex algorithms in dedicated modules

```python
# BEFORE: One large file (600+ lines)
# src/services/audio.py

# AFTER: Split by operation
# src/services/audio/
# ├── __init__.py        # Re-exports public API
# ├── upload.py          # Upload handling (80 lines)
# ├── processing.py      # Audio processing (120 lines)
# ├── stems.py           # Stem separation (150 lines)
# └── export.py          # Export functionality (90 lines)
```

### Import Pattern for Split Files

```python
# src/services/audio/__init__.py
"""Audio service - split across modules for maintainability."""

from .upload import upload_audio, validate_upload
from .processing import process_audio, normalize_audio
from .stems import separate_stems, merge_stems
from .export import export_audio, export_stems

__all__ = [
    "upload_audio",
    "validate_upload",
    "process_audio",
    "normalize_audio",
    "separate_stems",
    "merge_stems",
    "export_audio",
    "export_stems",
]
```

```python
# Usage remains clean
from src.services.audio import process_audio, separate_stems
```

## Class Size Limits

### Maximum Methods Per Class

| Metric | Limit | Rationale |
|--------|-------|-----------|
| Methods per class | **10** | Classes doing too much should be split |
| Lines per class | **300** | Includes methods, properties, docstrings |
| Instance attributes | **10** | Too many = poor cohesion |

### Enforcement

```toml
# pyproject.toml
[tool.ruff.lint.pylint]
max-public-methods = 10
max-attributes = 10
```

## Import Organization

### Python Import Order (enforced by ruff)

```python
# 1. Standard library
import os
from datetime import datetime

# 2. Third-party packages
from fastapi import APIRouter
from sqlalchemy import Column

# 3. Local application imports
from src.models import User
from src.services import UserService
```

### TypeScript Import Order (enforced by ESLint)

```typescript
// 1. Node built-ins
import { readFile } from "fs/promises";

// 2. External packages
import express from "express";
import { z } from "zod";

// 3. Internal packages (@tim/lib, etc.)
import { createLogger } from "@tim/lib";

// 4. Relative imports
import { UserService } from "./services/user";
import type { User } from "./types";
```

## Complexity Reduction Patterns

### Extract Early Returns

```python
# BAD: Deep nesting
def process_user(user):
    if user is not None:
        if user.is_active:
            if user.has_permission("edit"):
                # actual logic buried here
                return do_something(user)
    return None

# GOOD: Early returns
def process_user(user):
    if user is None:
        return None
    if not user.is_active:
        return None
    if not user.has_permission("edit"):
        return None

    return do_something(user)
```

### Extract Helper Functions

```python
# BAD: Long function doing multiple things
def process_order(order):
    # 20 lines of validation
    # 30 lines of price calculation
    # 25 lines of inventory check
    # 40 lines of payment processing
    # 20 lines of notification
    pass  # 135 lines total

# GOOD: Split into focused functions
def process_order(order):
    validate_order(order)           # 20 lines in separate function
    total = calculate_total(order)  # 30 lines
    check_inventory(order)          # 25 lines
    process_payment(order, total)   # 40 lines
    send_notifications(order)       # 20 lines
```

### Use Data Classes / Types

```python
# BAD: Function with many parameters
def create_user(name, email, password, role, department, manager_id, start_date, ...):
    pass

# GOOD: Use a data class
@dataclass
class CreateUserRequest:
    name: str
    email: str
    password: str
    role: str
    department: str | None = None
    manager_id: str | None = None
    start_date: date | None = None

def create_user(request: CreateUserRequest):
    pass
```

## CI Integration

### Python CI Check

Add to `.github/workflows/ci.yml`:

```yaml
lint:
  steps:
    - name: Check complexity
      run: |
        poetry run ruff check src/ --select=C901,PLR0911,PLR0912,PLR0913,PLR0915

    - name: Check file sizes
      run: |
        echo "Checking file sizes (max 400 lines)..."
        for f in $(find src -name "*.py" -type f); do
          lines=$(wc -l < "$f")
          if [ $lines -gt 400 ]; then
            echo "ERROR: $f has $lines lines (max 400)"
            exit 1
          fi
        done
        echo "All files within size limits"
```

### TypeScript CI Check

Add to `.github/workflows/ci.yml`:

```yaml
lint:
  steps:
    - name: Check complexity
      run: npm run lint -- --rule 'complexity: [error, 10]' --rule 'max-lines-per-function: [error, 50]'

    - name: Check file sizes
      run: |
        echo "Checking file sizes (max 400 lines)..."
        for f in $(find src -name "*.ts" -type f); do
          lines=$(wc -l < "$f")
          if [ $lines -gt 400 ]; then
            echo "ERROR: $f has $lines lines (max 400)"
            exit 1
          fi
        done
        echo "All files within size limits"
```

## Warning Thresholds vs Hard Limits

| Metric | Warning (Consider Refactoring) | Hard Limit (Blocked) |
|--------|-------------------------------|---------------------|
| File size | 300 lines | 400 lines |
| Function size | 40 lines | 50 lines |
| Complexity | 8 | 10 |

## When to Request Human Review

AI developers should request human review when:

1. **A file would exceed 300 lines** - Consider splitting before hitting 400 limit
2. **A function would exceed 40 lines** - Consider extracting helpers before hitting 50 limit
3. **Complexity exceeds 8** - Consider simplifying before hitting 10 limit
4. **Unsure how to split** - Human can advise on architecture

## Summary

| Metric | Limit | Enforced By |
|--------|-------|-------------|
| File size | 400 lines | CI script |
| Function size | 50 lines | ruff/ESLint |
| Cyclomatic complexity | 10 | ruff/ESLint |
| Cognitive complexity | 15 | ruff/ESLint |
| Function parameters | 5 | ruff/ESLint |
| Nesting depth | 4 | ruff/ESLint |
| Class methods | 10 | ruff |
| Class attributes | 10 | ruff |

These limits are chosen specifically for AI development effectiveness. They are stricter than typical industry standards because AI accuracy degrades faster than human productivity as complexity increases.
