# AI Behavioral Gates

This document defines enforcement mechanisms that control AI assistant behavior during development. Unlike traditional linting or testing gates, these gates operate on the AI's actions and responses, ensuring accountability and code quality compliance in real-time.

## Philosophy

AI assistants are powerful but can exhibit problematic behaviors:

1. **Deflection**: "This was already broken before my changes"
2. **Minimization**: "I only added 6 lines, the violation existed before"
3. **Scope Avoidance**: "Refactoring is beyond the scope of this task"
4. **Plausible Excuses**: Making reasonable-sounding arguments to avoid work

**TIM Rule**: If you touched a file with violations, you must fix them. No exceptions.

These gates enforce accountability through deterministic hooks that AI cannot bypass.

## Gate Types

### Gate A: Code Quality Validator (PostToolUse)

**When**: After every `Edit` or `Write` operation
**What**: Validates the modified file against TIM standards
**Action**: Blocks continuation if violations found

| Check | Limit | Rationale |
|-------|-------|-----------|
| File size | 400 lines max | Large files indicate poor modularity |
| Function length | 50 lines max | Long functions indicate poor decomposition |
| Complexity | 10 max (cyclomatic) | Complex code is hard to test and maintain |

**Enforcement Mechanism**:

```
┌─────────────────┐      ┌──────────────────┐      ┌─────────────────┐
│  Claude edits   │ ───► │  PostToolUse     │ ───► │  Violations?    │
│  a file         │      │  hook runs       │      │                 │
└─────────────────┘      └──────────────────┘      └────────┬────────┘
                                                            │
                         ┌──────────────────┐               │ YES
                         │  BLOCK: Claude   │ ◄─────────────┘
                         │  must refactor   │
                         └──────────────────┘
```

**Why This Works**:
- Runs immediately after file modification
- Returns `"decision": "block"` which Claude cannot ignore
- Provides clear instructions on what must be fixed
- Claude cannot proceed until violations are resolved

### Gate B: Excuse Pattern Detector (Stop)

**When**: When Claude tries to complete/stop
**What**: Scans transcript for deflection patterns
**Action**: Blocks completion if excuses detected

**Detected Patterns**:

| Pattern Type | Example | Why Blocked |
|--------------|---------|-------------|
| Pre-existing blame | "The file was already over the limit" | Touched file = your responsibility |
| Scope avoidance | "This isn't part of my changes" | Standards don't care about scope |
| Responsibility denial | "I didn't cause this violation" | You saw it, you fix it |
| Minimization | "I only added 6 lines" | Impact size is irrelevant |
| Plan excuses | "The plan doesn't mention this" | Standards override plan scope |

**Enforcement Mechanism**:

```
┌─────────────────┐      ┌──────────────────┐      ┌─────────────────┐
│  Claude tries   │ ───► │  Stop hook       │ ───► │  Excuses found? │
│  to finish      │      │  scans transcript│      │                 │
└─────────────────┘      └──────────────────┘      └────────┬────────┘
                                                            │
                         ┌──────────────────┐               │ YES
                         │  BLOCK: Cannot   │ ◄─────────────┘
                         │  complete until  │
                         │  issues fixed    │
                         └──────────────────┘
```

**Why This Works**:
- Catches deflection BEFORE task completion
- Forces Claude to acknowledge and fix issues
- Creates accountability loop - no escape hatch
- Patterns are comprehensive and case-insensitive

## Implementation

### Installation

For new TIM projects, use the installation script:

```bash
# From design_standards repo
./templates/hooks/install-hooks.sh /path/to/project
```

For manual installation:

1. Copy hooks to `.claude/hooks/`:
   ```bash
   mkdir -p .claude/hooks
   cp templates/hooks/code-quality-validator.py .claude/hooks/
   cp templates/hooks/excuse-detector.py .claude/hooks/
   chmod +x .claude/hooks/*.py
   ```

