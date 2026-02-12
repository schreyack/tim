# AI Developer Coordination Standard

This document defines how multiple AI developers coordinate when working on the same codebase.

## Overview

TIM uses 2-3 concurrent AI developers per project. Without coordination, this creates:

- Merge conflicts
- Duplicated work
- Inconsistent implementations
- Blocked workflows

This standard defines the coordination mechanisms.

## Git Worktree Strategy

Each AI developer works in a separate git worktree with dedicated branches.

### Directory Structure

```text
/project/
├── main/                    # Main worktree (human review, merges)
├── ai-1/                    # AI Developer 1 worktree
├── ai-2/                    # AI Developer 2 worktree
└── ai-3/                    # AI Developer 3 worktree (if needed)
```

### Setup

```bash
# Clone main repository
git clone <repo> main
cd main

# Create worktrees for AI developers
git worktree add ../ai-1 -b ai-1/current-task
git worktree add ../ai-2 -b ai-2/current-task
git worktree add ../ai-3 -b ai-3/current-task
```

### Branch Naming Convention

```text
ai-{developer-id}/{task-type}/{description}
```

Examples:

- `ai-1/feature/add-user-authentication`
- `ai-2/fix/resolve-database-timeout`
- `ai-3/refactor/migrate-tests-to-standard`

## Task Assignment

### Ownership Rules

1. **One owner per file** - At any time, only one AI developer modifies a specific file
2. **Ownership is explicit** - Tasks must specify which files/modules are owned
3. **Handoff is explicit** - Ownership transfers only through completed PR

### Task Definition Template

```yaml
# .ai-tasks/ai-1-current.yaml
task_id: "TASK-123"
ai_developer: "ai-1"
description: "Migrate auth tests to TIM standard"
status: "in_progress"

ownership:
  exclusive:
    - "tests/unit/test_auth*.py"
    - "src/services/auth.py"
  shared_read:
    - "src/models/user.py"
    - "src/config.py"

blocked_by: []
blocks: ["TASK-125"]

started_at: "2025-01-15T10:00:00Z"
estimated_completion: "2025-01-15T14:00:00Z"
```

### Conflict Prevention

Before starting work, AI developers must:

1. **Pull latest main** - Ensure branch is up-to-date
2. **Check task files** - Verify no other AI owns target files
3. **Claim ownership** - Update task file before modifying files
4. **Release ownership** - Clear task file after PR merged

## Communication Protocol

### State Files

Each AI developer maintains a state file for coordination:

```yaml
# .ai-state/ai-1.yaml
last_updated: "2025-01-15T10:30:00Z"
status: "working"  # working | blocked | waiting_review | idle

current_task: "TASK-123"
current_branch: "ai-1/refactor/migrate-tests"

files_modified:
  - "tests/unit/test_auth_service.py"
  - "tests/unit/test_user_service.py"

blocked_on:
  type: null  # merge_conflict | dependency | review | human_input
  details: null

next_planned_action: "Complete test migration, create PR"
```

### Blocking Conditions

When an AI developer is blocked:

1. Update state file with block type and details
2. Switch to a different non-conflicting task if available
3. If no tasks available, set status to `blocked`

### Resolution Priority

1. **Merge conflicts** - Human resolves, or AI with ownership resolves
2. **Dependencies** - Blocking task must complete first
3. **Review** - Human reviews PR within SLA
4. **Human input** - Human provides required decision

## Merge Strategy

### PR Flow

```text
ai-1/feature/xyz → main (via PR)
                 ↓
        Human review required
                 ↓
        AI-2 and AI-3 rebase after merge
```

### Rebase Protocol

After any merge to main:

1. All AI developers pause current work
2. Fetch and rebase onto latest main
3. Resolve any conflicts (or flag for human)
4. Resume work

### Automated Checks

Before AI creates PR:

1. Rebase onto latest main
2. Run all gate checks locally
3. Verify no file conflicts with other in-progress work

## File Locking (Optional)

For critical files, explicit locking prevents conflicts:

```yaml
# .locks/current.yaml
locks:
  - file: "src/config.py"
    owner: "ai-1"
    task: "TASK-123"
    acquired: "2025-01-15T10:00:00Z"
    expires: "2025-01-15T12:00:00Z"  # 2 hour max

  - file: "alembic/versions/*.py"
    owner: "ai-2"
    task: "TASK-124"
    acquired: "2025-01-15T09:00:00Z"
    expires: "2025-01-15T11:00:00Z"
```

### Lock Rules

- Locks expire after 2 hours (prevents stale locks)
- AI must check lock file before modifying locked files
- Human can break locks if AI is unresponsive

## Review Queue Management

### PR Priority

1. **Blocking PRs** - Other AIs waiting on this merge
2. **Security fixes** - Immediate priority
3. **Bug fixes** - Same-day review
4. **Features** - Standard queue
5. **Refactoring** - When capacity available

### Review SLA

| Priority | Target Review Time |
|----------|-------------------|
| Blocking | 1 hour |
| Security | 2 hours |
| Bug fix | 4 hours |
| Feature | 24 hours |
| Refactor | 48 hours |

## Deadlock Prevention

### Detection

Deadlock occurs when:

- AI-1 is blocked on AI-2's task
- AI-2 is blocked on AI-1's task

### Prevention Rules

1. **No circular dependencies** - Task graph must be acyclic
2. **Timeout escalation** - Blocked > 2 hours → human escalation
3. **Priority override** - Human can reorder tasks to break deadlock

### Resolution

1. Human identifies circular dependency
2. Human breaks one dependency (accepts partial work)
3. Blocked AI continues
4. Other AI adapts to changed requirements

## Handoff Protocol

When one AI session ends and another begins:

### Session End

1. Commit all work (even if incomplete)
2. Update state file with current status
3. Document next steps in commit message or task file
4. Push branch

### Session Start

1. Read all AI state files
2. Identify available tasks (not owned by active AI)
3. Pull latest changes
4. Claim task ownership
5. Resume or start work

## Metrics

Track coordination effectiveness:

| Metric | Target |
|--------|--------|
| Merge conflict rate | < 5% of PRs |
| Average block duration | < 1 hour |
| Review SLA compliance | > 90% |
| Deadlock occurrences | 0 per week |

## See Also

- [AI Review Checklist](../enforcement/ai-review-checklist.md)
- [Gates](../enforcement/gates.md)
- [Incident Response](../incident/response.md)
