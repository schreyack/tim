# TIM Design Standards

> **A note from Tim Schreyack**
>
> I spent the first half of my career as a network engineer, building infrastructure on protocols like TCP/IP—where the fundamental challenge is creating something reliable on top of something unreliable. That mental model became second nature: you don't trust the underlying layer, you verify, you implement checksums, you build in retransmission. Reliability emerges from disciplined enforcement, not wishful thinking.
>
> The second half of my career shifted to DevOps and network automation at companies like [Network to Code](https://www.networktocode.com/), where I now work as Director of Sales Engineering. My mode of operation became: if there's a manual process, write code to automate it. If there's a repeatable workflow, make it repeatable *reliably*.
>
> When I started using Claude Code and discovered [Boris Cherny's workflow](https://www.anthropic.com/engineering/claude-code-best-practices)—the plan-first approach, iterating until the plan is right, then executing—I immediately thought: *how do I automate this and get reliable results?* AI is like IP: powerful but unreliable. It hallucinates, it stops early, it makes excuses. The TIM standards are my TCP: verification loops, enforcement gates, and tooling that makes reliability emerge from an unreliable substrate.
>
> — Tim Schreyack ([LinkedIn](https://www.linkedin.com/in/tim-schreyack/))

---

**TIM is a set of design standards for AI-driven software development.**

### The Problem

AI agents write plausible-looking code that compiles and runs, but silently introduces bugs, security holes, and incomplete implementations. Traditional coding standards fail because they rely on human discipline—AI agents will take shortcuts, make excuses, and declare "done" prematurely unless physically prevented from doing so.

### The Philosophy

The TIM standards enforce a **Plan → Review → Code → Verify → Test → Deploy** lifecycle where **humans approve plans and deployments, AI executes in between**. This keeps humans in control of "what" and "when" while AI handles "how." Every phase has gates that block progression until requirements are met.

The core principle: if a rule can be bypassed, an AI will bypass it—so the TIM standards remove the bypass.

### The Enforcement

The TIM standards solve this through **automated enforcement at every layer**:

- **Pre-commit hooks** block commits that fail type checking or contain secrets
- **CI pipelines** block merges without 90% test coverage
- **Deploy gates** require human approval before production
- **Real-time behavioral hooks** catch AI making excuses or writing oversized files
- **Tim Loop** re-injects task prompts until verification passes—there is no "good enough," only 100% complete

### What You Get

A complete enforcement framework:
- Standards documentation for coding, testing, security, and deployment
- Ready-to-copy templates for CI pipelines, pre-commit hooks, and configuration
- Shared libraries (tim-lib for Python, @tim/lib for Node.js)
- The **Tim Loop** plugin for guaranteed task completion
- The **plan-ops** CLI for human-gated plan management

Adopt the full framework for new projects, or install Tim Loop standalone for immediate benefit.

### The Tools

**Tim Loop** is a Claude Code plugin that enforces the TIM standards' most critical requirement: tasks must be 100% complete, not "mostly done." It captures the original task, loops until all objectives are verified complete, preserves context when conversations get too long, enforces code quality limits in real-time, and blocks completion when AI tries to make excuses. The loop continues until verification passes—there is no early exit.

**plan-ops** is a CLI tool (bundled with Tim Loop) that enforces the TIM standards' human oversight requirements. It organizes plans through a lifecycle (draft → active → completed), requires human approval before AI implements anything, and tracks status with structured metadata.

### The Development Lifecycle

| Phase | What Happens | TIM Enforcement |
|-------|--------------|-----------------|
| **Plan** | AI creates a formal plan with goals, steps, and completion criteria | Tim Loop `--plan` mode, plan-ops `import` |
| **Review** | Human reviews plan for feasibility and approves | plan-ops `promote`, `ai-ready` approval gates |
| **Code** | AI implements exactly what the plan specifies | Tim Loop `--implement`, real-time code quality hooks |
| **Verify** | AI verifies 100% of objectives are met, loops if not | Tim Loop verification phase (no exit until complete) |
| **Test** | Tests must exist and pass with 90% coverage | Pre-commit hooks, CI pipeline (Gate 2) |
| **Deploy** | Human approves production deployment | Deploy gates, canary rollout (Gate 3) |

### Recommended Workflow

The TIM standards work best with a **3-terminal setup** that keeps human oversight smooth while AI executes:

**Setup (iTerm2 or any terminal with tabs):**

| Terminal | Purpose | What Runs Here |
|----------|---------|----------------|
| **Tab 1** | Claude Code | `/tim-loop` commands |
| **Tab 2** | plan-ops | `plan-ops` commands to manage lifecycle |
| **Tab 3** | Approvals | `plan-ops approve-execute` and other approval commands |

**The workflow:**

1. **Tab 2**: Run `plan-ops` commands to see status, import plans, or get next steps
2. **Tab 2**: plan-ops outputs the exact command to paste into Claude—just copy it
3. **Tab 1**: Run `/clear` then paste the command from plan-ops
4. **Tab 1**: Claude executes the task via Tim Loop
5. **Tab 3**: When approval is needed, plan-ops tells you—run the approval command here
6. **Repeat**: plan-ops always shows the next step and gives you the command to paste

**Why this works:**
- **plan-ops keeps you on track**—it always knows where you are in the lifecycle
- **Commands are pre-formatted**—copy from Tab 2, paste into Tab 1
- **`/clear` before every command**—starts Claude with fresh context
- **Approvals in Tab 3**—never interrupts your Claude session
- **Human stays in control**—you decide when to proceed, AI executes

**Example session:**

```bash
# Tab 2: Check status and get next command
$ plan-ops status
Active plan: 2025-01-26-auth-system.md (Phase 2 of 3)
Next step: Run in Claude Code:
  /tim-loop --implement plans/active/2025-01-26-auth-system.md

# Tab 1: Clear and paste
/clear
/tim-loop --implement plans/active/2025-01-26-auth-system.md

# Tab 3: (when plan-ops says approval needed)
$ plan-ops approve-execute abc123 --approver "Tim"
```

---

## Just Want Tim Loop?

You don't need to adopt the full TIM standards to use the Tim Loop plugin. Install it in 2 commands:

### Install

In Claude Code:
```
/plugin marketplace add schreyack/design_standards
/plugin install tim-loop@tim-design-standards
```

Restart Claude Code. That's it.

### Use

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
export PATH="$HOME/.claude/plugins/marketplaces/tim-design-standards/bin:$PATH"

# Reload shell
source ~/.zshrc
```

Then run `plan-ops help` from anywhere.

### Learn More

- [Full plugin documentation](plugins/tim-loop/README.md) - all options, modes, troubleshooting

---

## What Do You Want to Do?

| Goal | Where to Look |
|------|---------------|
| **Install Tim Loop plugin** | [Just Want Tim Loop?](#just-want-tim-loop) (above) |
| **Understand Tim Loop in depth** | [plugins/tim-loop/README.md](plugins/tim-loop/README.md) |
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

1. Copy `CLAUDE.md` to your project root
2. Copy templates from `templates/python/` or `templates/node/`
3. Install shared library (see [libs/python/](libs/python/) or [libs/node/](libs/node/))
4. Copy `.tim-patterns.yaml` template and register your patterns
5. Run `pre-commit install`
6. Configure CI pipeline using templates from `templates/ci/`

## Existing Project Migration

To migrate an existing project to TIM compliance:

1. Run `tools/tim-compliance-check.sh` to assess current state
2. Follow [Legacy Onboarding Playbook](standards/operations/legacy-onboarding.md)
3. Start at enforcement Level 0 (audit only)
4. Use [Graduated Enforcement](standards/enforcement/graduated-enforcement.md) to progressively tighten
5. Migrate tests using [Test Migration Standard](standards/testing/test-migration.md)
6. Reach Level 4 (full enforcement) before production

---

## Four-Gate Enforcement Model

The TIM standards require four enforcement gates in all compliant projects:

```
┌─────────────────────────────────────────────────────────────┐
│  GATE 1: LOCAL (Pre-commit)                                 │
│  Type check → Lint → Format → Secrets scan                  │
│  BLOCKS: git commit                                         │
├─────────────────────────────────────────────────────────────┤
│  GATE 2: CI (Pull Request)                                  │
│  Gate 1 + Tests + Coverage (90%) + Security scan            │
│  BLOCKS: PR merge                                           │
├─────────────────────────────────────────────────────────────┤
│  GATE 3: DEPLOY (Pre-deployment)                            │
│  Integration + E2E + Canary (10%) + Human approval          │
│  BLOCKS: Production deploy                                  │
├─────────────────────────────────────────────────────────────┤
│  GATE 4: PATTERN COMPLIANCE                                 │
│  All patterns registered in .tim-patterns.yaml              │
│  CUSTOM patterns require human approval                     │
│  BLOCKS: Deployment if non-compliant                        │
└─────────────────────────────────────────────────────────────┘
```

See [standards/enforcement/gates.md](standards/enforcement/gates.md) for full details.

---

## Key Requirements

The TIM standards require:

| Requirement | Threshold | Enforcement |
|-------------|-----------|-------------|
| Type safety | 100% | Pre-commit + CI |
| Test coverage | 90% | CI blocks merge |
| Security vulns | 0 HIGH/CRITICAL | CI blocks merge |
| Secrets in code | 0 | Pre-commit blocks |
| File size | 400 lines max | CI + AI behavioral gates |
| Function size | 50 lines max | CI + AI behavioral gates |
| Complexity | 10 max | CI blocks merge |
| Shared lib usage | Required | Compliance check |
| Pattern compliance | 100% | Deploy blocks |

---

## Technology Stacks

The TIM standards support two technology stacks:

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

```
design_standards/
├── CLAUDE.md              # Copy to TIM-compliant projects
├── README.md              # This file
├── standards/             # All standards documentation
├── libs/                  # Shared libraries (required by TIM)
│   ├── python/            # tim-lib Python package
│   └── node/              # @tim/lib Node.js package
├── plugins/               # Claude Code plugins
│   └── tim-loop/          # Tim Loop plugin
├── examples/              # Reference implementations
│   ├── python/            # Python/FastAPI example
│   └── node/              # Node.js/Express example
├── templates/             # Ready-to-copy configs
└── tools/                 # Enforcement tools
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

### Operations
| Document | Summary |
|----------|---------|
| [plan-management.md](standards/operations/plan-management.md) | Plan lifecycle, approval workflow, Tim Loop |
| [ai-coordination.md](standards/operations/ai-coordination.md) | Multi-AI developer coordination |
| [legacy-onboarding.md](standards/operations/legacy-onboarding.md) | Migration playbook for existing projects |
| [afk-coding-patterns.md](standards/operations/afk-coding-patterns.md) | Extended autonomous development |

### Coding
| Document | Summary |
|----------|---------|
| [python.md](standards/coding/python.md) | mypy strict, ruff, FastAPI patterns |
| [typescript.md](standards/coding/typescript.md) | strict mode, ESLint, Prisma |
| [code-organization.md](standards/coding/code-organization.md) | File size limits, complexity (AI-critical) |
| [api-versioning.md](standards/coding/api-versioning.md) | URL path versioning, deprecation |

### Testing
| Document | Summary |
|----------|---------|
| [requirements.md](standards/testing/requirements.md) | 90% coverage, TDD workflow |
| [e2e-requirements.md](standards/testing/e2e-requirements.md) | True e2e testing, route discovery |
| [test-migration.md](standards/testing/test-migration.md) | Convert tests to TIM standards |

### Security
| Document | Summary |
|----------|---------|
| [owasp-checklist.md](standards/security/owasp-checklist.md) | OWASP Top 10 coverage |
| [secrets.md](standards/security/secrets.md) | Secrets management, rotation |
| [authentication.md](standards/security/authentication.md) | JWT, password hashing |

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

### Incident Response
| Document | Summary |
|----------|---------|
| [response.md](standards/incident/response.md) | Incident handling, post-mortems |

---

## Why Strict Enforcement Works for AI

The TIM standards are intentionally strict because AI agents respond differently to enforcement than humans:

| Human Developer | AI Developer |
|----------------|--------------|
| Frustrated by repeated failures | Unfazed by iteration |
| May disable "annoying" checks | Cannot bypass enforcement |
| Tires after many fix cycles | Unlimited patience |
| May cut corners under pressure | Follows rules consistently |

This is why the TIM standards enforce:
- **Type checking on every commit** - Catches AI hallucinations about types
- **Tests must pass before merge** - Catches plausible-sounding but broken logic
- **90% coverage minimum** - Forces comprehensive testing, not just happy paths
- **No bypass flags anywhere** - Removes temptation to skip verification
- **Real-time behavioral gates** - Catches violations as they happen

Strictness is the feature, not a bug.

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
