# Shared Libraries Standard

TIM projects must use shared libraries for common functionality. This prevents code drift, ensures consistency, and centralizes maintenance.

**Philosophy**: Write once, import everywhere. When you fix a bug or add a feature, all projects benefit automatically.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          TIM SHARED LIBRARIES                                │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │                    tim (THIS REPO)                       │   │
│  │  ├── templates/ops/tim-ops-lib.sh   ← Ops: Bash library              │   │
│  │  ├── libs/python/tim_lib/           ← Python: tim-lib                │   │
│  │  └── libs/node/                      ← Node.js: @tim/lib              │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
│                           │                                                  │
│                           │ Git submodule OR                                 │
│                           │ Package install                                  │
│                           ▼                                                  │
│  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐          │
│  │   Project A      │  │   Project B      │  │   Project C      │          │
│  │                  │  │                  │  │                  │          │
│  │  Uses:           │  │  Uses:           │  │  Uses:           │          │
│  │  - tim-ops-lib   │  │  - tim-ops-lib   │  │  - tim-ops-lib   │          │
│  │  - tim-lib (py)  │  │  - @tim/lib (js) │  │  - tim-lib (py)  │          │
│  └──────────────────┘  └──────────────────┘  └──────────────────┘          │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Shared Libraries

### 1. tim-ops-lib (Bash)

The ops.sh deployment library. Already implemented in `templates/ops/tim-ops-lib.sh`.

**Provides:**
- Deployment commands (deploy, rollback, status)
- Safety tiers (SAFE, MODERATE, HUMAN_REQUIRED, BLOCKED)
- Health checks
- Audit logging
- Notifications

**Usage:**
```bash
# In project's ops.sh
source "$PROJECT_ROOT/.tim-ops/tim-ops-lib.sh"
load_config "ops-config.yaml"
tim_ops_main "$@"
```

### 2. tim-py (Python)

Shared Python library for all TIM Python projects.

**Provides:**
- `tim_lib.config` - Pydantic base settings with common patterns
- `tim_lib.logging` - Structured logging setup (structlog)
- `tim_lib.security` - Password hashing, JWT helpers
- `tim_lib.db` - SQLAlchemy session patterns, health checks
- `tim_lib.api` - FastAPI middleware, error handlers
- `tim_lib.testing` - Test fixtures, factories

**Installation:**
```bash
# Option 1: Git submodule
git submodule add https://github.com/your-org/tim lib/tim
pip install -e lib/tim/libs/python

# Option 2: Direct pip install (when published)
pip install tim-lib
```

### 3. @tim/lib (Node.js/TypeScript)

Shared TypeScript library for all TIM Node.js projects.

**Provides:**
- `@tim/config` - Zod-based config validation
- `@tim/logging` - Structured logging (pino)
- `@tim/security` - Password hashing (bcrypt), JWT helpers
- `@tim/db` - Prisma utilities, health checks
- `@tim/api` - Express middleware, error handlers
- `@tim/testing` - Test utilities, factories

**Installation:**
```bash
# Option 1: Git submodule
git submodule add https://github.com/your-org/tim lib/tim
npm install ./lib/tim/libs/node

# Option 2: npm package (when published)
npm install @tim/lib
```

## Distribution Methods

### Method 1: Git Submodule + Symlinks (Recommended)

Best for small teams with private repos. Ensures consistent, immutable enforcement.

```bash
# Add tim as submodule
git submodule add https://github.com/your-org/tim lib/tim
# OR for local repos:
git submodule add /path/to/tim lib/tim

# Symlink enforcement configs (Python)
ln -s lib/tim/templates/python/.pre-commit-config.yaml .pre-commit-config.yaml
# OR for Node.js:
ln -s lib/tim/templates/node/.pre-commit-config.yaml .pre-commit-config.yaml

# Make symlinks immutable (prevents AI bypass)
sudo chflags -h schg .pre-commit-config.yaml

# Update to latest
cd lib/tim && git pull origin main
cd ../.. && git add lib/tim && git commit -m "chore: update tim submodule"

# In pyproject.toml
[tool.poetry.dependencies]
tim-lib = { path = "lib/tim/libs/python", develop = true }

# In package.json
"dependencies": {
  "@tim/lib": "file:lib/tim/libs/node"
}
```

**Why symlinks + immutability?**
- Symlinks ensure all projects use identical configs from tim
- `chflags -h schg` makes the symlink itself immutable (not just the target)
- AI cannot remove, modify, or redirect the symlink to bypass enforcement

**Pros:**
- Consistent enforcement across all projects
- Single source of truth in tim repo
- Immutable - AI cannot bypass
- Full source access for debugging

