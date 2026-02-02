"""Plan normalization via Claude.

Uses Claude CLI to restructure improperly formatted plans into the standard format.
"""

import difflib
from pathlib import Path

from pyplan_ops.executor import ClaudeExecutor
from pyplan_ops.validator import validate_plan_structure

NORMALIZE_PROMPT = '''You are a plan normalizer. Convert the following plan content into the standard pyplan-ops format.

The standard format requires:

1. A title as H1 header: # Plan Title

2. A Status section with this exact table format:
```
## Status

| Field | Value |
|-------|-------|
| Stage | draft |
| Created | YYYY-MM-DD |
| Last Updated | YYYY-MM-DD |
| Author | [author name] |
| Approver | - |
| Plan Review | required |
| Review Date | - |
| Execution Approved | no |
| Execution Approved By | - |
| Execution Started | - |

### Progress Log

| Timestamp | Stage | Event |
|-----------|-------|-------|
| YYYY-MM-DD | draft | Plan created |
```

3. A Permissions block (before phases):
```
## Permissions

<!-- PLAN_PERMISSIONS
preset: python-dev
-->
```

4. Phases with this format:
```
## Phase N: Phase Name

<!-- PHASE_META
depends: none  (or: Phase 1, Phase 2)
-->

### Task N.M: Task Name

[Task content...]

**Verify**:
- [ ] First verification criterion
- [ ] Second verification criterion
```

IMPORTANT:
- Preserve all original content and meaning
- Every task MUST have a **Verify** section with checkboxes
- If the original has no verification criteria, infer reasonable ones
- Number phases sequentially starting at 1
- Number tasks as Phase.Task (e.g., 1.1, 1.2, 2.1)

Here is the plan to normalize:

---
{content}
---

Output ONLY the normalized markdown, nothing else.
'''


def generate_diff(original: str, normalized: str) -> str:
    """Generate a unified diff between original and normalized content."""
    original_lines = original.splitlines(keepends=True)
    normalized_lines = normalized.splitlines(keepends=True)

    diff = difflib.unified_diff(
        original_lines,
        normalized_lines,
        fromfile="original",
        tofile="normalized",
        lineterm="",
    )

    return "".join(diff)


def _check_normalization_needed(content: str) -> str | None:
    """Check if normalization is needed and return content if valid, None otherwise."""
    validation = validate_plan_structure(content)
    if validation.is_valid:
        return content
    if validation.severity == "unfixable":
        raise ValueError(f"Plan has unfixable issues: {[i.message for i in validation.issues]}")
    return None


async def _call_claude_for_normalization(content: str, executor: ClaudeExecutor) -> str:
    """Call Claude to normalize the plan content."""
    prompt = NORMALIZE_PROMPT.format(content=content)
    result = await executor.execute(
        prompt=prompt,
        allowed_tools=[],
        output_format="text",
    )
    if not result.success:
        raise RuntimeError(f"Normalization failed: {result.error}")
    return result.output.strip()


def _prompt_user_approval(original: str, normalized: str) -> bool:
    """Show diff and prompt user for approval."""
    diff = generate_diff(original, normalized)
    print("\n=== Proposed Changes ===\n")
    print(diff)
    print("\n========================\n")
    response = input("Apply these changes? [y/N]: ").strip().lower()
    return response == "y"


async def normalize_plan(
    path: Path,
    executor: ClaudeExecutor | None = None,
    auto_approve: bool = False,
) -> str:
    """Normalize a plan file using Claude."""
    if executor is None:
        executor = ClaudeExecutor()

    content = path.read_text()

    valid_content = _check_normalization_needed(content)
    if valid_content is not None:
        return valid_content

    normalized = await _call_claude_for_normalization(content, executor)

    if not auto_approve and not _prompt_user_approval(content, normalized):
        raise RuntimeError("Normalization cancelled by user")

    return normalized


async def normalize_and_save(
    path: Path,
    output_path: Path | None = None,
    executor: ClaudeExecutor | None = None,
    auto_approve: bool = False,
) -> Path:
    """Normalize a plan file and save the result.

    Args:
        path: Path to the plan file to normalize
        output_path: Where to save (defaults to overwriting original)
        executor: ClaudeExecutor instance
        auto_approve: If True, skip user approval prompt

    Returns:
        Path to the saved normalized file
    """
    normalized = await normalize_plan(path, executor, auto_approve)

    save_path = output_path or path
    save_path.write_text(normalized)

    return save_path
