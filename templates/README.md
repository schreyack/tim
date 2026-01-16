# TIM Templates

Ready-to-copy configuration files that implement TIM Design Standards.

## Template Index

### Python Stack

| Template | Purpose | Standards Implemented |
|----------|---------|----------------------|
| `python/pyproject.toml` | Poetry project config | [Python Standard](../standards/coding/python.md), [Testing](../standards/testing/requirements.md) |
| `python/.pre-commit-config.yaml` | Pre-commit hooks | [Gate 1](../standards/enforcement/gates.md#gate-1-local) |
| `python/mypy.ini` | Type checking config | [Python Standard](../standards/coding/python.md) |

### Node.js Stack

| Template | Purpose | Standards Implemented |
|----------|---------|----------------------|
| `node/package.json` | NPM project config | [TypeScript Standard](../standards/coding/typescript.md), [Testing](../standards/testing/requirements.md) |
| `node/tsconfig.json` | TypeScript config | [TypeScript Standard](../standards/coding/typescript.md) |
| `node/eslint.config.js` | ESLint config | [Code Organization](../standards/coding/code-organization.md) |
| `node/.pre-commit-config.yaml` | Pre-commit hooks | [Gate 1](../standards/enforcement/gates.md#gate-1-local) |

### CI/CD

| Template | Purpose | Standards Implemented |
|----------|---------|----------------------|
| `ci/python-ci.yml` | GitHub Actions for Python | [Gates](../standards/enforcement/gates.md), [CI Integration](../standards/deployment/ci-integration.md) |
| `ci/node-ci.yml` | GitHub Actions for Node.js | [Gates](../standards/enforcement/gates.md), [CI Integration](../standards/deployment/ci-integration.md) |
| `ci/security-scan.yml` | Security scanning workflow | [OWASP](../standards/security/owasp-checklist.md), [Secrets](../standards/security/secrets.md) |

## Usage

### New Python Project

```bash
# Copy Python templates
cp templates/python/pyproject.toml my-project/
cp templates/python/.pre-commit-config.yaml my-project/
cp templates/ci/python-ci.yml my-project/.github/workflows/ci.yml

# Customize pyproject.toml with your project name
# Install pre-commit hooks
cd my-project && pre-commit install
```

### New Node.js Project

```bash
# Copy Node.js templates
cp templates/node/package.json my-project/
cp templates/node/tsconfig.json my-project/
cp templates/node/eslint.config.js my-project/
cp templates/node/.pre-commit-config.yaml my-project/
cp templates/ci/node-ci.yml my-project/.github/workflows/ci.yml

# Customize package.json with your project name
# Install dependencies
cd my-project && npm install
```

## Template-to-Gate Mapping

Templates are designed to enforce specific gates:

### Gate 1 (Local/Pre-commit)

- `.pre-commit-config.yaml` - Runs on every commit
- `mypy.ini` / `tsconfig.json` - Type checking
- `eslint.config.js` - Linting

### Gate 2 (CI/Pull Request)

- `*-ci.yml` - All pre-commit checks + tests + security scans
- Coverage thresholds (90%) enforced

### Gate 3 (Deploy/Pre-deployment)

- Integration and E2E tests in CI templates
- Migration dry-run steps
- Health check validation

## Customization Guidelines

When customizing templates:

1. **Keep thresholds** - Don't lower coverage from 90%
2. **Keep strictness** - Don't disable type checking rules
3. **Add, don't remove** - Add project-specific checks, don't remove standard ones
4. **Update versions** - Keep dependencies current

## Version Compatibility

Templates are tested with:

| Stack | Minimum Version |
|-------|-----------------|
| Python | 3.11+ |
| Node.js | 20+ |
| Poetry | 1.7+ |
| npm | 10+ |

### Gate 4 (Pattern Compliance)

- Pattern registry validation via compliance checker
- CUSTOM patterns require human approval

## See Also

- [Four-Gate Enforcement Model](../standards/enforcement/gates.md)
- [Graduated Enforcement](../standards/enforcement/graduated-enforcement.md) - For migration
- [Working Examples](../examples/) - Complete reference implementations
- [Shared Libraries](../standards/architecture/shared-libraries.md)
