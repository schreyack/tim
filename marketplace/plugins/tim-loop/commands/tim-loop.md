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

## What This Does

Tim Loop ensures a task gets done **completely and correctly**. It registers a stop hook that prevents Claude from exiting until the work is verified. If gaps remain, the prompt re-injects and Claude continues. The loop breaks only when every objective is met or max iterations are reached.

**100% means 100%.** Every goal achieved. Every step executed. Every test passing. Every file created is imported AND used. Zero TODO/FIXME. Orphaned code (exists but not used) = not implemented.

---

## Modes

| Mode | Command | What It Does |
|------|---------|-------------|
| **Full workflow** (default) | `/tim-loop "add auth"` | Plan → Review → Implement → Verify |
| **Plan only** | `/tim-loop --plan "design auth"` | Creates plan in `plans/drafts/`, no code changes |
| **Implement existing** | `/tim-loop --implement plans/active/plan.md` | Implement → Verify (plan must be active + AI-ready) |
| **Quick** | `/tim-loop --no-review "fix typo"` | Plan → Implement → Verify (skips review) |
| **Full review** | `/tim-loop --full-review plans/drafts/plan.md` | 7-phase review: Tech → Devil's Advocate → Security → AI-Ready → Goal Align → PM → User Advocate |
| **Tech review** | `/tim-loop --tech-review plans/drafts/plan.md` | Technical accuracy review only |
| **PM review** | `/tim-loop --pm-review plans/drafts/plan.md` | Organization and flow review (never reduces scope) |
| **AI-ready** | `/tim-loop --ai-ready plans/active/plan.md` | Unambiguous instructions check + goal alignment |
| **Verify** | `/tim-loop --verify plans/active/plan.md` | Post-implementation audit: intent, code, TIM rules |
| **Wizard** | `/tim-loop --wizard plans/active/plan.md` | Interactive lifecycle guide: Import → Review → Implement → Complete |

### Full Review Phases

| Phase | Focus | Min Iterations |
|-------|-------|----------------|
| 1. Tech Review | Technical accuracy, edge cases | 5 |
| 2. Devil's Advocate | Assumptions, failure modes | 2 |
| 3. Security Review | Auth, validation, OWASP | 2 |
| 4. AI-Ready Review | Unambiguous instructions | 2 |
| 5. Goal Alignment | Original intent preserved | 1 |
| 6. PM Review | Organization, flow, clerical | 1 |
| 7. User Advocate | Unauthorized decision audit | 1 |

Each phase has its own iteration counter. Early completion attempts are challenged until minimums are met.

---

## Options

| Option | Default | Description |
|--------|---------|-------------|
| `--force`, `-f` | - | Override existing session detection |
| `--team` | - | Parallel implementation with agent teams (experimental) |
| `--auto-approve` | - | Auto-approve tool permissions. Use with caution. |
| `--max-iterations <n>` | 30 | Force exit after N iterations |
| `--max-verify-cycles <n>` | 999999 | Max verification attempts |
| `--min-review-iterations <n>` | 5 | Min review passes before allowing completion |
| `--completion-promise` | "COMPLETE" | Completion signal. Change if "COMPLETE" appears in your task. |
| `--llm-loop` | - | Enable LLM judge for semantic evasion detection |
| `--dry-run` | - | Preview prompt without executing |
| `--cleanup` | - | Remove orphan state files older than 24h |
| `--cleanup-all` | - | Remove ALL state files including active sessions |
| `--help` | - | Show detailed help |
