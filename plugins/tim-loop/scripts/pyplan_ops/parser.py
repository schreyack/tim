"""Markdown plan parser.

Extracts structured data from properly-formatted plan files.
"""

import re
from pathlib import Path

from pyplan_ops.models import (
    Phase,
    Plan,
    PlanPermissions,
    PlanStatus,
    Task,
)


def parse_status_table(content: str) -> PlanStatus:
    """Extract status fields from the status table."""
    status = PlanStatus()

    # Match status table rows
    table_pattern = r"\|\s*([^|]+)\s*\|\s*([^|]+)\s*\|"
    matches = re.findall(table_pattern, content)

    field_mapping = {
        "stage": "stage",
        "created": "created",
        "last updated": "last_updated",
        "author": "author",
        "approver": "approver",
        "plan review": "plan_review",
        "review date": "review_date",
        "execution approved": "execution_approved",
        "execution approved by": "execution_approved_by",
        "execution started": "execution_started",
    }

    for field, value in matches:
        field_lower = field.strip().lower()
        if field_lower in field_mapping:
            setattr(status, field_mapping[field_lower], value.strip())

    return status


def parse_permissions(content: str) -> PlanPermissions:
    """Extract permissions from PLAN_PERMISSIONS comment."""
    permissions = PlanPermissions()

    # Match PLAN_PERMISSIONS block
    perm_pattern = r"<!--\s*PLAN_PERMISSIONS\s*(.*?)-->"
    match = re.search(perm_pattern, content, re.DOTALL)

    if match:
        perm_content = match.group(1)

        # Extract preset
        preset_match = re.search(r"preset:\s*(\S+)", perm_content)
        if preset_match:
            permissions.preset = preset_match.group(1)

        # Extract additional tools if specified
        tools_match = re.search(r"tools:\s*\[(.*?)\]", perm_content)
        if tools_match:
            tools = [t.strip().strip('"\'') for t in tools_match.group(1).split(",")]
            permissions.global_tools = [t for t in tools if t]

    return permissions


def parse_phase_meta(content: str, phase_start: int, next_phase_start: int | None) -> tuple[list[int], list[str]]:
    """Extract phase metadata from PHASE_META comment."""
    depends: list[int] = []
    tools: list[str] = []

    # Get phase content
    phase_content = content[phase_start:next_phase_start] if next_phase_start else content[phase_start:]

    # Match PHASE_META block
    meta_pattern = r"<!--\s*PHASE_META\s*(.*?)-->"
    match = re.search(meta_pattern, phase_content, re.DOTALL)

    if match:
        meta_content = match.group(1)

        # Extract dependencies
        depends_match = re.search(r"depends:\s*(.+?)(?:\n|$)", meta_content)
        if depends_match:
            depends_str = depends_match.group(1).strip()
            if depends_str.lower() != "none":
                # Parse "Phase 1" or "Phase 1, Phase 2" or just "1, 2"
                phase_refs = re.findall(r"(?:Phase\s+)?(\d+)", depends_str)
                depends = [int(p) for p in phase_refs]

        # Extract additional tools
        tools_match = re.search(r"tools:\s*\[(.*?)\]", meta_content)
        if tools_match:
            tools = [t.strip().strip('"\'') for t in tools_match.group(1).split(",")]
            tools = [t for t in tools if t]

    return depends, tools


def parse_verify_criteria(task_content: str) -> list[str]:
    """Extract verification criteria from task content."""
    criteria: list[str] = []

    # Look for **Verify**: or **Verify** block
    verify_pattern = r"\*\*Verify\*\*:?\s*(.*?)(?=\n###|\n##|\n---|\Z)"
    match = re.search(verify_pattern, task_content, re.DOTALL)

    if match:
        verify_block = match.group(1)
        # Extract checkbox items
        checkbox_pattern = r"^\s*-\s*\[[ x]\]\s*(.+)$"
        for line in verify_block.split("\n"):
            checkbox_match = re.match(checkbox_pattern, line)
            if checkbox_match:
                criteria.append(checkbox_match.group(1).strip())

    return criteria


def parse_tasks(phase_content: str, phase_id: int) -> list[Task]:
    """Parse tasks from phase content."""
    tasks: list[Task] = []

    # Find all task headers
    task_pattern = r"###\s+Task\s+(\d+\.\d+):\s*(.+?)(?=\n)"
    task_matches = list(re.finditer(task_pattern, phase_content))

    for i, match in enumerate(task_matches):
        task_id = match.group(1)
        task_name = match.group(2).strip()

        # Get task content (from this header to next task or end of phase)
        start = match.end()
        end = task_matches[i + 1].start() if i + 1 < len(task_matches) else len(phase_content)
        task_content = phase_content[start:end].strip()

        # Extract verification criteria
        verify_criteria = parse_verify_criteria(task_content)

        tasks.append(
            Task(
                id=task_id,
                name=task_name,
                content=task_content,
                verify_criteria=verify_criteria,
            )
        )

    return tasks


def parse_phases(content: str) -> list[Phase]:
    """Parse all phases from plan content."""
    phases: list[Phase] = []

    # Find all phase headers
    phase_pattern = r"##\s+Phase\s+(\d+):\s*(.+?)(?=\n)"
    phase_matches = list(re.finditer(phase_pattern, content))

    for i, match in enumerate(phase_matches):
        phase_id = int(match.group(1))
        phase_name = match.group(2).strip()

        # Get phase content boundaries
        start = match.start()
        end = phase_matches[i + 1].start() if i + 1 < len(phase_matches) else None

        # Get phase content for task parsing
        phase_content = content[match.end() : end] if end else content[match.end() :]

        # Parse phase metadata
        depends, additional_tools = parse_phase_meta(content, start, end)

        # Parse tasks
        tasks = parse_tasks(phase_content, phase_id)

        phases.append(
            Phase(
                id=phase_id,
                name=phase_name,
                tasks=tasks,
                depends_on=depends,
                additional_tools=additional_tools,
            )
        )

    return phases


def parse_title(content: str) -> str:
    """Extract plan title from first H1 header."""
    title_pattern = r"^#\s+(.+?)$"
    match = re.search(title_pattern, content, re.MULTILINE)
    return match.group(1).strip() if match else "Untitled Plan"


def parse_plan(path: Path) -> Plan:
    """Parse a plan file into a Plan object.

    Args:
        path: Path to the markdown plan file

    Returns:
        Parsed Plan object with all phases, tasks, and metadata
    """
    content = path.read_text()

    return Plan(
        path=path,
        title=parse_title(content),
        status=parse_status_table(content),
        permissions=parse_permissions(content),
        phases=parse_phases(content),
    )