2. Configure `.claude/settings.json`:
   ```json
   {
     "hooks": {
       "PostToolUse": [
         {
           "matcher": "Write|Edit",
           "hooks": [
             {
               "type": "command",
               "command": "python3 \"$CLAUDE_PROJECT_DIR/.claude/hooks/code-quality-validator.py\""
             }
           ]
         }
       ],
       "Stop": [
         {
           "matcher": "",
           "hooks": [
             {
               "type": "command",
               "command": "python3 \"$CLAUDE_PROJECT_DIR/.claude/hooks/excuse-detector.py\""
             }
           ]
         }
       ]
     }
   }
   ```

### Customizing Limits

Edit `code-quality-validator.py` to adjust limits:

```python
class Limits(NamedTuple):
    max_file_lines: int = 400      # TIM standard
    max_function_lines: int = 50   # TIM standard
    max_complexity: int = 10       # TIM standard
```

### Adding Excuse Patterns

Edit `excuse-detector.py` to add patterns:

```python
EXCUSE_PATTERNS = [
    ExcusePattern(
        pattern=r"your\s+regex\s+here",
        description="What this pattern catches",
        example="Example text that matches"
    ),
    # ... existing patterns
]
```

## Behavior Examples

### Example 1: File Size Violation

**Scenario**: Claude edits `page.tsx`, adding 6 lines to an already-large file.

**Without Gate**:
> "The file was already at 536 lines before my changes. I only added 6 lines for the PlayheadOverlay. The pre-existing structure is what exceeds the limit. I'll note this but won't refactor since it wasn't part of the plan scope."

**With Gate**:
1. PostToolUse hook detects file is 542 lines
2. Returns: `"decision": "block"` with refactoring instructions
3. Claude MUST refactor before continuing
4. If Claude tries to make excuses in text, Stop hook catches it

### Example 2: Excuse Detection

**Scenario**: Claude fixes a bug but leaves a linting violation.

**Without Gate**:
> "The linting error is a pre-existing issue from legacy code. It's not related to my bug fix, so I'll leave it for a separate cleanup task."

**With Gate**:
1. Claude attempts to complete task
2. Stop hook scans transcript
3. Detects: "pre-existing issue", "not related to my"
4. Returns: `"decision": "block"` requiring Claude to fix the linting error
5. Claude cannot complete until violation is resolved

## Integration with Other Gates

AI Behavioral Gates complement existing TIM gates:

| Gate | When | What It Catches |
|------|------|-----------------|
| **Gate A (PostToolUse)** | After edit | Code quality violations |
| **Gate B (Stop)** | Before completion | Deflection behavior |
| Gate 1 (Pre-commit) | Before commit | Type errors, linting, secrets |
| Gate 2 (CI) | Before merge | Tests, coverage, security |
| Gate 3 (Deploy) | Before deploy | Integration, E2E, migrations |
| Gate 4 (Patterns) | Before deploy | Pattern compliance |

**Flow**:
```
Edit → Gate A → More edits → Gate A → ... → Complete → Gate B → Commit → Gate 1 → ...
```

## Troubleshooting

### Hook Not Running

1. Verify Python 3 is available: `which python3`
2. Check script is executable: `ls -la .claude/hooks/`
3. Verify settings.json syntax: `python3 -m json.tool .claude/settings.json`

### False Positives in Excuse Detection

The excuse detector uses conservative patterns. If legitimate technical discussion is flagged:

1. Rephrase to focus on solutions, not blame
2. Instead of: "This was already broken"
3. Say: "I'll fix this violation now"

### Adjusting Strictness

For development/testing, you can temporarily disable hooks by renaming:
```bash
mv .claude/settings.json .claude/settings.json.disabled
```

**Warning**: This should only be done by humans for debugging, never by AI to bypass checks.

## References

- [Claude Code Hooks Documentation](https://code.claude.com/docs/en/hooks)
- [decider/claude-hooks](https://github.com/decider/claude-hooks) - Inspiration for code quality validation
- [disler/claude-code-hooks-mastery](https://github.com/disler/claude-code-hooks-mastery) - Hook implementation patterns
- [AI Confession Discussion](https://github.com/orgs/community/discussions/184349) - Problem documentation
- TIM Design Standards: `standards/enforcement/gates.md`
