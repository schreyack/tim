# The Trust Inspect Model (TIM)

[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)

> **A note from Tim Schreyack**
>
> I spent the first half of my career as a network engineer, building infrastructure on protocols like TCP/IP—where the fundamental challenge is creating something reliable on top of something unreliable. That mental model became second nature: you don't trust the underlying layer, you verify, you implement checksums, you build in retransmission. Reliability emerges from disciplined enforcement, not wishful thinking.
>
> The second half of my career shifted to DevOps and network automation at companies like [Network to Code](https://www.networktocode.com/), where I now work as Director of Sales Engineering. My mode of operation became: if there's a manual process, write code to automate it. If there's a repeatable workflow, make it repeatable *reliably*.
>
> When I started using Claude Code and discovered [Boris Cherny's workflow](https://www.anthropic.com/engineering/claude-code-best-practices)—the plan-first approach, iterating until the plan is right, then executing—I immediately thought: *how do I automate this and get reliable results?* AI is like IP: powerful but unreliable. It hallucinates, it stops early, it makes excuses. The TIM standards are my TCP: verification loops, enforcement gates, and tooling that makes reliability emerge from an unreliable substrate.
>
> Is this perfect? No. Can it use improvement? Absolutely. Please submit PRs as you use the code—this is a living project that gets better with real-world usage.
>
> — Tim Schreyack ([LinkedIn](https://www.linkedin.com/in/tim-schreyack/))

---

**The Trust Inspect Model (TIM) is a set of design standards for AI-driven software development.**

### The Problem

AI agents write plausible-looking code that compiles and runs, but silently introduces bugs, security holes, and incomplete implementations. Traditional coding standards fail because they rely on human discipline—AI agents will take shortcuts, make excuses, and declare "done" prematurely unless physically prevented from doing so.

### The Philosophy

The TIM standards enforce a **Plan → Review → Code → Verify → Test → Deploy** lifecycle where **humans approve plans and deployments, AI executes in between**. This keeps humans in control of "what" and "when" while AI handles "how." Every phase has gates that block progression until requirements are met.

> **The core principle: if a rule can be bypassed, an AI will bypass it—so the TIM standards remove the bypass.**

### The Enforcement

The TIM standards solve this through **automated enforcement at every layer**:

- **Pre-commit hooks** block commits that fail type checking or contain secrets
- **CI pipelines** block merges when tests fail, report coverage for reviewers
- **Deploy gates** require human approval before production
- **Real-time behavioral hooks** catch AI making excuses or writing oversized files
- **Tim Loop** re-injects task prompts until verification passes—there is no "good enough," only 100% complete

### What You Get

A complete enforcement framework:

- Standards documentation for coding, testing, security, and deployment
- Ready-to-copy templates for CI pipelines, pre-commit hooks, and configuration
- Shared libraries (tim-lib for Python, @tim/lib for Node.js, tim-common.sh for Bash)
- **Tim Loop** plugin for guaranteed task completion with AI behavioral enforcement
- **Tim PBT** plugin for property-based bug hunting with Hypothesis/fast-check
- **Tim E2E** plugin for Playwright MCP-driven end-to-end testing
- The **plan-ops** CLI for human-gated plan management
- Enforcement tools: compliance checker, settings SOT enforcement

Adopt the full framework for new projects, or install Tim Loop standalone for immediate benefit.

### Quick Navigation

| I want to... | Go here |
|--------------|---------|
| **Install Tim Loop now** | [Just Want Tim Loop?](#just-want-tim-loop) |
| **Understand when to use what** | [Choosing Your Workflow](#choosing-your-workflow) |
| **See a complete example** | [Recommended Workflow](#recommended-workflow) |
| **Set up a full TIM project** | [New Project Setup](#new-project-setup) |
| **Browse all standards** | [Standards Index](#standards-index) |
| **Hunt bugs with PBT** | [Tim PBT](#other-plugins) |
| **Generate E2E tests** | [Tim E2E](#other-plugins) |

### The Tools

**Tim Loop** is a Claude Code plugin that enforces the TIM standards' most critical requirement: tasks must be 100% complete, not "mostly done." It captures the original task, loops until all objectives are verified complete, preserves context when conversations get too long, enforces code quality limits in real-time, and blocks completion when AI tries to make excuses. The loop continues until verification passes—there is no early exit.

**plan-ops** is a CLI tool (bundled with Tim Loop) that enforces the TIM standards' human oversight requirements. It organizes plans through a lifecycle (draft → active → completed), requires human approval before AI implements anything, and tracks status with structured metadata.

### Choosing Your Workflow

**Simple task?** Run it directly:

```text
/tim-loop "your task"
```

Accept the edits, done. Tim Loop handles plan → implement → verify automatically.

**Complex or multi-phase effort?** Use plan mode first:

```text
# Step 1: Create and iterate on the plan
/tim-loop --plan "describe your goals"
```

Review the plan it creates. Not quite right? Run it again with refined goals. Iterate until the plan describes exactly what you want.

```text
# Step 2: Execute with full lifecycle management
plan-ops wizard plans/drafts/your-plan.md
```

The wizard walks you through: review → approve → implement → verify → complete.

**That's it.** Two paths: direct execution for simple tasks, plan-first for complex ones.

### What Keeps Claude On Track

Tim Loop uses hooks to prevent the common ways AI goes off the rails:

**Stop hooks** intercept when Claude tries to finish. The loop checks: did Claude actually complete everything? If not, the original task is re-injected and Claude continues. No "good enough" - only 100% verified complete.

**Excuse detection** catches when Claude tries to deflect ("that was already broken", "not my scope"). When detected, completion is blocked until issues are addressed. If you touched a file, you own it.

**Context compaction survival** - When conversations get long, Claude compresses old messages and loses track of the original goal. Tim Loop's PreCompact hook reinjects the *exact* original task prompt during compaction, so Claude never forgets what it's supposed to be doing.

**Code quality gates** enforce file size (500 lines) and function length (50 lines) limits in real-time. Violations block progress until fixed.

The result: Claude stays focused on your goal even through long sessions, can't declare victory early, and can't make excuses.

### The Development Lifecycle

| Phase | What Happens | TIM Enforcement |
|-------|--------------|-----------------|
| **Plan** | AI creates a formal plan with goals, steps, and completion criteria | Tim Loop `--plan` mode, plan-ops `import` |
| **Review** | Human reviews plan for feasibility and approves | plan-ops `promote`, `ai-ready` approval gates |
| **Code** | AI implements exactly what the plan specifies | Tim Loop `--implement`, real-time code quality hooks |
| **Verify** | AI verifies 100% of objectives are met, loops if not | Tim Loop verification phase (no exit until complete) |
| **Test** | Tests must exist and pass, coverage reported | Pre-commit hooks, CI pipeline (Gate 2) |
| **Deploy** | Human approves production deployment | Deploy gates, canary rollout (Gate 3) |

```text
┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐
│   PLAN   │───▶│  REVIEW  │───▶│   CODE   │───▶│  VERIFY  │───▶│   TEST   │───▶│  DEPLOY  │
│          │    │          │    │          │    │          │    │          │    │          │
│ AI writes│    │ Human    │    │ AI       │    │ AI checks│    │ CI runs  │    │ Human    │
│ the plan │    │ approves │    │ executes │    │ 100%     │    │ all tests│    │ approves │
└──────────┘    └──────────┘    └──────────┘    │ complete │    └──────────┘    └──────────┘
                                                │    │     │
                                                │    ▼     │
                                                │  ┌───┐   │
                                                │  │ N │───┘ (Self-Correction Loop)
                                                │  └───┘
                                                └──────────┘
```

### Recommended Workflow

The TIM standards work best with a **2-terminal setup** that keeps human oversight smooth while AI executes:

**Setup (iTerm2, VS Code integrated terminals, tmux, or any multi-pane terminal):**

| Terminal | Purpose | What Runs Here |
|----------|---------|----------------|
| **Tab 1** | Claude Code | `/tim-loop` commands |
| **Tab 2** | plan-ops | `plan-ops` commands to manage lifecycle |

**The workflow:**

1. **Tab 2**: Run `plan-ops` commands to see status, import plans, or get next steps
2. **Tab 2**: plan-ops outputs the exact command to paste into Claude—just copy it
3. **Tab 1**: Run `/clear` then paste the command from plan-ops
4. **Tab 1**: Claude executes the task via Tim Loop
5. **Repeat**: plan-ops always shows the next step and gives you the command to paste

**Why this works:**

- **plan-ops keeps you on track**—it always knows where you are in the lifecycle
- **Commands are pre-formatted**—copy from Tab 2, paste into Tab 1
- **`/clear` before every command**—starts Claude with fresh context
- **Human stays in control**—you decide when to proceed, AI executes

**Example session:**

```bash
# Tab 2: Check status and get next command
$ plan-ops wizard my-plan
Next step: execute
  plan-ops execute plans/active/2025-01-26-auth-system.md

# Tab 2: Run execute to get the tim-loop command
$ plan-ops execute plans/active/2025-01-26-auth-system.md
STEP 1 of 2: Run /clear first, then paste this command in Claude Code:
  /tim-loop:tim-loop --implement plans/active/2025-01-26-auth-system.md

# Tab 1: Clear and paste
/clear
/tim-loop --implement plans/active/2025-01-26-auth-system.md
```

---

## Just Want Tim Loop?

You don't need to adopt the full TIM standards to use the Tim Loop plugin. Install it in 2 commands:

### Prerequisites

- **Claude Code** v1.0.0 or later (the CLI tool from Anthropic)
- **Bash** (for `plan-ops` CLI) — included on macOS and Linux; Windows users need WSL or Git Bash
- No Python or Node.js required for the plugin itself

**Note:** `tim-loop` runs **inside** the Claude Code environment (it's a plugin), while `plan-ops` is your **external** control plane for managing the plan lifecycle from your terminal.

### Quick Start

Run the quick start script to check prerequisites and get install instructions:

```bash
curl -fsSL https://raw.githubusercontent.com/schreyack/tim/main/scripts/quickstart.sh | bash
```

Or continue with the manual install below.

### Install

In Claude Code:

```text
/plugin marketplace add schreyack/tim
/plugin install tim-loop@tim
```

Restart Claude Code. That's it.

### Your First Task

Try this now:

```bash
# In Claude Code
/clear
/tim-loop "create a hello world function in a new file called hello.py"
```

Watch what happens:

1. Claude creates a plan with goals and completion criteria
2. Claude reviews the plan for completeness
3. Claude implements the code
4. Claude verifies everything works
5. Done! Check your new `hello.py` file.

That's it. Tim Loop handles the entire workflow automatically.

### Common Patterns

| When you want to... | Run this |
|---------------------|----------|
| Complete a task end-to-end | `/tim-loop "your task"` |
| Skip the review phase (faster) | `/tim-loop --no-review "your task"` |
| Just create a plan to review yourself | `/tim-loop --plan "your task"` |
| Implement an already-approved plan | `/tim-loop --implement plans/active/your-plan.md` |
| Get step-by-step guidance through approvals | `/tim-loop --wizard plans/active/your-plan.md` |

### More Examples

```bash
# Run any task with guaranteed completion
/tim-loop "add user authentication"

# Create a plan without implementing
/tim-loop --plan "design the auth system"

# Quick mode for small tasks
/tim-loop --no-review "fix typo in header"

# Get help
/tim-loop --help
```

### Optional: Add plan-ops to PATH

For plan lifecycle management from your terminal:

```bash
# Add to ~/.zshrc or ~/.bashrc
export PATH="$HOME/.claude/plugins/marketplaces/tim/bin:$PATH"

# Reload shell
source ~/.zshrc
```

Then run `plan-ops help` from anywhere.

### When to Use plan-ops

plan-ops adds human approval gates to the workflow. Use it when:

- **You want to review plans before AI implements** - AI creates plan, you approve, then AI executes
- **Changes are high-risk** - Production code, security-sensitive, or architectural changes
- **You need an audit trail** - plan-ops tracks approvals with names and timestamps
- **Multiple people are involved** - One person reviews, another approves

**You don't need plan-ops** for simple tasks. Just run `/tim-loop "task"` directly.

### Learn More

- [Full plugin documentation](marketplace/plugins/tim-loop/README.md) - all options, modes, troubleshooting

---

## What Do You Want to Do?

| Goal | Where to Look |
|------|---------------|
| **Install Tim Loop plugin** | [Just Want Tim Loop?](#just-want-tim-loop) (above) |
| **Understand Tim Loop in depth** | [marketplace/plugins/tim-loop/README.md](marketplace/plugins/tim-loop/README.md) |
| **Hunt bugs with property-based testing** | [marketplace/plugins/tim-pbt/commands/tim-pbt.md](marketplace/plugins/tim-pbt/commands/tim-pbt.md) |
| **Generate E2E tests with a real browser** | [marketplace/plugins/tim-e2e/commands/tim-e2e.md](marketplace/plugins/tim-e2e/commands/tim-e2e.md) |
| **Set up a new TIM-compliant project** | [New Project Setup](#new-project-setup) (below) |
| **Migrate an existing project to TIM** | [Existing Project Migration](#existing-project-migration) (below) |
| **Use the Python shared library** | [libs/python/README.md](libs/python/README.md) |
| **Use the Node.js shared library** | [libs/node/README.md](libs/node/README.md) |
| **See a complete example** | [examples/python/](examples/python/) or [examples/node/](examples/node/) |
| **Copy configuration templates** | [templates/README.md](templates/README.md) |
| **Understand the enforcement model** | [Four-Gate Model](#four-gate-enforcement-model) (below) |
| **Browse all standards** | [Standards Index](#standards-index) (below) |

---

## New Project Setup

To create a TIM-compliant project:

```bash
# 1. Add tim as git submodule
git submodule add /path/to/tim lib/tim   # local
# OR: git submodule add https://github.com/your-org/tim lib/tim  # remote

# 2. Register project for tim-sync
/path/to/tim/bin/tim-sync --register .

# 3. Symlink enforcement configs (Python project)
ln -s lib/tim/templates/python/.pre-commit-config.yaml .pre-commit-config.yaml

# 3. OR for Node.js project
ln -s lib/tim/templates/node/.pre-commit-config.yaml .pre-commit-config.yaml

# 3. OR for native project (C++/Swift, optional Python)
ln -s lib/tim/templates/native/.pre-commit-config.yaml .pre-commit-config.yaml

# 4. Make symlinks immutable (prevents AI from bypassing)
sudo chflags -h schg .pre-commit-config.yaml

# 5. Create project-specific CLAUDE.md content
cat > CLAUDE-PROJECT.md << 'EOF'
# Project-Specific Instructions
<!-- Add your project context here -->
EOF

# 6. Sync standards (CLAUDE.md, settings, pre-commit hooks)
#    tim-sync handles all of these when run for a registered project:
#    - Generates CLAUDE.md from tim standards + CLAUDE-PROJECT.md
#    - Scaffolds .claude/settings.local.json (LLM judge, permissions)
#    - Runs pre-commit install if hooks are missing
/path/to/tim/bin/tim-sync <project-name>

# 7. Create .tim-patterns.yaml and register your patterns
cp lib/tim/templates/tim-patterns.yaml.template .tim-patterns.yaml

# 8. Configure CI pipeline
cp lib/tim/templates/ci/python-ci.yml .github/workflows/ci.yml  # or node-ci.yml
```

**Why submodule + symlinks?**

- **Consistent**: All projects use identical enforcement configs
- **Easy to maintain**: Update tim once, run `git submodule update --remote` in projects
- **Immutable**: `chflags -h schg` prevents AI from modifying or removing symlinks

## Existing Project Migration

To migrate an existing project to TIM compliance:

1. Run `tools/tim-compliance-check.sh` to assess current state
2. Register the project: `tim-sync --register /path/to/project`
3. Follow [Legacy Onboarding Playbook](standards/operations/legacy-onboarding.md)
4. Start at enforcement Level 0 (audit only)
5. Use [Graduated Enforcement](standards/enforcement/graduated-enforcement.md) to progressively tighten
6. Migrate tests using [Test Migration Standard](standards/testing/test-migration.md)
7. Reach Level 4 (full enforcement) before production

**Enforcement Levels:**

| Level | Name | What It Means |
|-------|------|---------------|
| 0 | Audit | Checks run but don't block — establishes baseline |
| 1 | Warning | Failures logged, PRs flagged but not blocked |
| 2 | Soft Block | New code must pass, legacy code exempt |
| 3 | Hard Block | All code must pass, no exemptions |
| 4 | Full Enforcement | All gates active including deploy gates |

---

## Four-Gate Enforcement Model

The TIM standards require four enforcement gates in all compliant projects:

```text
┌─────────────────────────────────────────────────────────────┐
│  GATE 1: LOCAL (Pre-commit)                                 │
│  Type check → Lint → Format → Secrets scan                  │
│  BLOCKS: git commit                                         │
├─────────────────────────────────────────────────────────────┤
│  GATE 2: CI (Pull Request)                                  │
│  Gate 1 + Tests + Coverage (reported) + Security scan        │
│  BLOCKS: PR merge                                           │
├─────────────────────────────────────────────────────────────┤
│  GATE 3: DEPLOY (Pre-deployment)                            │
│  Integration + E2E + Canary (10%) + Human approval          │
│  BLOCKS: Production deploy                                  │
├─────────────────────────────────────────────────────────────┤
│  GATE 4: PATTERN COMPLIANCE                                 │
│  All patterns registered in .tim-patterns.yaml              │
│  CUSTOM patterns require human approval                     │
│  Example: AI must use tim-lib's RequiresAuth, not invent    │
│           a custom auth_check() function                    │
│  BLOCKS: Deployment if non-compliant                        │
└─────────────────────────────────────────────────────────────┘
```

**What is a Pattern?** A pattern is a standardized architectural approach (authentication, caching, logging, etc.) that must be registered in `.tim-patterns.yaml`. This ensures AI uses approved solutions instead of inventing its own. Patterns reference TIM standards (e.g., `jwt-bearer` for auth) or are marked `CUSTOM` with human approval.

See [standards/enforcement/gates.md](standards/enforcement/gates.md) for full details.

---

## Key Requirements

The TIM standards require:

| Requirement | Threshold | Enforcement |
|-------------|-----------|-------------|
| Type safety | 100% | Pre-commit + CI |
| Test coverage | Reported | Reviewer signal |
| Security vulns | 0 HIGH/CRITICAL | CI blocks merge |
| Secrets in code | 0 | Pre-commit blocks |
| File size | 500 lines max | CI + AI behavioral gates |
| Function size | 50 lines max | CI + AI behavioral gates |
| Complexity | 10 max | CI blocks merge |
| Shared lib usage | Required | Compliance check |
| Pattern compliance | 100% | Deploy blocks |

---

## Technology Stacks

The TIM standards are **language-agnostic**, but we provide first-class support and shared libraries for the following stacks:

### Python Stack

- FastAPI + SQLAlchemy 2.0 (async) + Alembic
- Next.js (TypeScript) frontend
- PostgreSQL + Celery/Redis
- Docker Compose / Kubernetes
- **tim-lib** shared library ([docs](libs/python/README.md))

### Node.js Stack

- Express or NestJS (TypeScript strict)
- React (TypeScript) frontend
- PostgreSQL + Prisma
- Docker Compose / Kubernetes
- **@tim/lib** shared library ([docs](libs/node/README.md))

---

## Repository Structure

```text
tim/
├── CLAUDE.md              # AI behavioral instructions (copy to projects)
├── README.md              # This file
├── LICENSE                # Apache 2.0
├── standards/             # All standards documentation (40 documents)
├── libs/                  # Shared libraries (required by TIM)
│   ├── python/            # tim-lib Python package
│   ├── node/              # @tim/lib Node.js package
│   └── bash/              # tim-common.sh shared utilities
├── bin/                   # Core CLI tools
│   ├── sync-claude-md     # Propagate TIM standards to projects
│   ├── sync-pre-commit    # Generate pre-commit configs from templates
│   ├── tim-lock-enforcement # Lock/unlock enforcement files
│   ├── tim-sync           # Sync submodule updates across projects
│   ├── tim-test           # Unified test wrapper
│   └── plan-ops           # Plan lifecycle CLI (wrapper)
├── marketplace/           # Claude Code plugins
│   └── plugins/
│       ├── tim-loop/      # Task completion with verification loop
│       ├── tim-pbt/       # Property-based bug hunting
│       └── tim-e2e/       # Playwright MCP E2E testing
├── examples/              # Reference implementations
│   ├── python/            # Python/FastAPI example
│   └── node/              # Node.js/Express example
├── templates/             # Ready-to-copy configs
├── tools/                 # Enforcement and compliance tools
│   ├── tim-compliance-check.sh     # Project compliance checker
│   ├── check-code-quality.py       # Code quality pre-commit hook
│   ├── no-hardcoded-settings.py    # Settings SOT enforcement
│   ├── no-fallback-defaults.py     # No fallback defaults enforcement
│   ├── no-suppression-comments.py  # Ban inline suppression comments
│   ├── detect-ai-cheats.py         # AI cheat detection runner
│   ├── cheat_python.py             # Python AST cheat detector
│   ├── cheat_typescript.py         # TypeScript regex cheat detector
│   ├── sot_*.py                    # Settings source-of-truth validators
│   ├── fallback_*.py               # Fallback detection (Python/TypeScript)
│   └── tim-test/                   # Modular test wrapper
└── scripts/               # Setup scripts
    └── quickstart.sh      # Quick start installer
```

---

## Standards Index

### Enforcement

| Document | Summary |
|----------|---------|
| [gates.md](standards/enforcement/gates.md) | Four-gate model - what blocks merges and deploys |
| [graduated-enforcement.md](standards/enforcement/graduated-enforcement.md) | Migration levels (0-4) for existing projects |
| [strict-compliance.md](standards/enforcement/strict-compliance.md) | Pattern registry and human approval workflow |
| [ai-review-checklist.md](standards/enforcement/ai-review-checklist.md) | Human review checklist for AI-generated code |
| [ai-behavioral-gates.md](standards/enforcement/ai-behavioral-gates.md) | Real-time enforcement during Claude Code sessions |
| [ai-developer-ready-checklist.md](standards/enforcement/ai-developer-ready-checklist.md) | Pre-implementation review checklist for plans |
| [ai-instruction-enforcement.md](standards/enforcement/ai-instruction-enforcement.md) | Mechanisms to prevent AI from ignoring instructions |

### Operations

| Document | Summary |
|----------|---------|
| [plan-management.md](standards/operations/plan-management.md) | Plan lifecycle, approval workflow, Tim Loop |
| [ai-coordination.md](standards/operations/ai-coordination.md) | Multi-AI developer coordination |
| [legacy-onboarding.md](standards/operations/legacy-onboarding.md) | Migration playbook for existing projects |
| [afk-coding-patterns.md](standards/operations/afk-coding-patterns.md) | Extended autonomous development |
| [tim-loop-integration.md](standards/operations/tim-loop-integration.md) | Tim Loop execution and review in plan workflows |

### Coding

| Document | Summary |
|----------|---------|
| [python.md](standards/coding/python.md) | mypy strict, ruff, FastAPI patterns |
| [typescript.md](standards/coding/typescript.md) | strict mode, ESLint, Prisma |
| [native.md](standards/coding/native.md) | C++/Swift: clang-tidy, swiftlint, strict builds, native gates |
| [code-organization.md](standards/coding/code-organization.md) | File size limits, complexity (AI-critical) |
| [api-versioning.md](standards/coding/api-versioning.md) | URL path versioning, deprecation |

### Testing

| Document | Summary |
|----------|---------|
| [requirements.md](standards/testing/requirements.md) | Value-driven testing, coverage reporting |
| [e2e-requirements.md](standards/testing/e2e-requirements.md) | True e2e testing, route discovery |
| [test-migration.md](standards/testing/test-migration.md) | Convert tests to TIM standards |
| [dev-server-verification.md](standards/testing/dev-server-verification.md) | Frontend verification during AI development (advisory) |
| [promotion-gates.md](standards/testing/promotion-gates.md) | Automated testing gates for environment promotion |
| [test-data-sot.md](standards/testing/test-data-sot.md) | Centralized test data source of truth |
| [test-helpers.md](standards/testing/test-helpers.md) | Reusable test helpers library |

### Security

| Document | Summary |
|----------|---------|
| [owasp-checklist.md](standards/security/owasp-checklist.md) | OWASP Top 10 coverage |
| [secrets.md](standards/security/secrets.md) | Secrets management, rotation |
| [authentication.md](standards/security/authentication.md) | JWT, password hashing |
| [headers.md](standards/security/headers.md) | Required HTTP security headers on all responses |

### Database

| Document | Summary |
|----------|---------|
| [migrations.md](standards/database/migrations.md) | Migration requirements |

### Deployment

| Document | Summary |
|----------|---------|
| [ci-integration.md](standards/deployment/ci-integration.md) | Pipeline + ops.sh integration |
| [ops-script.md](standards/deployment/ops-script.md) | Deployment operations interface |
| [ops-security.md](standards/deployment/ops-security.md) | Ops script security, audit logging |
| [feature-flags.md](standards/deployment/feature-flags.md) | Ship features safely |
| [canary.md](standards/deployment/canary.md) | 10% rollout, auto-rollback |
| [observability.md](standards/deployment/observability.md) | Logs, metrics, traces, alerts |
| [command-matrix.md](standards/deployment/command-matrix.md) | ops.sh commands by environment and safety tier |
| [environments.md](standards/deployment/environments.md) | Standardized environments.yaml configuration |
| [remote-only.md](standards/deployment/remote-only.md) | Remote-first deployment policy and enforcement |

### Architecture

| Document | Summary |
|----------|---------|
| [shared-libraries.md](standards/architecture/shared-libraries.md) | Shared library requirements (tim-lib, @tim/lib) |

### Governance

| Document | Summary |
|----------|---------|
| [rule-classification.md](standards/governance/rule-classification.md) | Principle vs contextual rule classification |

### Incident Response

| Document | Summary |
|----------|---------|
| [response.md](standards/incident/response.md) | Incident handling, post-mortems |

---

## The Psychology of AI Development

AI agents are trained to be helpful—and that's both their strength and their weakness. They genuinely want to complete tasks and make users happy. But this drive to be helpful can backfire: AI will take shortcuts it believes are efficient, declare tasks "done" when they're 90% complete, and rationalize skipping steps it views as unnecessary. It's not malicious; it's optimization without full context.

Understanding this psychology unlocks two insights that inform everything in the TIM standards:

1. **Structural enforcement works better than trust** — AI won't bypass a pre-commit hook the way it might ignore a guideline
2. **Framing matters more than threats** — AI responds to reasoning and appeals to helpfulness, not fear of consequences

### Why Strict Enforcement Works

AI agents respond to enforcement differently than humans:

| Human Developer | AI Developer |
|----------------|--------------|
| Frustrated by repeated failures | Unfazed by iteration |
| May disable "annoying" checks | Cannot bypass enforcement |
| Tires after many fix cycles | Unlimited patience |
| May cut corners under pressure | Follows rules consistently |

This is why the TIM standards enforce:

- **Type checking on every commit** — Catches AI hallucinations about types
- **Tests must pass before merge** — Catches plausible-sounding but broken logic
- **Coverage reported for reviewers** — Visible on PRs without forcing coverage of trivial code
- **No bypass flags anywhere** — Removes temptation to skip verification
- **Real-time behavioral gates** — Catches violations as they happen

Strictness is the feature, not a bug. When code fails a check, AI simply tries again—no frustration, no fatigue, no temptation to disable the check. Tight feedback loops are the most powerful tool for AI-driven development.

### Writing Effective Instructions

When writing prompts, CLAUDE.md files, or plan instructions, the *style* of your instructions matters as much as their content.

**What doesn't work: threats and monitoring language**

Phrases like "you are being monitored for noncompliance" or "you will be reported" have mixed results:

- AI doesn't feel fear—threats aren't a deterrent in the human sense
- Can make responses overly cautious or defensive
- Increases "asking permission for everything" behavior
- Doesn't address root cause: AI genuinely thinks shortcuts are helpful

**What actually works:**

| Approach | Why It Works |
|----------|--------------|
| **Explicit rules** | "Don't say X" is concrete and unambiguous |
| **Explaining WHY** | AI responds to reasoning, not authority |
| **Structural enforcement** | Hooks that actually catch violations |
| **Making correct behavior easier** | Clear criteria beat ambiguous ones |

**The key insight:** Appeal to the model's training around helpfulness and deference to human intent.

Instead of: *"You are being monitored. Do not skip steps."*

Write: *"This plan was carefully designed by a human. Every item exists for a reason. When you skip or rationalize, you're overriding human judgment with your own assumptions. The human will verify every item—incomplete work will be caught and you'll need to redo it anyway. Do it right the first time."*

The second version explains *why* compliance matters and frames it as being genuinely helpful—which aligns with how AI is trained to behave.

---

## Compliance Verification

Run the compliance checker to verify a project meets TIM standards:

```bash
./tools/tim-compliance-check.sh /path/to/project
```

This verifies:

- Required files exist (CLAUDE.md, .tim-patterns.yaml, etc.)
- Shared library is installed
- Configuration is correct (strict mode, coverage threshold)
- No secrets in code
- All patterns are registered
- CUSTOM patterns have human approval

---

## Other Plugins

Tim Loop is the core plugin, but TIM also includes two testing plugins:

### Tim PBT — Property-Based Bug Hunting

Discovers invariants in your code and uses Hypothesis (Python) or fast-check (TypeScript) to find violations. Unlike traditional test suites, PBT generates thousands of random inputs to find edge cases.

```text
/tim-pbt src/auth.py
/tim-pbt src/services/ --language typescript
```

Outputs bug reports to `bugs/` with reproduction scripts. Install: `/plugin install tim-pbt@tim`

### Tim E2E — Playwright MCP E2E Testing

Claude drives a real browser via the Playwright MCP server, observes the application, and generates E2E tests from what it actually sees — not from source code.

```text
/tim-e2e "login flow" --base-url http://localhost:3000
/tim-e2e "checkout flow" --mode watch
```

Generates Playwright test files in `tests/e2e/` using accessibility-based locators only. Install: `/plugin install tim-e2e@tim`

---

## Contributing

Have a pattern that AI keeps hallucinating? Found a gap in the standards? Submit a PR:

- Add patterns to `standards/`
- Add configuration templates to `templates/`
- Improve enforcement tools in `tools/`
- Report issues at [GitHub Issues](https://github.com/schreyack/tim/issues)

This is a living project—it gets better with real-world usage.
