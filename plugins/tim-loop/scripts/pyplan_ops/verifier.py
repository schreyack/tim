"""Verification loop logic.

Handles task verification with retry and remediation support.
"""

from pyplan_ops.executor import ClaudeExecutor
from pyplan_ops.models import Task, VerifyResult

__all__ = ["VerifyResult", "verify_task"]

VERIFY_TASK_PROMPT = '''Verify that the following task has been completed correctly.

Task: {task_name}

Verification Criteria:
{criteria}

For each criterion, check if it has been satisfied. Return your assessment in this format:

CRITERION: [criterion text]
STATUS: PASS or FAIL
EVIDENCE: [what you found]

After checking all criteria, provide a final summary:
OVERALL: PASS or FAIL
'''

REMEDIATE_PROMPT = '''The following verification failed. Please fix the issues.

Task: {task_name}

Failed Criteria:
{failed_criteria}

Evidence of failures:
{evidence}

Please make the necessary changes to satisfy all criteria.
'''

# Verification uses restricted tools - read-only plus test runners
VERIFICATION_TOOLS = [
    "Read",
    "Glob",
    "Grep",
    "Bash",  # Needed for running tests
]


def _build_verify_prompt(task: Task) -> str:
    """Build the verification prompt for a task."""
    criteria_text = "\n".join(f"- {c}" for c in task.verify_criteria)
    return VERIFY_TASK_PROMPT.format(
        task_name=task.name,
        criteria=criteria_text,
    )


def _build_remediate_prompt(task: Task, failed: list[str], evidence: str) -> str:
    """Build the remediation prompt for failed criteria."""
    failed_text = "\n".join(f"- {c}" for c in failed)
    return REMEDIATE_PROMPT.format(
        task_name=task.name,
        failed_criteria=failed_text,
        evidence=evidence,
    )


def _parse_verify_output(output: str, criteria: list[str]) -> tuple[dict[str, bool], str]:
    """Parse verification output to extract results per criterion."""
    results: dict[str, bool] = {}
    evidence_parts: list[str] = []

    lines = output.split("\n")
    current_criterion = None

    for line in lines:
        line = line.strip()

        if line.startswith("CRITERION:"):
            current_criterion = line[len("CRITERION:") :].strip()

        elif line.startswith("STATUS:"):
            status = line[len("STATUS:") :].strip().upper()
            if current_criterion:
                # Match to original criteria
                for c in criteria:
                    if c.lower() in current_criterion.lower() or current_criterion.lower() in c.lower():
                        results[c] = status == "PASS"
                        break

        elif line.startswith("EVIDENCE:"):
            evidence_parts.append(line[len("EVIDENCE:") :].strip())

    # Default any unmatched criteria to False
    for c in criteria:
        if c not in results:
            results[c] = False

    return results, "\n".join(evidence_parts)


async def _run_single_verification(
    task: Task, executor: ClaudeExecutor, attempt: int
) -> tuple[VerifyResult | None, dict[str, bool], list[str], str]:
    """Run a single verification attempt. Returns (final_result, criteria_results, failed, evidence)."""
    prompt = _build_verify_prompt(task)
    result = await executor.execute(prompt=prompt, allowed_tools=VERIFICATION_TOOLS, output_format="text")

    if not result.success:
        return VerifyResult(task_id=task.id, passed=False, error=result.error, attempts=attempt), {}, [], ""

    criteria_results, evidence = _parse_verify_output(result.output, task.verify_criteria)
    failed = [c for c, passed in criteria_results.items() if not passed]

    if not failed:
        return VerifyResult(
            task_id=task.id, passed=True, criteria_results=criteria_results, evidence=evidence, attempts=attempt
        ), criteria_results, failed, evidence

    return None, criteria_results, failed, evidence


async def verify_task(
    task: Task,
    executor: ClaudeExecutor,
    max_attempts: int = 10,
    implementation_tools: list[str] | None = None,
) -> VerifyResult:
    """Verify a task with retry and remediation loop."""
    if implementation_tools is None:
        implementation_tools = ["Read", "Write", "Edit", "Bash", "Glob", "Grep"]

    criteria_results: dict[str, bool] = {}
    evidence = ""

    for attempt in range(1, max_attempts + 1):
        final_result, criteria_results, failed, evidence = await _run_single_verification(task, executor, attempt)
        if final_result is not None:
            return final_result

        if attempt < max_attempts:
            remediate_prompt = _build_remediate_prompt(task, failed, evidence)
            await executor.execute(prompt=remediate_prompt, allowed_tools=implementation_tools, output_format="text")

    return VerifyResult(
        task_id=task.id,
        passed=False,
        criteria_results=criteria_results,
        evidence=evidence,
        attempts=max_attempts,
        error=f"Failed after {max_attempts} attempts",
    )
