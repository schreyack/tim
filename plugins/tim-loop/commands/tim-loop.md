---
description: "Goal in, working code out: iterative convergence with verification loop"
argument-hint: "TASK [--plan] [--implement FILE] [--review FILE] [--wizard FILE] [--no-review] [--no-verify] [--auto-approve] [--cleanup] [--cleanup-all]"
allowed-tools: ["Bash(${CLAUDE_PLUGIN_ROOT}/scripts/tim-loop-setup.sh:*)"]
---

# Tim Loop

Execute setup to launch Tim Loop with four-phase workflow:

```!
"${CLAUDE_PLUGIN_ROOT}/scripts/tim-loop-setup.sh" $ARGUMENTS
```

---

# Installation & Usage Guide

## Prerequisites

1. **Claude Code CLI** - Install from [claude.ai/code](https://claude.ai/code)
2. **TIM Standards** - This plugin is part of the tim marketplace

## Installation

Install via Claude Code plugin system:

```bash
# Register the TIM marketplace (if not already done)
# Then install tim-loop from the marketplace
```

Or install from the marketplace UI in Claude Code.

## Usage

From within Claude Code:

### Modes (Mutually Exclusive)

#### Full Workflow (default) - Recommended for most tasks
```
/tim-loop "add user authentication"
```
**Phases:** Plan -> Review -> Implement -> Verify
**End state:** Plan file with `VERIFIED: YES`, code deployed
**Use for:** Most tasks - provides full safety and quality checks

#### Plan Only (`--plan`)
```
/tim-loop --plan "design the auth system"
```
**Phases:** Plan only
**End state:** Plan file in `plans/drafts/`, NO code changes
**Use for:** When you want to review the plan yourself before implementation

#### Implement Existing (`--implement`)
```
/tim-loop --implement plans/active/my-plan.md
```
**Phases:** Implement -> Verify (skips plan creation and review)
**End state:** Code deployed, plan verified
**Requirements:** Plan MUST be in `plans/active/` AND have `AI Developer Ready: yes`
**Use for:** When plan was created separately and already approved

#### Quick Mode (`--no-review`)
```
/tim-loop --no-review "fix typo in header"
```
**Phases:** Plan -> Implement -> Verify (skips review)
**End state:** Same as full workflow, but faster
**Use for:** Small, obvious tasks where review adds no value

#### Review Mode (`--review`)
```
/tim-loop --review plans/drafts/my-plan.md
```
**Phases:** Review only (iterative improvement)
**End state:** Plan file improved, ready for promotion
**Use for:** Iterative review of multi-phase plans before promotion

#### Wizard Mode (`--wizard`)
```
/tim-loop --wizard plans/active/my-plan.md
```
**Interactive wizard** that guides you through the FULL plan lifecycle:
Import -> Plan Review -> Promote -> AI-Ready -> Execute -> Tim-Loop -> Complete
**Use for:** When you want step-by-step guidance through all approvals and gates

### Modifier Options

| Option | Default | Description |
|--------|---------|-------------|
| `--no-verify` | - | Skip verification phase. **WARNING:** Can leave incomplete work. Only use for debugging. |
| `--auto-approve` | - | Auto-approve all tool permissions. **WARNING:** Use with caution. |
| `--max-iterations <n>` | 30 | Safety limit - force exit after N iterations |
| `--max-verify-cycles <n>` | 999999 | Max verification attempts (effectively unlimited) |
| `--completion-promise` | "COMPLETE" | Phrase that signals completion. Change if "COMPLETE" appears in your task. |
| `--dry-run` | - | Preview generated prompt without executing |
| `--help` | - | Show detailed help text |

### Cleanup Options

| Option | Description |
|--------|-------------|
| `--cleanup` | Remove orphan state files older than 24 hours (from crashed sessions) |
| `--cleanup-all` | Remove ALL state files including active sessions. Use if loop is stuck. |

## How It Works

Tim Loop implements a four-phase workflow with automatic verification:

1. **Phase 1: Create Plan** - Creates a plan document in `plans/drafts/`
2. **Phase 2: Validate Plan** - Validates plan is complete (ADDITIVE-ONLY - cannot remove/modify original items)
3. **Phase 3: Implement** - Implements 100% of the plan exactly as written
4. **Phase 4: Verify** - Verifies 100% of plan objectives are met
   - If 100% objectives met -> COMPLETE
   - If any gaps found -> Fixes or adds corrective phases, loops back to Phase 2

### The Loop Mechanism

1. When you run `/tim-loop "task"`, it registers a stop hook
2. The hook intercepts when Claude tries to exit
3. If the completion promise wasn't output, the prompt is re-injected
4. Claude sees its previous work in files and continues
5. Loop repeats until completion or max iterations

### Completion Rules (CRITICAL)

**100% means 100%.** The loop is NOT complete until:

1. **Every Goal achieved** - Not partially, not "good enough"
2. **Every Implementation Step executed** - All of them, in full
3. **Every Test exists and passes** - From Testing Strategy
4. **Every Completion Criterion met** - Each one verified
5. **Every file created is imported AND used** - Not just created
6. **Zero TODO/FIXME comments** in new code

**Orphaned code (exists but not used) = NOT implemented.**

For full rules, see the tim-loop documentation in the plugin.
