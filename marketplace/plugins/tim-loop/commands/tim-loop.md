---
description: "Goal in, working code out: iterative convergence with verification loop"
argument-hint: "TASK [--plan] [--implement FILE] [--tech-review FILE] [--pm-review FILE] [--ai-ready FILE] [--verify FILE] [--wizard FILE] [--no-review] [--no-verify] [--team] [--auto-approve] [--cleanup] [--cleanup-all]"
allowed-tools: ["Bash(${CLAUDE_PLUGIN_ROOT}/scripts/tim-loop-setup.sh:*)"]
---

# Tim Loop

Execute setup to launch Tim Loop with four-phase workflow:

```!
"${CLAUDE_PLUGIN_ROOT}/scripts/tim-loop-setup.sh" $ARGUMENTS
```

---

## Installation & Usage Guide

### Prerequisites

1. **Claude Code CLI** - Install from [claude.ai/code](https://claude.ai/code)
2. **TIM Standards** - This plugin is part of the tim marketplace

### Installation

Install via Claude Code plugin system:

```bash
# Register the TIM marketplace (if not already done)
# Then install tim-loop from the marketplace
```

Or install from the marketplace UI in Claude Code.

### Usage

From within Claude Code:

#### Modes (Mutually Exclusive)

##### Full Workflow (default) - Recommended for most tasks

```text
/tim-loop "add user authentication"
```

**Phases:** Plan -> Review -> Implement -> Verify
**End state:** Plan file with `VERIFIED: YES`, code deployed
**Use for:** Most tasks - provides full safety and quality checks

##### Plan Only (`--plan`)

```text
/tim-loop --plan "design the auth system"
```

**Phases:** Plan only
**End state:** Plan file in `plans/drafts/`, NO code changes
**Use for:** When you want to review the plan yourself before implementation

##### Implement Existing (`--implement`)

```text
/tim-loop --implement plans/active/my-plan.md
```

**Phases:** Implement -> Verify (skips plan creation and review)
**End state:** Code deployed, plan verified
**Requirements:** Plan MUST be in `plans/active/` AND have `AI Developer Ready: yes`
**Use for:** When plan was created separately and already approved

##### Quick Mode (`--no-review`)

```text
/tim-loop --no-review "fix typo in header"
```

**Phases:** Plan -> Implement -> Verify (skips review)
**End state:** Same as full workflow, but faster
**Use for:** Small, obvious tasks where review adds no value

##### Full Review Mode (`--full-review`) - Recommended

```text
/tim-loop --full-review plans/drafts/my-plan.md
```

**Phases:** Seven-phase comprehensive review with per-phase iteration tracking:

| Phase | Focus | Min Iterations | Completion Signal |
|-------|-------|----------------|-------------------|
| 1. Tech Review | Technical accuracy, edge cases | 5 | `<promise>PHASE-1-TECH-DONE</promise>` |
| 2. Devil's Advocate | Assumptions, failure modes | 2 | `<promise>PHASE-2-DEVILS-ADVOCATE-DONE</promise>` |
| 3. Security Review | Auth, validation, OWASP | 2 | `<promise>PHASE-3-SECURITY-DONE</promise>` |
| 4. AI-Ready Review | Unambiguous instructions | 2 | `<promise>PHASE-4-AI-READY-DONE</promise>` |
| 5. Goal Alignment | Original intent preserved | 1 | `<promise>PHASE-5-GOAL-ALIGN-DONE</promise>` |
| 6. PM Review | Organization, flow, clerical | 1 | `<promise>PHASE-6-PM-DONE</promise>` |
| 7. User Advocate | Unauthorized decision audit | 1 | `<promise>PHASE-7-USER-ADVOCATE-DONE</promise>` |

**After all 7 phases:** Output `<promise>FULL-REVIEW-DONE</promise>` to complete.

**Key features:**

- Each phase has its own iteration counter and minimum requirements
- Early phase completion attempts are challenged until minimums are met
- Phase transitions inject the next phase's prompt automatically
- Cannot skip to final completion without completing all phases

**End state:** Plan file ready for implementation (technically sound, AI-ready, goal-aligned)
**Use for:** Complete review in a single session (replaces separate --tech-review and --ai-ready)

##### Tech Review Mode (`--tech-review`)

```text
/tim-loop --tech-review plans/drafts/my-plan.md
```

**Phases:** Technical review by a skeptical senior engineer persona
**End state:** Plan file improved with technical accuracy, edge cases, testability
**Use for:** First-pass review only (use `--full-review` for complete review)

##### PM Review Mode (`--pm-review`)

```text
/tim-loop --pm-review plans/drafts/my-plan.md
```

**Phases:** Project management review to organize the plan after tech reviews

**Focus:**

- Organize for logical implementation flow
- Fix clerical errors
- Ensure approach makes sense
- NEVER reduce scope

**End state:** Plan file organized and ready for promotion
**Use for:** After tech review completes, before promoting to active

##### AI-Ready Review Mode (`--ai-ready`)

```text
/tim-loop --ai-ready plans/active/my-plan.md
```

**Phases:** AI-readiness review by a tech lead persona + goal alignment check
**End state:** Plan file with unambiguous instructions ready for AI implementation
**Use for:** Final review only (use `--full-review` for complete review)

##### Verify Mode (`--verify`)

```text
/tim-loop --verify plans/active/my-plan.md
```

**Phases:** Four-phase verification audit (intent, implementation, TIM rules, remediation)
**End state:** Verified implementation or remediation plan created
**Use for:** Post-implementation verification that plan was fully and correctly implemented

##### Wizard Mode (`--wizard`)

```text
/tim-loop --wizard plans/active/my-plan.md
```

**Interactive wizard** that guides you through the FULL plan lifecycle:
Import -> Full Review (consolidated) -> Tim-Loop -> Complete

The wizard now runs Full Review in a single command (tech review + AI-ready + goal alignment),
then handles promotion and status updates automatically.
**Use for:** When you want step-by-step guidance through all approvals and gates

#### Modifier Options

| Option | Default | Description |
|--------|---------|-------------|
| `--force`, `-f` | - | Override existing active session detection |
| `--team` | - | Use agent teams for parallel implementation. Only valid with full workflow or `--implement`. **(experimental)** |
| `--auto-approve` | - | Auto-approve all tool permissions. **WARNING:** Use with caution. |
| `--max-iterations <n>` | 30 | Safety limit - force exit after N iterations |
| `--max-verify-cycles <n>` | 999999 | Max verification attempts (effectively unlimited) |
| `--min-review-iterations <n>` | 5 | Minimum review passes before allowing completion |
| `--completion-promise` | "COMPLETE" | Phrase that signals completion. Change if "COMPLETE" appears in your task. |
| `--llm-loop` | - | Enable LLM judge for semantic evasion detection (requires LLM judge config) |
| `--dry-run` | - | Preview generated prompt without executing |
| `--help` | - | Show detailed help text |

#### Cleanup Options

| Option | Description |
|--------|-------------|
| `--cleanup` | Remove orphan state files older than 24 hours (from crashed sessions) |
| `--cleanup-all` | Remove ALL state files including active sessions. Use if loop is stuck. |

### How It Works

Tim Loop implements a four-phase workflow with automatic verification:

1. **Phase 1: Create Plan** - Creates a plan document in `plans/drafts/`
2. **Phase 2: Validate Plan** - Validates plan is complete (ADDITIVE-ONLY - cannot remove/modify original items)
3. **Phase 3: Implement** - Implements 100% of the plan exactly as written
4. **Phase 4: Verify** - Verifies 100% of plan objectives are met
   - If 100% objectives met -> COMPLETE
   - If any gaps found -> Fixes or adds corrective phases, loops back to Phase 2

#### The Loop Mechanism

1. When you run `/tim-loop "task"`, it registers a stop hook
2. The hook intercepts when Claude tries to exit
3. If the completion promise wasn't output, the prompt is re-injected
4. Claude sees its previous work in files and continues
5. Loop repeats until completion or max iterations

#### Completion Rules (CRITICAL)

**100% means 100%.** The loop is NOT complete until:

1. **Every Goal achieved** - Not partially, not "good enough"
2. **Every Implementation Step executed** - All of them, in full
3. **Every Test exists and passes** - From Testing Strategy
4. **Every Completion Criterion met** - Each one verified
5. **Every file created is imported AND used** - Not just created
6. **Zero TODO/FIXME comments** in new code

**Orphaned code (exists but not used) = NOT implemented.**

For full rules, see the tim-loop documentation in the plugin.
