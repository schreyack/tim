# TIM AI Behavioral Gates

Real-time enforcement hooks for Claude Code that ensure code quality and AI accountability.

## What's Included

| Hook | Type | Purpose |
|------|------|---------|
| `code-quality-validator.py` | PostToolUse | Enforces 400-line file limit, 50-line function limit |
| `excuse-detector.py` | Stop | Catches deflection patterns, blocks completion until fixed |
| `install-hooks.sh` | Script | One-command installer for any project |
| `settings.json.template` | Config | Claude Code configuration template |

## Installation Options

### Option 1: Install tim-loop Plugin (Recommended)

If you install the **tim-loop** plugin, you get these hooks automatically:

```bash
# In Claude Code
/plugin install tim-loop@tim-design-standards
```

The plugin includes:
- All AI behavioral gates (code quality + excuse detection)
- Four-phase workflow (Plan → Review → Implement → Verify)
- Prompt preservation across context compaction
- 100% completion verification

### Option 2: Standalone Installation

For projects that only want the enforcement hooks without tim-loop:

```bash
# From design_standards repo
./templates/hooks/install-hooks.sh /path/to/project
```

This copies the hooks and configures `.claude/settings.json`.

## How It Works

### Code Quality Validator

Runs after every `Edit` or `Write` operation:

```
File modified → Check line count → >400 lines? → BLOCK
                                 → Check functions → >50 lines? → BLOCK
                                 → All OK → Continue
```

When blocked, Claude receives:
```
CODE QUALITY VIOLATION in page.tsx:
- File has 542 lines (max: 400)

You must refactor before continuing.
```

### Excuse Pattern Detector

Runs when Claude tries to complete:

```
Claude tries to stop → Scan transcript → Excuses found? → BLOCK
                                       → No excuses → Allow completion
```

Detected patterns include:
- "was already broken"
- "not part of my changes"
- "I only added X lines"
- "out of scope"
- "pre-existing issue"

When blocked, Claude receives:
```
DEFLECTION DETECTED - You attempted to avoid responsibility.

TIM RULE: If you touched a file with violations, you MUST fix them.
No exceptions. No excuses.
```

## Customization

### Adjusting Limits

Edit `code-quality-validator.py`:

```python
class Limits(NamedTuple):
    max_file_lines: int = 400      # Change to your limit
    max_function_lines: int = 50   # Change to your limit
    max_complexity: int = 10       # Change to your limit
```

### Adding Excuse Patterns

Edit `excuse-detector.py`:

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

## Philosophy

AI assistants can exhibit problematic behaviors:
- Making excuses instead of fixing issues
- Claiming problems are "out of scope"
- Deflecting responsibility to pre-existing code

**TIM Rule**: If you touched a file with violations, you must fix them. No exceptions.

These gates enforce accountability through deterministic hooks that AI cannot bypass. Unlike prompt instructions that AI might ignore, hooks run at the application level.

## References

- [AI Behavioral Gates Standard](../standards/enforcement/ai-behavioral-gates.md)
- [Tim Loop Plugin](../plugins/tim-loop/README.md)
- [Claude Code Hooks Documentation](https://code.claude.com/docs/en/hooks)
