# TIM Templates

Ready-to-copy configuration files that implement TIM Design Standards.

## Template Index

### Python Stack

| Template | Purpose | Standards Implemented |
|----------|---------|----------------------|
| `python/.pre-commit-config.yaml` | Pre-commit hooks | [Gate 1](../standards/enforcement/gates.md#gate-1-local) |

*Planned: pyproject.toml, mypy.ini*

### Node.js Stack

| Template | Purpose | Standards Implemented |
|----------|---------|----------------------|
| `node/.pre-commit-config.yaml` | Pre-commit hooks | [Gate 1](../standards/enforcement/gates.md#gate-1-local) |

*Planned: package.json, tsconfig.json, eslint.config.js*

### CI/CD

*Planned: python-ci.yml, node-ci.yml, security-scan.yml*

### Operations

| Template | Purpose | Standards Implemented |
|----------|---------|----------------------|
| `ops/ops.sh.template` | Deployment script | [ops-script](../standards/deployment/ops-script.md) |
| `ops/ops-config.yaml.template` | Ops configuration | [ops-script](../standards/deployment/ops-script.md) |

### Plans

| Template | Purpose | Standards Implemented |
|----------|---------|----------------------|
| `plan.md.template` | Plan document | [Plan Management](../standards/operations/plan-management.md) |
| `CLAUDE.md.template` | Project instructions | All standards |
| `tim-patterns.yaml.template` | Pattern registry | [Pattern Compliance](../standards/enforcement/strict-compliance.md) |

## Usage

### New Python Project

```bash
# Copy Python templates
cp templates/python/.pre-commit-config.yaml my-project/
cp templates/CLAUDE.md.template my-project/CLAUDE.md
cp templates/tim-patterns.yaml.template my-project/.tim-patterns.yaml
cp templates/plan.md.template my-project/plans/

# Customize CLAUDE.md for your project
# Install pre-commit hooks
cd my-project && pre-commit install
```

### New Node.js Project

```bash
# Copy Node.js templates
cp templates/node/.pre-commit-config.yaml my-project/
cp templates/CLAUDE.md.template my-project/CLAUDE.md
cp templates/tim-patterns.yaml.template my-project/.tim-patterns.yaml
cp templates/plan.md.template my-project/plans/

# Customize CLAUDE.md for your project
# Install pre-commit hooks
cd my-project && pre-commit install
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
- [Plan Lifecycle Management](../standards/operations/plan-management.md) - Plan creation and approval workflow
- [Graduated Enforcement](../standards/enforcement/graduated-enforcement.md) - For migration
- [Working Examples](../examples/) - Complete reference implementations
- [Shared Libraries](../standards/architecture/shared-libraries.md)
