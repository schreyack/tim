"""Plan structure validation.

Checks plan files for required elements and structural correctness.
"""

import re

from pyplan_ops.models import ValidationIssue, ValidationResult


def _check_empty_content(content: str) -> list[ValidationIssue]:
    """Check for empty or whitespace-only content."""
    if not content or not content.strip():
        return [ValidationIssue(severity="error", message="Plan file is empty")]
    return []


def _check_title(content: str) -> list[ValidationIssue]:
    """Check for H1 title."""
    if not re.search(r"^#\s+.+$", content, re.MULTILINE):
        return [ValidationIssue(severity="warning", message="Missing H1 title")]
    return []


def _check_status_header(content: str) -> list[ValidationIssue]:
    """Check for status table."""
    if "## Status" not in content:
        return [ValidationIssue(severity="warning", message="Missing Status section")]

    required_fields = ["Stage", "Created", "Author"]
    issues = []
    for field in required_fields:
        if not re.search(rf"\|\s*{field}\s*\|", content, re.IGNORECASE):
            issues.append(
                ValidationIssue(severity="warning", message=f"Status table missing {field} field")
            )
    return issues


def _check_phases(content: str) -> list[ValidationIssue]:
    """Check for phase structure."""
    phase_matches = re.findall(r"^##\s+Phase\s+\d+:", content, re.MULTILINE)
    if not phase_matches:
        return [ValidationIssue(severity="warning", message="No phases found (## Phase N: format)")]
    return []


def _check_tasks(content: str) -> list[ValidationIssue]:
    """Check for task structure."""
    task_matches = re.findall(r"^###\s+Task\s+\d+\.\d+:", content, re.MULTILINE)
    if not task_matches:
        return [ValidationIssue(severity="warning", message="No tasks found (### Task N.M: format)")]
    return []


def _check_verify_blocks(content: str) -> list[ValidationIssue]:
    """Check that tasks have verify blocks."""
    issues = []
    task_pattern = r"###\s+Task\s+(\d+\.\d+):"
    verify_pattern = r"\*\*Verify\*\*:?"

    task_matches = list(re.finditer(task_pattern, content))

    for i, match in enumerate(task_matches):
        task_id = match.group(1)
        start = match.end()
        end = task_matches[i + 1].start() if i + 1 < len(task_matches) else len(content)
        task_content = content[start:end]

        if not re.search(verify_pattern, task_content):
            issues.append(
                ValidationIssue(
                    severity="warning",
                    message=f"Task {task_id} missing **Verify** block",
                )
            )

    return issues


def validate_plan_structure(content: str) -> ValidationResult:
    """Validate plan structure and return issues.

    Returns:
        ValidationResult with is_valid, severity, and issues list
        - severity "ok": No issues
        - severity "fixable": Missing elements that can be auto-generated
        - severity "unfixable": Fundamental problems like empty file
    """
    all_issues: list[ValidationIssue] = []

    # Check for unfixable issues first
    empty_issues = _check_empty_content(content)
    if empty_issues:
        return ValidationResult(is_valid=False, severity="unfixable", issues=empty_issues)

    # Check for fixable issues
    all_issues.extend(_check_title(content))
    all_issues.extend(_check_status_header(content))
    all_issues.extend(_check_phases(content))
    all_issues.extend(_check_tasks(content))
    all_issues.extend(_check_verify_blocks(content))

    if not all_issues:
        return ValidationResult(is_valid=True, severity="ok", issues=[])

    return ValidationResult(is_valid=False, severity="fixable", issues=all_issues)
