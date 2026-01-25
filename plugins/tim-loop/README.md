# Tim Loop Plugin

Goal in, working code out: iterative convergence with verification loop.

## Overview

Tim Loop implements a four-phase workflow for AI-driven development:

1. **Plan** - Create a formal plan document
2. **Review** - Validate the plan (additive-only)
3. **Implement** - Execute 100% of the plan
4. **Verify** - Confirm 100% completion

The loop continues until verification passes or max iterations reached.

## Installation

This plugin is part of the `tim-design-standards` marketplace.

### Register the Marketplace

Add to `~/.claude/plugins/known_marketplaces.json`:

```json
{
  "tim-design-standards": {
    "source": {
      "source": "github",
      "repo": "schreyack/design_standards"
    },
    "installLocation": "/path/to/.claude/plugins/marketplaces/tim-design-standards"
  }
}
```

Then install via Claude Code's plugin system.

## Usage

```bash
# Full workflow (recommended)
/tim-loop "add user authentication"

# Plan only
/tim-loop --plan "design the auth system"

# Implement existing plan
/tim-loop --implement plans/active/my-plan.md

# Quick mode (skip review)
/tim-loop --no-review "fix typo"

# Wizard mode (full lifecycle guidance)
/tim-loop --wizard plans/active/my-plan.md
```

## Options

| Option | Description |
|--------|-------------|
| `--plan` | Create plan only, no implementation |
| `--implement FILE` | Implement existing approved plan |
| `--no-review` | Skip review phase |
| `--no-verify` | Skip verification (not recommended) |
| `--auto-approve` | Auto-approve tool permissions |
| `--max-iterations N` | Safety limit (default: 30) |
| `--dry-run` | Preview prompt without executing |
| `--cleanup` | Remove stale state files |

## Completion Rules

The loop is NOT complete until:

- Every Goal achieved
- Every Implementation Step executed
- Every Test exists and passes
- Every Completion Criterion met
- Every file created is imported AND used
- Zero TODO/FIXME comments

**Orphaned code (exists but not used) = NOT implemented.**

## Files

- `commands/tim-loop.md` - Skill definition
- `scripts/tim-loop-setup.sh` - Main setup script
- `scripts/tim-loop-hook.sh` - Stop hook for iteration
- `scripts/tim-loop-permission-hook.sh` - Auto-approve hook
- `hooks/hooks.json` - PreCompact hook for prompt preservation

## Integration with plan-ops.sh

Tim Loop integrates with `plan-ops.sh` for full plan lifecycle management:

- `--wizard` mode delegates to plan-ops wizard
- Plans follow the drafts -> active -> completed lifecycle
- AI Developer Ready approval required for `--implement`
