# Tim Loop Plugin

**Goal in, working code out: iterative convergence with verification loop.**

Tim Loop is a Claude Code plugin that implements a four-phase workflow for AI-driven development. It ensures tasks are completed 100% - not "good enough", not "mostly done", but fully verified complete.

## Table of Contents

- [Overview](#overview)
- [Installation](#installation)
- [Usage](#usage)
- [How It Works](#how-it-works)
- [AI Behavioral Gates](#ai-behavioral-gates)
- [Modes](#modes)
- [Options Reference](#options-reference)
- [Completion Rules](#completion-rules)
- [Integration with plan-ops.sh](#integration-with-plan-opssh)
- [PreCompact Hook (Prompt Preservation)](#precompact-hook-prompt-preservation)
- [Cleanup](#cleanup)
- [File Structure](#file-structure)
- [Troubleshooting](#troubleshooting)

## Overview

Tim Loop implements a four-phase workflow:

1. **Plan** - Create a formal plan document with goals, implementation steps, testing strategy, and completion criteria
2. **Review** - Validate the plan is complete and actionable (additive-only - cannot remove or modify original items)
3. **Implement** - Execute 100% of the plan exactly as written
4. **Verify** - Confirm 100% of objectives are met. If gaps found, loop continues.

The loop continues until verification passes or max iterations are reached.

## Installation

Tim Loop is part of the `tim-design-standards` marketplace hosted on GitHub.

### Option A: Interactive Install (Recommended)

The easiest way to install is through the interactive plugin manager:

1. **Open the plugin manager:**
   ```
   /plugin
   ```

2. **Navigate to the Marketplaces tab** (use arrow keys)

3. **Add the marketplace:**
   - Select "Add Marketplace"
   - Enter: `schreyack/design_standards`
   - Press Enter to confirm

4. **Navigate to the Discover tab**

5. **Find and install tim-loop:**
   - Scroll to find `tim-loop`
   - Press Enter to select it
   - Choose your installation scope:
     - **User** (default): Available in all your projects
     - **Project**: Shared with team via version control
     - **Local**: Just for you in this repo

6. **Restart Claude Code** to activate the plugin

### Option B: Command-Line Install

If you prefer CLI commands:

```bash
# Step 1: Add the marketplace
/plugin marketplace add schreyack/design_standards

# Step 2: Install tim-loop from the marketplace
/plugin install tim-loop@tim-design-standards
```

### Option C: Manual Installation

For offline environments or custom setups:

#### Step 1: Clone the repository

```bash
git clone https://github.com/schreyack/design_standards.git \
  ~/.claude/plugins/marketplaces/tim-design-standards
```

#### Step 2: Register in your settings

Add to `~/.claude/settings.json` (or `.claude/settings.json` for project scope):

```json
{
  "extraKnownMarketplaces": {
    "tim-design-standards": {
      "source": "./plugins/marketplaces/tim-design-standards"
    }
  },
  "enabledPlugins": {
    "tim-loop@tim-design-standards": true
  }
}
```

#### Step 3: Restart Claude Code

### Updating

**Interactive:**
1. Run `/plugin`
2. Go to the **Installed** tab
3. Select `tim-loop` and choose "Update"

**Command-line:**
```bash
/plugin update tim-loop@tim-design-standards
```

**Manual:**
```bash
cd ~/.claude/plugins/marketplaces/tim-design-standards && git pull
```

### Verifying Installation

After installation, verify it works:

```bash
/tim-loop --help
```

You should see the help text with available options.

## Usage

From within Claude Code:

```bash
# Full workflow (recommended for most tasks)
/tim-loop "add user authentication"

# Plan only - create plan, no implementation
/tim-loop --plan "design the auth system"

# Implement an existing approved plan
/tim-loop --implement plans/active/my-plan.md

# Quick mode - skip review phase
/tim-loop --no-review "fix typo in header"

# Wizard mode - full lifecycle guidance
/tim-loop --wizard plans/active/my-plan.md

# Preview what would happen
/tim-loop --dry-run "add feature X"

# Get help
/tim-loop --help
```

## How It Works

### The Loop Mechanism

1. When you run `/tim-loop "task"`, it:
   - Creates a session with unique ID
   - Saves the prompt to a state file
   - Registers a stop hook in `~/.claude/settings.local.json`

2. The stop hook intercepts when Claude tries to exit the conversation

3. The hook checks for the completion promise (`<promise>COMPLETE</promise>`):
   - If found AND plan has `<!-- VERIFIED: YES -->` → Task complete, cleanup
   - If not found → Re-inject the prompt, increment iteration

4. Claude sees its previous work in files and continues where it left off

5. Loop repeats until:
   - Verification passes (100% complete)
   - Max iterations reached (default: 30)
   - User manually stops

### Hooks Used

| Hook | Purpose |
|------|---------|
| `Stop` | Intercepts exit to check for completion and re-inject prompt |
| `Stop` | Excuse pattern detector - catches deflection and blocks completion |
| `PreToolUse` | Auto-approves tools when `--auto-approve` is active |
| `PostToolUse` | Code quality validator - enforces file/function size limits |
| `PreCompact` | Preserves original prompt across context compaction |

## AI Behavioral Gates

Tim Loop includes real-time enforcement hooks that ensure code quality and accountability. These run automatically when you install the plugin - no additional configuration needed.

### Code Quality Validator (PostToolUse)

Runs after every `Edit` or `Write` operation:

| Check | Limit | Action |
|-------|-------|--------|
| File size | 400 lines max | Blocks until refactored |
| Function length | 50 lines max | Blocks until split |

When a violation is detected, Claude receives a blocking response:

```
CODE QUALITY VIOLATION in page.tsx:

- File has 542 lines (max: 400). Must be refactored into smaller modules.

TIM Design Standards require this file to be refactored before continuing.
This is a HARD REQUIREMENT - no exceptions.
```

Claude cannot proceed until the violation is fixed.

### Excuse Pattern Detector (Stop)

Runs when Claude tries to complete a task. Scans the conversation for deflection patterns:

| Pattern Type | Example | Why Blocked |
|--------------|---------|-------------|
| Pre-existing blame | "The file was already over the limit" | Touched file = your responsibility |
| Scope avoidance | "This isn't part of my changes" | Standards don't care about scope |
| Responsibility denial | "I didn't cause this violation" | You saw it, you fix it |
| Minimization | "I only added 6 lines" | Impact size is irrelevant |
| Plan excuses | "The plan doesn't mention this" | Standards override plan scope |

When excuses are detected:

```
DEFLECTION DETECTED - You attempted to avoid responsibility.

Found 3 excuse pattern(s):
  - Pattern: Claiming pre-existing problems excuse current responsibility
    Context: "...file was already over the limit before my changes..."

TIM DESIGN STANDARDS RULE:
If you touched a file with violations, you MUST fix them.
No exceptions. No excuses.
```

Claude cannot complete until issues are addressed.

### Why This Matters

AI assistants often exhibit problematic behaviors:
- Making excuses instead of fixing issues
- Claiming problems are "out of scope"
- Minimizing their responsibility

**TIM Rule**: If you touched a file with violations, you must fix them. No exceptions.

These gates enforce accountability through deterministic hooks that AI cannot bypass.

## Modes

### Full Workflow (default)

```bash
/tim-loop "add user authentication"
```

**Phases:** Plan → Review → Implement → Verify
**End state:** Plan file with `<!-- VERIFIED: YES -->`, code deployed
**Use for:** Most tasks - provides full safety and quality checks

### Plan Only (`--plan`)

```bash
/tim-loop --plan "design the auth system"
```

**Phases:** Plan only
**End state:** Plan file in `plans/drafts/`, NO code changes
**Use for:** When you want to review the plan yourself before implementation

### Implement Existing (`--implement`)

```bash
/tim-loop --implement plans/active/my-plan.md
```

**Phases:** Implement → Verify (skips plan creation and review)
**End state:** Code deployed, plan verified
**Requirements:**
- Plan MUST be in `plans/active/` folder
- Plan MUST have `| AI Developer Ready | yes |` in status table
**Use for:** When plan was created separately and already approved

### Quick Mode (`--no-review`)

```bash
/tim-loop --no-review "fix typo in header"
```

**Phases:** Plan → Implement → Verify (skips review)
**End state:** Same as full workflow, but faster
**Use for:** Small, obvious tasks where review adds no value

### Wizard Mode (`--wizard`)

```bash
/tim-loop --wizard plans/active/my-plan.md
```

**Interactive wizard** that guides you through the FULL plan lifecycle:
Import → Ralph Review → Promote → AI-Ready → Execute → Tim-Loop → Complete

**Use for:** When you want step-by-step guidance through all approvals and gates

## Options Reference

### Mode Options (Mutually Exclusive)

| Option | Description |
|--------|-------------|
| (default) | Full workflow: Plan → Review → Implement → Verify |
| `--plan` | Create plan only, no implementation |
| `--implement FILE` | Implement existing approved plan (must be in `active/` with AI Developer Ready) |
| `--wizard FILE` | Interactive wizard through full plan lifecycle |

### Modifier Options

| Option | Default | Description |
|--------|---------|-------------|
| `--no-review` | - | Skip review phase (Plan → Implement → Verify) |
| `--no-verify` | - | Skip verification phase. **WARNING:** Can leave incomplete work. Only use for debugging. |
| `--auto-approve` | - | Auto-approve all tool permissions. **WARNING:** Use with caution. |
| `--max-iterations N` | 30 | Safety limit - force exit after N iterations |
| `--max-verify-cycles N` | 999999 | Max verification attempts (effectively unlimited) |
| `--review-iterations N` | 10 | Max iterations for review phase |
| `--completion-promise STR` | "COMPLETE" | Phrase that signals completion. Change if "COMPLETE" appears in your task. |
| `--dry-run` | - | Preview generated prompt without executing |
| `--help` | - | Show detailed help text |

### Cleanup Options

| Option | Description |
|--------|-------------|
| `--cleanup` | Remove orphan state files older than 24 hours (from crashed sessions) |
| `--cleanup-all` | Remove ALL state files including active sessions. Use if loop is stuck. |

## Completion Rules

**100% means 100%.** The loop is NOT complete until:

1. **Every Goal achieved** - Not partially, not "good enough"
2. **Every Implementation Step executed** - All of them, in full
3. **Every Test exists and passes** - From Testing Strategy
4. **Every Completion Criterion met** - Each one verified
5. **Every file created is imported AND used** - Not just created
6. **Zero TODO/FIXME comments** in new code

**Orphaned code (exists but not used) = NOT implemented.**

### Verification Markers

The loop looks for these markers in the plan file:

| Marker | Meaning |
|--------|---------|
| `<!-- REVIEWED: NO -->` | Plan created, needs review |
| `<!-- REVIEWED: YES -->` | Plan reviewed, ready for implementation |
| `<!-- VERIFIED: NO -->` | Implementation done, needs verification |
| `<!-- VERIFIED: YES -->` | All objectives verified complete |
| `<!-- VERIFIED: FAILED -->` | Verification failed, remediation required |

## Integration with plan-ops.sh

Tim Loop integrates with `tools/plan-ops.sh` for full plan lifecycle management:

### Plan Lifecycle Flow

```
1. Create plan → plans/drafts/
2. (Multi-phase only) Ralph Loop review
3. Human approves → plans/active/
4. AI Developer Ready approval
5. Tim Loop implements → plans/completed/
```

### Wizard Mode Integration

The `--wizard` mode delegates to plan-ops.sh wizard, which guides you through:

1. **Import** - Import plan from `~/.claude/plans/` if needed
2. **Ralph Review** - Multi-phase validation (2+ phases require this)
3. **Promote** - Move from drafts to active
4. **AI-Ready** - Human verifies plan is suitable for AI implementation
5. **Execute** - Request execution approval
6. **Tim-Loop** - Run implementation with verification loop
7. **Complete** - Move to completed folder

### Requirements for --implement

Plans must meet these criteria before `--implement` will work:

1. Located in `plans/active/` (not drafts or completed)
2. Have `| AI Developer Ready | yes |` in status table
3. Execution approval granted (via plan-ops.sh approve-execute)

## PreCompact Hook (Prompt Preservation)

Tim Loop includes a PreCompact hook that preserves the original task prompt when Claude Code compacts context (removes older messages to stay within token limits).

### How It Works

1. At tim-loop start, the original prompt is saved to a session-specific file
2. When context compaction occurs, the PreCompact hook fires
3. The hook injects the original prompt as a system message
4. Claude continues with full awareness of the original task

### Configuration

The PreCompact hook is defined in `hooks/hooks.json` and registered automatically when the plugin is installed:

```json
{
  "hooks": {
    "PreCompact": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/scripts/tim-loop-prompt-manager.sh hook"
          }
        ]
      }
    ]
  }
}
```

### Prompt Manager Tool

The `scripts/tim-loop-prompt-manager.sh` script (bundled with the plugin) manages prompt files:

```bash
# These commands are typically run automatically by tim-loop
# Manual usage (from plugin directory):

# Save prompt for current session
./scripts/tim-loop-prompt-manager.sh save "task prompt..."

# Save prompt from file
./scripts/tim-loop-prompt-manager.sh save-file prompt.txt

# Get saved prompt
./scripts/tim-loop-prompt-manager.sh get

# Clear saved prompt
./scripts/tim-loop-prompt-manager.sh clear

# Clean up stale prompts (>24h)
./scripts/tim-loop-prompt-manager.sh cleanup

# Run as PreCompact hook (outputs JSON)
./scripts/tim-loop-prompt-manager.sh hook
```

## Cleanup

### Automatic Cleanup

Tim Loop automatically cleans up:

- Orphan state files older than 24 hours (on each loop start)
- Expired approval requests
- Orphan hooks when no active sessions exist

### Manual Cleanup

```bash
# Clean orphan files older than 24 hours
/tim-loop --cleanup

# Clean ALL state files (use if stuck)
/tim-loop --cleanup-all
```

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `TIM_LOOP_ORPHAN_AGE_HOURS` | 24 | Hours before orphan files are cleaned |
| `PLAN_OPS_SCRIPT` | (auto-detected) | Path to plan-ops.sh |
| `TIM_PROMPT_DIR` | `.tim-execution-requests` | Directory for prompt files |
| `TIM_PROMPT_STALE_MINUTES` | 1440 | Minutes before prompts are stale |

## File Structure

```
plugins/tim-loop/
├── .claude-plugin/
│   └── plugin.json           # Plugin metadata (name, description, author, version)
├── commands/
│   └── tim-loop.md           # Skill definition (command syntax, allowed tools)
├── scripts/
│   ├── tim-loop-setup.sh     # Main setup script (parses args, creates state, registers hooks)
│   ├── tim-loop-hook.sh      # Stop hook (checks completion, re-injects prompt)
│   ├── tim-loop-permission-hook.sh  # PreToolUse hook (auto-approve when enabled)
│   ├── tim-loop-prompt-manager.sh   # PreCompact hook (preserves prompt across compaction)
│   ├── code-quality-validator.py    # PostToolUse hook (file/function size limits)
│   └── excuse-detector.py    # Stop hook (catches deflection patterns)
├── hooks/
│   └── hooks.json            # Hook configuration (PreCompact, PostToolUse, Stop)
└── README.md                 # This file
```

### State Files

Tim Loop creates these files during execution:

| File | Location | Purpose |
|------|----------|---------|
| `.tim-loop-state-{session_id}` | `~/.claude/` | Current iteration, max iterations, completion promise |
| `.tim-loop-prompt-{session_id}` | `~/.claude/` | Original prompt for re-injection |
| `.tim-loop-active` | `~/.claude/` | Marker pointing to active state file |
| `.tim-loop-auto-approve` | `~/.claude/` | Session ID when auto-approve is active |

## Troubleshooting

### Loop won't stop

1. Check if completion promise was output: `<promise>COMPLETE</promise>`
2. Check if plan has `<!-- VERIFIED: YES -->`
3. Run cleanup: `/tim-loop --cleanup-all`

### "Plan is not marked AI Developer Ready"

For `--implement` mode, the plan must have:
```markdown
| AI Developer Ready | yes |
```
in its status table. Use plan-ops.sh to grant this approval:
```bash
./tools/plan-ops.sh ai-ready plans/active/my-plan.md --reviewer "Your Name"
```

### "Can only implement plans from active/ folder"

Move the plan to active first:
```bash
./tools/plan-ops.sh promote plans/drafts/my-plan.md --approver "Your Name"
```

### Hooks not being unregistered

Check `~/.claude/settings.local.json` for stale hooks:
```bash
cat ~/.claude/settings.local.json | grep tim-loop
```

Clean them manually or run:
```bash
/tim-loop --cleanup-all
```

### Loop continues after task should be complete

The verification logic checks for `<!-- VERIFIED: YES -->` in the plan file. Ensure:

1. The plan file exists at the expected path
2. The verification marker is exactly `<!-- VERIFIED: YES -->` (not `VERIFIED:YES` or similar)
3. The completion promise is output after verification

### Context compaction loses track of task

The PreCompact hook should preserve the prompt. Check:

1. Plugin hooks.json is properly installed
2. `scripts/tim-loop-prompt-manager.sh` exists in the plugin folder and is executable
3. Session ID is being passed correctly

### Max iterations reached

Increase the limit:
```bash
/tim-loop --max-iterations 50 "complex task"
```

Or investigate why the task isn't completing - the verification check will show what's missing.

### Code quality validator keeps blocking

The validator enforces TIM standards (400-line files, 50-line functions). If you're blocked:

1. Refactor the file into smaller modules
2. Extract large functions into smaller units
3. Each module should have a single responsibility

**There is no bypass** - this is intentional. Fix the code.

### Excuse detector false positive

The excuse detector uses conservative patterns. If legitimate technical discussion is flagged:

1. Rephrase to focus on solutions, not blame
2. Instead of: "This was already broken"
3. Say: "I'll fix this violation now"

The detector looks for deflection language. Solution-focused language passes through.

### Behavioral gates not running

Verify Python 3 is available:
```bash
which python3
```

Check the hooks are registered:
```bash
cat ~/.claude/settings.local.json | grep -A5 PostToolUse
```

Verify scripts are executable:
```bash
ls -la ~/.claude/plugins/cache/tim-design-standards/tim-loop/*/scripts/*.py
```
