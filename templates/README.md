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

---

## AI Development Feedback Loop

These templates implement a tight feedback loop optimized for AI development. The key insight: **AI agents don't get frustrated by repetition.** When code fails, AI simply tries again.

### The Unified Check Command

Every project should have a single command that runs all verification:

```bash
# Node.js (in package.json scripts)
npm run check

# Python (in pyproject.toml with poethepoet)
poe check
```

The `check` command should run, in order:

| Step | What It Catches | Typical Time |
|------|----------------|--------------|
| Type check (`tsc`/`mypy`) | Type errors, undefined references | 5-15s |
| Lint (`eslint`/`ruff`) | Code style, potential bugs | 5-10s |
| Format check | Formatting inconsistencies | 2-5s |
| Tests | Logic errors, regressions | 30s-2min |

### Why This Order Matters

1. **Type errors first** - Fastest feedback, catches hallucinated types
2. **Lint second** - Catches issues that types miss
3. **Format third** - Quick, rarely fails if editor configured
4. **Tests last** - Slowest, but catches everything else

### Pre-commit Hooks

Templates include pre-commit hooks that run `check` automatically. This is critical for AI development:

- AI cannot commit broken code
- AI gets immediate feedback
- AI iterates until all checks pass

### Example package.json Scripts

```json
{
  "scripts": {
    "check": "npm run typecheck && npm run lint && npm run format:check && npm run test",
    "typecheck": "tsc --noEmit",
    "lint": "eslint . --max-warnings 0",
    "format:check": "prettier --check .",
    "test": "vitest run --coverage"
  }
}
```

### Strictness Is the Feature

All templates enforce strict settings by default:

- `tsconfig.json`: `"strict": true`
- `eslint`: `--max-warnings 0`
- Coverage: 90% minimum threshold

These aren't obstacles - they're the quality gates that make AI development reliable.

See: [AFK Coding Patterns](../standards/operations/afk-coding-patterns.md) for extended autonomous development.

---

## See Also

- [Four-Gate Enforcement Model](../standards/enforcement/gates.md)
- [Plan Lifecycle Management](../standards/operations/plan-management.md) - Plan creation and approval workflow
- [Graduated Enforcement](../standards/enforcement/graduated-enforcement.md) - For migration
- [Working Examples](../examples/) - Complete reference implementations
- [Shared Libraries](../standards/architecture/shared-libraries.md)
