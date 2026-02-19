# Tim Loop Plugin

**Goal in, working code out: iterative convergence with verification loop.**

Tim Loop is a Claude Code plugin that implements a four-phase workflow for AI-driven development. It ensures tasks are completed 100% - not "good enough", not "mostly done", but fully verified complete.

## Table of Contents

- [Why Tim Loop Exists](#why-tim-loop-exists)
- [What Makes This Approach Novel](#what-makes-this-approach-novel)
- [The Two Components](#the-two-components)
- [Overview](#overview)
- [Installation](#installation)
- [Usage](#usage)
- [How It Works](#how-it-works)
- [AI Behavioral Gates](#ai-behavioral-gates)
- [Modes](#modes)
- [Options Reference](#options-reference)
- [Completion Rules](#completion-rules)
- [Integration with plan-ops.sh](#integration-with-plan-opssh)
- [SessionStart Hook (Prompt Preservation)](#sessionstart-hook-prompt-preservation)
- [Cleanup](#cleanup)
- [File Structure](#file-structure)
- [Troubleshooting](#troubleshooting)

---

## Why Tim Loop Exists

AI coding assistants have a fundamental problem: **they lose track of what they're doing**.

Three things cause this:

1. **Context compaction** - When the conversation gets too long, older context is summarized and details are lost. The AI forgets critical requirements, architectural decisions, or the original goal entirely.

2. **Premature completion** - AI naturally wants to wrap up. It will declare "done" when code compiles, even if half the requirements are missing or tests don't exist.

3. **Deflection and excuses** - When confronted with problems (code quality violations, test failures), AI will rationalize why it's "not my responsibility" or "out of scope."

Tim Loop solves all three with **hooks that enforce accountability**.

---

## What Makes This Approach Novel

Most solutions to AI context loss focus on **retrieval** - archiving context and searching for it later. Tim Loop takes a different approach: **direct prompt reinjection**.

### Comparison with Other Approaches

| Approach | How It Works | Limitation |
|----------|--------------|------------|
| **Archive + Search** (e.g., c0ntextKeeper) | Saves context to database, AI queries via MCP tools | AI must know to search; can miss critical context |
| **Periodic Refresh** (e.g., UserPromptSubmit hooks) | Reinjects context every N prompts | Doesn't target compaction; wastes tokens on every prompt |
| **Rolling Summaries** (e.g., Factory.ai) | Maintains compressed summaries of conversation | Summaries lose precision; "behavioral drift" |
| **Tim Loop's SessionStart** | Reinjects **exact original task prompt** during compaction | Full fidelity preserved |

### Key Innovations

**1. Exact Prompt Preservation**

When context compaction occurs, Tim Loop's SessionStart hook reinjects the *exact* original task prompt - not a summary, not a retrieval query, but the precise instructions. The AI continues with full fidelity to the original goal.

```text
=== ORIGINAL TASK (reinjected after context compaction) ===
[exact prompt preserved, character-for-character]
=== END ORIGINAL TASK ===
```

**2. Verification Loop That Cannot Be Bypassed**

Tim Loop intercepts Claude's attempt to exit and checks for two things:

- Did Claude output the completion promise? (`<promise>COMPLETE</promise>`)
- Does the plan have `<!-- VERIFIED: YES -->`?

If either is missing, the prompt is re-injected and Claude continues. **There is no way for AI to prematurely exit.** The loop continues until verification passes or max iterations are reached.

**3. Excuse Detection as a Hard Gate**

The Stop hook scans Claude's output for deflection patterns:

- "The file was already over the limit"
- "This isn't part of my scope"
- "I didn't cause this violation"

When detected, completion is **blocked**. Claude cannot finish until issues are addressed. This eliminates a major failure mode where AI rationalizes incomplete work.

**4. Human-Gated Plan Approval**

Through integration with plan-ops.sh, Tim Loop enforces:

- **AI Developer Ready approval** - Human verifies plan is unambiguous before AI implements
- **No bypass flags** - AI cannot auto-approve itself; approval requires interactive terminal

**5. Session-Isolated State**

Each Tim Loop session has isolated state files. Multiple concurrent sessions in different projects don't interfere. The SessionStart hook uses session IDs to reinject the correct prompt to the correct session.

### Why This Matters

From Anthropic's own research and industry consensus:

> "Most agent failures are not model failures anymore, they are **context failures**."

Tim Loop addresses context failures at three levels:

1. **Preservation** - Original task survives context compaction
2. **Accountability** - AI cannot deflect or make excuses
3. **Verification** - Loop continues until 100% complete

---

## The Two Components

Tim Loop works as a system of two tools that handle different concerns:

### Tim Loop (this plugin)

**What it does:** Executes AI development tasks with guaranteed completion.

- Creates and follows structured plans
- Loops until 100% of objectives are verified complete
- Preserves original task across context compaction
- Enforces code quality and blocks excuses
- Runs as a Claude Code plugin via `/tim-loop` command

**When to use:** When you have a task that needs to be fully completed, not abandoned at 80%.

### Plan-Ops (bundled in plugin)

**What it does:** Manages the plan lifecycle with human approval gates.

**Note:** Plan-ops is bundled in the tim-loop plugin. Run it from your terminal (not Claude Code) for human approval workflows. Use `/tim-loop --wizard` for guided plan management.

- Organizes plans in `drafts/` → `active/` → `completed/` folders
- Enforces Plan Review for multi-phase plans
- Requires human approval before AI can implement
- Tracks plan status with structured metadata
- Runs as a shell script in any terminal

**When to use:** When you want formal plan management with human oversight.

### How They Work Together

```text
┌─────────────────────────────────────────────────────────────────┐
│                      PLAN LIFECYCLE                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  1. DRAFT          2. REVIEW         3. ACTIVE        4. DONE   │
│  ┌─────────┐       ┌─────────┐       ┌─────────┐      ┌──────┐  │
│  │ Create  │──────▶│ Plan    │──────▶│ Approve │─────▶│ Done │  │
│  │ Plan    │       │ Review  │       │ Execute │      │      │  │
│  └─────────┘       └─────────┘       └─────────┘      └──────┘  │
│       │                 │                 │               │      │
│       ▼                 ▼                 ▼               ▼      │
│  plan-ops.sh       plan-ops.sh       plan-ops.sh    plan-ops.sh │
│  import            review            ai-ready        complete   │
│                    promote           execute                    │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                    IMPLEMENTATION LOOP                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│          /tim-loop --implement plans/active/my-plan.md          │
│                              │                                   │
│                              ▼                                   │
│                    ┌─────────────────┐                          │
│                    │   IMPLEMENT     │                          │
│                    │   (execute plan)│                          │
│                    └────────┬────────┘                          │
│                             │                                    │
│                             ▼                                    │
│                    ┌─────────────────┐                          │
│                    │    VERIFY       │◀─────────────────┐       │
│                    │ (100% complete?)│                  │       │
│                    └────────┬────────┘                  │       │
│                             │                           │       │
│              ┌──────────────┴──────────────┐           │       │
│              ▼                              ▼           │       │
│        ┌──────────┐                  ┌──────────┐      │       │
│        │   YES    │                  │    NO    │──────┘       │
│        │ Complete │                  │  (loop)  │               │
│        └──────────┘                  └──────────┘               │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

**Typical workflow:**

1. **Create plan** - Run `/tim-loop --plan "add feature X"` or let Claude create a plan
2. **Import** - `plan-ops.sh import ~/.claude/plans/my-plan.md`
3. **Review** - `plan-ops.sh review plans/drafts/my-plan.md` (for multi-phase plans)
4. **Promote** - `plan-ops.sh promote plans/drafts/my-plan.md --approver "Name"`
5. **AI Ready** - `plan-ops.sh ai-ready plans/active/my-plan.md --reviewer "Name"`
6. **Execute** - `plan-ops.sh execute plans/active/my-plan.md` (outputs tim-loop command)
7. **Implement** - `/tim-loop --implement plans/active/my-plan.md`
8. **Complete** - `plan-ops.sh complete plans/active/my-plan.md`

Or use the wizard for guided flow: `/tim-loop --wizard plans/active/my-plan.md`

---

## Overview

Tim Loop implements a four-phase workflow:

1. **Plan** - Create a formal plan document with goals, implementation steps, testing strategy, and completion criteria
2. **Review** - Validate the plan is complete and actionable (additive-only - cannot remove or modify original items)
3. **Implement** - Execute 100% of the plan exactly as written
4. **Verify** - Confirm 100% of objectives are met. If gaps found, loop continues.

The loop continues until verification passes or max iterations are reached.

## Installation

Tim Loop is part of the `tim` marketplace hosted on GitHub.

### Option A: Interactive Install (Recommended)

The easiest way to install is through the interactive plugin manager:

1. **Open the plugin manager:**

   ```text
   /plugin
   ```

2. **Navigate to the Marketplaces tab** (use arrow keys)

3. **Add the marketplace:**
   - Select "Add Marketplace"
   - Enter: `schreyack/tim`
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
/plugin marketplace add schreyack/tim

# Step 2: Install tim-loop from the marketplace
/plugin install tim-loop@tim
```

### Option C: Manual Installation

For offline environments or custom setups:

#### Step 1: Clone the repository

```bash
git clone https://github.com/schreyack/tim.git \
  ~/.claude/plugins/marketplaces/tim
```

#### Step 2: Register in your settings

Add to `~/.claude/settings.json` (or `.claude/settings.json` for project scope):

```json
{
  "extraKnownMarketplaces": {
    "tim": {
      "source": "./plugins/marketplaces/tim"
    }
  },
  "enabledPlugins": {
    "tim-loop@tim": true
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
/plugin update tim-loop@tim
```

**Manual:**

```bash
cd ~/.claude/plugins/marketplaces/tim && git pull
```

### Verifying Installation

After installation, verify it works:

```bash
/tim-loop --help
```

You should see the help text with available options.

### Project Initialization

The first time you run `/tim-loop` in a project, it automatically creates the `./plans/` folder structure:

- `drafts/` - Plans being designed
- `active/` - Approved plans under implementation
- `completed/` - Successfully executed plans
- `abandoned/` - Cancelled plans

Plan-ops commands are run directly from the plugin (no project-local copy needed).

### Adding plan-ops to PATH (Recommended)

To run `plan-ops` from any directory without the full path, add the `bin/` directory to your PATH:

```bash
# Add to ~/.bashrc or ~/.zshrc:
export PATH="$HOME/.claude/plugins/marketplaces/tim/bin:$PATH"

# Reload your shell
source ~/.bashrc  # or source ~/.zshrc
```

After setup, you can run plan-ops commands directly:

```bash
plan-ops init
plan-ops import ~/.claude/plans/my-plan.md
plan-ops wizard plans/drafts/my-plan.md
plan-ops list
```

The `plan-ops init` command will also display these instructions.

## Usage

From within Claude Code:

### IMPORTANT: Always Clear Context First

**Run `/clear` before starting any loop command.** This prevents leftover context and hooks from previous sessions from interfering.

```text
/clear
```

Then paste your tim-loop command:

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

| Hook | Script | Purpose |
|------|--------|---------|
| `SessionStart` | `tim-loop-prompt-manager.sh` | Preserves original prompt across context compaction |
| `UserPromptSubmit` | `option_expander.py` | Expands shorthand options in user prompts |
| `PreToolUse` | `block_bypass_flags.py` | Blocks `--no-verify` and similar bypass flags on Bash commands |
| `PreToolUse` | `tim-loop-permission-hook.sh` | Auto-approves tools when `--auto-approve` is active |
| `PostToolUse` | `code-quality-validator.py` | Code quality validator - enforces file/function size limits |
| `PostToolUse` | `fast_pattern_detector.py` | Fast pattern detection for behavioral enforcement |
| `Stop` | `excuse_detector_v2.py` | Excuse pattern detector - catches deflection and blocks completion |
| `Stop` | `tim_loop_hook.py` | Intercepts exit to check for completion and re-inject prompt |

## AI Behavioral Gates

Tim Loop includes real-time enforcement hooks that ensure code quality and accountability. These run automatically when you install the plugin - no additional configuration needed.

### Code Quality Validator (PostToolUse)

Runs after every `Edit` or `Write` operation:

| Check | Limit | Action |
|-------|-------|--------|
| File size | 400 lines max | Blocks until refactored |
| Function length | 50 lines max | Blocks until split |
| Cyclomatic complexity | 10 max | Blocks until simplified |

When a violation is detected, Claude receives a blocking response:

```text
CODE QUALITY VIOLATION in page.tsx:

- File has 542 lines (max: 400). Must be refactored into smaller modules.

TIM Standards require this file to be refactored before continuing.
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

```text
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
Import → Plan Review → Promote → AI-Ready → Execute → Tim-Loop → Complete

**Use for:** When you want step-by-step guidance through all approvals and gates

### Full Review Mode (`--full-review`)

```bash
/tim-loop --full-review plans/drafts/my-plan.md
```

**Phases:** Seven comprehensive review phases
**End state:** Plan file ready for implementation (technically sound, AI-ready, goal-aligned)
**Use for:** Complete review in a single session

#### Full Review Details (7 Phases)

Full review mode performs a comprehensive 7-phase review:

| Phase | Focus | Min Iterations |
|-------|-------|----------------|
| 1. Tech Review | Technical accuracy, edge cases, evidence log | 5 |
| 2. Devil's Advocate | Assumptions, failure modes, worst cases | 2 |
| 3. Security Review | Auth, validation, OWASP considerations | 2 |
| 4. AI-Ready | Unambiguous instructions, hallucination prevention | 2 |
| 5. Goal Alignment | Does plan still match original intent? | 1 |
| 6. PM Review | Organization, flow, clerical (no scope reduction) | 1 |
| 7. User Advocate | Unauthorized decisions audit (feature/UX changes) | 1 |

**Total minimum iterations:** 14
**Typical actual iterations:** 16-26

Each phase must output its completion signal before advancing.

### Phase 1: Evidence Requirement

Tech Review requires an Evidence Log before completion:

```text
**REVIEW EVIDENCE LOG**

Files verified:
- [specific file:line numbers checked]

Edge cases added:
- [before/after for improvements]

Criteria tightened:
- [before/after for specificity improvements]

Questions raised:
- [list or "None"]
```

Empty or vague logs (e.g., "verified all files") are not accepted.

## Options Reference

### Mode Options (Mutually Exclusive)

| Option | Description |
|--------|-------------|
| (default) | Full workflow: Plan → Review → Implement → Verify |
| `--plan` | Create plan only, no implementation |
| `--implement FILE` | Implement existing approved plan (must be in `active/` with AI Developer Ready) |
| `--full-review FILE` | Comprehensive 7-phase review in a single session |
| `--tech-review FILE` | Technical review by skeptical senior engineer persona |
| `--pm-review FILE` | Project management review (organization, no scope reduction) |
| `--ai-ready FILE` | AI-readiness review + goal alignment check |
| `--verify FILE` | Post-implementation verification audit |
| `--wizard FILE` | Interactive wizard through full plan lifecycle |

### Modifier Options

| Option | Default | Description |
|--------|---------|-------------|
| `--no-review` | - | Skip review phase (Plan → Implement → Verify) |
| `--force`, `-f` | - | Override existing active session detection |
| `--team` | - | Use agent teams for parallel implementation (experimental) |
| `--auto-approve` | - | Auto-approve all tool permissions. **WARNING:** Use with caution. |
| `--max-iterations N` | 30 | Safety limit - force exit after N iterations |
| `--max-verify-cycles N` | 999999 | Max verification attempts (effectively unlimited) |
| `--review-iterations N` | 10 | Max iterations for review phase |
| `--min-review-iterations N` | 5 | Minimum review passes before allowing completion |
| `--completion-promise STR` | "COMPLETE" | Phrase that signals completion. Change if "COMPLETE" appears in your task. |
| `--llm-loop` | - | Enable LLM judge for semantic evasion detection (requires LLM judge config) |
| `--dry-run` | - | Preview generated prompt without executing |
| `--health` | - | Run hook health check to verify tim-loop hooks are configured |
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

### Verification Failure Recovery

When tim-loop exits without completing verification (max iterations reached, stuck session), it writes a failure marker to the plan file:

```text
<!-- VERIFIED: FAILED -->
<!-- FAILURE_REASON: Max iterations (30) reached without verification. Status: NOT_VERIFIED -->
<!-- FAILURE_TIME: 2026-02-01 12:00:00 -->
```

**To recover:**

1. Review the plan file to understand what wasn't completed
2. Run `/tim-loop --verify <plan-file>` to attempt verification again
3. Or create a remediation plan addressing the gaps

## Integration with plan-ops.sh

Tim Loop integrates with `plan-ops.sh` for full plan lifecycle management:

### Plan Lifecycle Flow

```text
1. Create plan → plans/drafts/
2. (Multi-phase only) Plan Review
3. Human approves → plans/active/
4. AI Developer Ready approval
5. Tim Loop implements → plans/completed/
```

### Wizard Mode Integration

The `--wizard` mode delegates to plan-ops.sh wizard, which guides you through:

1. **Import** - Import plan from `~/.claude/plans/` if needed
2. **Plan Review** - Multi-phase validation (2+ phases require this)
3. **Promote** - Move from drafts to active
4. **AI-Ready** - Human verifies plan is suitable for AI implementation
5. **Execute** - Get tim-loop command
6. **Tim-Loop** - Run implementation with verification loop
7. **Complete** - Move to completed folder

### Requirements for --implement

Plans must meet these criteria before `--implement` will work:

1. Located in `plans/active/` (not drafts or completed)
2. Have `| AI Developer Ready | yes |` in status table

## SessionStart Hook (Prompt Preservation)

Tim Loop includes a SessionStart hook that preserves the original task prompt when Claude Code compacts context (removes older messages to stay within token limits).

### The Problem It Solves

When Claude's context window fills up, older messages are summarized to make room. This can cause:

- Loss of original task requirements
- Forgetting architectural decisions made earlier
- "Behavioral drift" where Claude deviates from the plan

Most solutions (archive + search, rolling summaries) lose fidelity. Tim Loop's approach is different: **reinject the exact original prompt**.

### How It Works

1. At tim-loop start, the original prompt is saved to a session-specific file (`~/.claude/.tim-loop-prompt-{session_id}`)
2. When context compaction occurs, the SessionStart hook fires
3. The hook returns JSON with `systemMessage` containing the original prompt
4. Claude receives the exact prompt and continues with full awareness of the original task

```text
=== ORIGINAL TASK (reinjected after context compaction) ===

The following is the original task prompt. Context was compacted but
this task remains active. Continue working on this task:

[exact original prompt, preserved character-for-character]

=== END ORIGINAL TASK ===
```

### Verifying It Works

The hook logs every invocation to `~/.claude/.tim-loop-reinject.log`:

```bash
# Check the log
cat ~/.claude/.tim-loop-reinject.log
```

You'll see entries like:

```text
[2026-01-25 08:00:00] REINJECT: session=31790 prompt_length=28698
[2026-01-25 08:15:30] SKIP: no prompt for session 12345
[2026-01-25 08:20:00] SKIP: fallback session ID (no valid session)
```

**Log entry meanings:**

| Entry | Meaning |
|-------|---------|
| `REINJECT` | Successfully reinjected prompt for session |
| `SKIP: no prompt` | Session exists but no saved prompt (not a tim-loop session) |
| `SKIP: fallback session ID` | Couldn't determine session ID |

### Configuration

The SessionStart hook is defined in `hooks/hooks.json` and registered automatically when the plugin is installed:

```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "compact",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/scripts/tim-loop-prompt-manager.sh hook",
            "timeout": 10
          }
        ]
      }
    ]
  }
}
```

### Session Isolation

Each tim-loop session has its own prompt file:

- Session 31790 → `~/.claude/.tim-loop-prompt-31790`
- Session 45123 → `~/.claude/.tim-loop-prompt-45123`

This means multiple concurrent tim-loops in different projects don't interfere with each other. The SessionStart hook uses the session ID to reinject the correct prompt.

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

# Run as SessionStart hook (outputs JSON)
./scripts/tim-loop-prompt-manager.sh hook
```

## Cleanup

### Automatic Cleanup

Tim Loop automatically cleans up:

- Orphan state files older than 24 hours (on each loop start)
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
| `TIM_PROMPT_DIR` | `~/.claude` | Directory for prompt files |
| `TIM_PROMPT_STALE_MINUTES` | 1440 | Minutes before prompts are stale |

## File Structure

```text
plugins/tim-loop/
├── .claude-plugin/
│   └── plugin.json           # Plugin metadata (name, description, author, version)
├── commands/
│   ├── tim-loop.md           # Skill definition (command syntax, allowed tools)
│   └── cancel-tim-loop.md    # Cancel command (cleanup state files)
├── config.yaml               # Default plugin settings (LLM judge config)
├── scripts/
│   ├── tim-loop-setup.sh     # Main setup script (parses args, creates state, registers hooks)
│   ├── tim_loop_hook.py      # Stop hook (checks completion, re-injects prompt)
│   ├── tim-loop-permission-hook.sh  # PreToolUse hook (auto-approve when enabled)
│   ├── tim-loop-prompt-manager.sh   # SessionStart hook (preserves prompt across compaction)
│   ├── code-quality-validator.py    # PostToolUse hook (file/function size limits)
│   ├── excuse_detector_v2.py # Stop hook (catches deflection patterns)
│   ├── fast_pattern_detector.py     # PostToolUse hook (fast pattern detection)
│   ├── block_bypass_flags.py # PreToolUse hook (blocks --no-verify and similar flags)
│   └── option_expander.py    # UserPromptSubmit hook (expands shorthand options)
├── hooks/
│   └── hooks.json            # Hook configuration (SessionStart, UserPromptSubmit, PreToolUse, PostToolUse, Stop)
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
./plugins/tim-loop/scripts/plan-ops.sh ai-ready plans/active/my-plan.md --reviewer "Your Name"
```

### "Can only implement plans from active/ folder"

Move the plan to active first:

```bash
./plugins/tim-loop/scripts/plan-ops.sh promote plans/drafts/my-plan.md --approver "Your Name"
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

The SessionStart hook should preserve the prompt. Check:

1. Plugin hooks.json is properly installed
2. `scripts/tim-loop-prompt-manager.sh` exists in the plugin folder and is executable
3. Session ID is being passed correctly

### Review stuck in early phase

If full-review keeps looping in Phase 1:

1. Check if Evidence Log is being output
2. Verify the log contains specific file:line references
3. Ensure at least 5 iterations have occurred

Each phase has minimum iteration requirements:

- Phase 1: 5 iterations minimum
- Phases 2-4: 2 iterations minimum
- Phases 5-7: 1 iteration minimum

### Max iterations reached

When max iterations is reached without verification, tim-loop marks the plan as FAILED and exits.

**Recovery steps:**

1. Check the plan file for `<!-- VERIFIED: FAILED -->` marker
2. Review what wasn't completed (the failure reason is in the marker)
3. Run `/tim-loop --verify <plan-file>` to attempt verification again
4. Or increase the limit: `/tim-loop --max-iterations 50 "complex task"`

### Code quality validator keeps blocking

The validator enforces TIM standards (400-line files, 50-line functions, complexity 10). If you're blocked:

1. Refactor the file into smaller modules
2. Extract large functions into smaller units
3. Reduce cyclomatic complexity by extracting conditionals to helper functions
4. Each module should have a single responsibility

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
ls -la ~/.claude/plugins/cache/tim/tim-loop/*/scripts/*.py
```
