# TIM Templates

Ready-to-copy configuration files that implement the TIM standards. These templates enforce strict type checking, file size limits, and coverage reporting, and integrate with the four-gate enforcement model.

## Template Index

### Python Stack

| Template | Purpose | Standards Implemented |
|----------|---------|----------------------|
| `python/.pre-commit-config.yaml` | Pre-commit hooks | [Gate 1](../standards/enforcement/gates.md#gate-1-local) |
| `python/pyproject.toml` | Poetry config with TIM defaults | Type checking, linting, coverage |

### Node.js Stack

| Template | Purpose | Standards Implemented |
|----------|---------|----------------------|
| `node/.pre-commit-config.yaml` | Pre-commit hooks | [Gate 1](../standards/enforcement/gates.md#gate-1-local) |
| `node/package.json` | npm config with TIM scripts | Type checking, linting, coverage |
| `node/tsconfig.json` | TypeScript strict mode config | Type safety |
| `node/eslint.config.js` | ESLint with TIM rules | Code quality |

### CI/CD

| Template | Purpose | Standards Implemented |
|----------|---------|----------------------|
| `ci/python-ci.yml` | Python CI pipeline | [Gate 2](../standards/enforcement/gates.md#gate-2-ci) |
| `ci/node-ci.yml` | Node.js CI pipeline | [Gate 2](../standards/enforcement/gates.md#gate-2-ci) |

### Operations

| Template | Purpose | Standards Implemented |
|----------|---------|----------------------|
| `environments.yaml.example` | Environment config template | [environments](../standards/deployment/environments.md) |

### Claude Code Hooks (AI Behavioral Gates)

AI behavioral gates (code quality validator, excuse detector) are bundled with the **Tim Loop plugin**. Install via the Claude Code marketplace:

```text
/plugin marketplace add schreyack/tim
/plugin install tim-loop@tim
```

See [AI Behavioral Gates](../standards/enforcement/ai-behavioral-gates.md) for documentation.

### Plans

| Template | Purpose | Standards Implemented |
|----------|---------|----------------------|
| `plan.md.template` | Plan document | [Plan Management](../standards/operations/plan-management.md) |
| `CLAUDE.md.template` | Project instructions | All standards |
| `tim-patterns.yaml.template` | Pattern registry | [Pattern Compliance](../standards/enforcement/strict-compliance.md) |

## Usage

### Recommended: Submodule + Generated Configs

The recommended approach uses git submodules with generated configs (like `sync-claude-md`):

```bash
cd my-project

# Add tim as submodule
git submodule add /path/to/tim lib/tim

# Generate pre-commit config (auto-detects python or node)
lib/tim/bin/sync-pre-commit my-project

# Optionally add project-specific overrides
# Create .pre-commit-overrides.yaml to disable hooks or add repos

# Copy pattern registry template
cp lib/tim/templates/tim-patterns.yaml.template .tim-patterns.yaml

# Create project-specific CLAUDE.md content
echo "# Project-Specific Instructions" > CLAUDE-PROJECT.md

# Generate CLAUDE.md from tim standards
lib/tim/bin/sync-claude-md

# Install pre-commit hooks
pre-commit install

# Install Tim Loop plugin (in Claude Code)
# /plugin marketplace add schreyack/tim
# /plugin install tim-loop@tim
```

**Why generated configs?**
- Single source of truth - base templates in tim, generated files in projects
- Override capability - `.pre-commit-overrides.yaml` can disable hooks or add project-specific ones
- Immutable output - generated files are locked with `chflags uchg` (no sudo needed)
- Clean submodule - no dirty submodule state from symlinks
- Same pattern as `sync-claude-md` - consistent tooling

**Override file format** (`.pre-commit-overrides.yaml`, optional):
```yaml
disable:
  - bandit         # hook IDs to remove from base
  - no-print

repos:              # additional repos to append
  - repo: local
    hooks:
      - id: custom-check
        name: Project-specific check
        entry: ./scripts/check.sh
        language: system
```

### Alternative: Copy Templates

If you prefer copying (e.g., one-off setup without submodule):

```bash
# Python project
cp templates/python/.pre-commit-config.yaml my-project/
cp templates/CLAUDE.md.template my-project/CLAUDE.md
cp templates/tim-patterns.yaml.template my-project/.tim-patterns.yaml

# Node.js project
cp templates/node/.pre-commit-config.yaml my-project/
cp templates/node/tsconfig.json my-project/
cp templates/node/eslint.config.js my-project/

# Install pre-commit hooks
cd my-project && pre-commit install
```

**Note:** Copying templates means manual updates when tim standards change. Prefer `sync-pre-commit` for ongoing projects.

## Template-to-Gate Mapping

Templates are designed to enforce specific gates:

### AI Behavioral Gates (Real-time)

- `hooks/code-quality-validator.py` - PostToolUse hook, enforces file/function limits
- `hooks/excuse-detector.py` - Stop hook, catches deflection patterns

These hooks run during Claude Code sessions, providing immediate enforcement that AI cannot bypass.

### Gate 1 (Local/Pre-commit)

- `.pre-commit-config.yaml` - Runs on every commit
- `mypy.ini` / `tsconfig.json` - Type checking
- `eslint.config.js` - Linting

### Gate 2 (CI/Pull Request)

- `*-ci.yml` - All pre-commit checks + tests + security scans
- Coverage collected and reported

### Gate 3 (Deploy/Pre-deployment)

- Integration and E2E tests in CI templates
- Migration dry-run steps
- Health check validation

## Customization Guidelines

When customizing templates, the TIM standards require:

1. **Keep coverage reporting** - Don't remove coverage collection
2. **Keep strictness** - Don't disable type checking rules
3. **Add, don't remove** - Add project-specific checks, don't remove standard ones
4. **Update versions** - Keep dependencies current

Lowering thresholds or disabling checks violates TIM compliance and will be caught by the compliance checker.

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
- Coverage: collected and reported for reviewers

These aren't obstacles - they're the quality gates that make AI development reliable.

See: [AFK Coding Patterns](../standards/operations/afk-coding-patterns.md) for extended autonomous development.

---

## See Also

- [Four-Gate Enforcement Model](../standards/enforcement/gates.md)
- [Plan Lifecycle Management](../standards/operations/plan-management.md) - Plan creation and approval workflow
- [Graduated Enforcement](../standards/enforcement/graduated-enforcement.md) - For migration
- [Working Examples](../examples/) - Complete reference implementations
- [Shared Libraries](../standards/architecture/shared-libraries.md)