**Cons:**
- Must update submodule when tim changes
- Everyone needs repo access
- macOS-specific immutability (Linux uses `chattr +i`)

### Method 2: Package Registry (Future)

Best for larger teams or open-source.

```bash
# Python (PyPI or private registry)
pip install tim-lib==1.0.0

# Node.js (npm or private registry)
npm install @tim/lib@1.0.0
```

**Pros:**
- Semantic versioning
- Easy dependency management
- CI/CD can publish automatically

**Cons:**
- Requires registry setup
- More infrastructure to maintain

### Method 3: Auto-Download (Like tim-ops-lib)

For simple cases. Library downloads on first run.

```bash
# In ops.sh (already implemented)
TIM_OPS_LIB="${TIM_OPS_LIB:-$PROJECT_ROOT/.tim-ops/tim-ops-lib.sh}"
if [[ ! -f "$TIM_OPS_LIB" ]]; then
    curl -sSL "$TIM_OPS_URL" -o "$TIM_OPS_LIB"
fi
source "$TIM_OPS_LIB"
```

## Versioning Strategy

All shared libraries follow semantic versioning:

```
MAJOR.MINOR.PATCH

MAJOR: Breaking changes (API changed)
MINOR: New features (backwards compatible)
PATCH: Bug fixes (backwards compatible)
```

### Version Pinning

Projects should pin to minor version:

```toml
# pyproject.toml
tim-lib = "^1.2.0"  # Allows 1.2.x, not 1.3.0

# package.json
"@tim/lib": "~1.2.0"  # Allows 1.2.x, not 1.3.0
```

### Upgrade Process

1. **Release new version** of shared library
2. **Update one project** and test thoroughly
3. **Roll out to other projects** after validation
4. **Security fixes**: Push to all projects immediately

## What Goes in Shared Libraries

### DO Include

| Category | Examples |
|----------|----------|
| Configuration | Base settings classes, env validation |
| Logging | Structured logging setup, formatters |
| Security | Password hashing, JWT, rate limiting |
| Database | Session management, health checks |
| API | Middleware, error handlers, validators |
| Testing | Fixtures, factories, utilities |
| Observability | Metrics setup, tracing config |

### DO NOT Include

| Category | Why |
|----------|-----|
| Business logic | Project-specific, changes frequently |
| Database models | Project-specific schemas |
| API routes | Project-specific endpoints |
| UI components | Project-specific design |
| Configuration values | Secrets, environment-specific |

## Implementation Guidelines

### Adding to Shared Library

Before adding code to a shared library:

1. **Is it used by 2+ projects?** If only one project needs it, keep it there.
2. **Is it stable?** Don't add code that's still changing rapidly.
3. **Is it generic?** Must work for any project without modification.
4. **Does it have tests?** Shared code requires high test coverage.

### Breaking Changes

When making breaking changes:

1. **Document migration path** in CHANGELOG
2. **Provide deprecation warnings** for at least one minor version
3. **Update all TIM projects** in coordinated release
4. **Never break in patch releases**

```python
# Example deprecation
import warnings

def old_function():
    """Deprecated: Use new_function instead."""
    warnings.warn(
        "old_function is deprecated, use new_function",
        DeprecationWarning,
        stacklevel=2
    )
    return new_function()
```

## Directory Structure

```
tim/
├── libs/
│   ├── python/
│   │   ├── pyproject.toml
│   │   ├── tim_lib/
│   │   │   ├── __init__.py
│   │   │   ├── config.py      # Configuration utilities
│   │   │   ├── logging.py     # Logging setup
│   │   │   ├── security.py    # Security helpers
│   │   │   ├── db.py          # Database utilities
│   │   │   ├── api.py         # API middleware
│   │   │   └── testing.py     # Test utilities
│   │   └── tests/
│   │       └── test_*.py
│   │
│   └── node/
│       ├── package.json
│       ├── tsconfig.json
│       ├── src/
│       │   ├── index.ts
│       │   ├── config.ts      # Configuration utilities
│       │   ├── logging.ts     # Logging setup
│       │   ├── security.ts    # Security helpers
│       │   ├── db.ts          # Database utilities
│       │   ├── api.ts         # API middleware
│       │   └── testing.ts     # Test utilities
│       └── tests/
│           └── *.test.ts
│
├── templates/
│   └── ops/
│       ├── tim-ops-lib.sh     # Ops library (already exists)
│       └── ...
```

## Checklist for Projects

- [ ] Add tim as git submodule: `git submodule add ... lib/tim`
- [ ] Install tim-lib in dependencies
- [ ] Import and use shared config base
- [ ] Use shared logging setup
- [ ] Use shared security helpers (don't roll your own crypto)
- [ ] Update submodule periodically: `git submodule update --remote`
- [ ] Pin to stable version for production
