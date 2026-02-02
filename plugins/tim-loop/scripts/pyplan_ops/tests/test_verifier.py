"""Tests for verification logic."""


from pyplan_ops.models import Task
from pyplan_ops.verifier import (
    _build_remediate_prompt,
    _build_verify_prompt,
    _parse_verify_output,
)


class TestBuildVerifyPrompt:
    def test_includes_task_name(self) -> None:
        task = Task(id="1.1", name="Test Task", content="Do stuff", verify_criteria=["Check A"])
        prompt = _build_verify_prompt(task)

        assert "Test Task" in prompt

    def test_includes_all_criteria(self) -> None:
        task = Task(
            id="1.1",
            name="Test",
            content="",
            verify_criteria=["First check", "Second check", "Third check"],
        )
        prompt = _build_verify_prompt(task)

        assert "First check" in prompt
        assert "Second check" in prompt
        assert "Third check" in prompt


class TestBuildRemediatePrompt:
    def test_includes_failed_criteria(self) -> None:
        task = Task(id="1.1", name="Fix Me", content="", verify_criteria=[])
        failed = ["Failed A", "Failed B"]
        prompt = _build_remediate_prompt(task, failed, "Some evidence")

        assert "Failed A" in prompt
        assert "Failed B" in prompt
        assert "Some evidence" in prompt


class TestParseVerifyOutput:
    def test_parses_passing_criteria(self) -> None:
        output = """
CRITERION: File exists
STATUS: PASS
EVIDENCE: Found the file

CRITERION: Contains text
STATUS: PASS
EVIDENCE: Text is present
"""
        criteria = ["File exists", "Contains text"]
        results, evidence = _parse_verify_output(output, criteria)

        assert results["File exists"] is True
        assert results["Contains text"] is True

    def test_parses_failing_criteria(self) -> None:
        output = """
CRITERION: File exists
STATUS: FAIL
EVIDENCE: File not found
"""
        criteria = ["File exists"]
        results, evidence = _parse_verify_output(output, criteria)

        assert results["File exists"] is False

    def test_defaults_unmatched_to_false(self) -> None:
        output = "No structured output here"
        criteria = ["Some criterion"]
        results, _ = _parse_verify_output(output, criteria)

        assert results["Some criterion"] is False

    def test_collects_evidence(self) -> None:
        output = """
CRITERION: Test
STATUS: PASS
EVIDENCE: First piece of evidence
EVIDENCE: Second piece
"""
        criteria = ["Test"]
        _, evidence = _parse_verify_output(output, criteria)

        assert "First piece" in evidence
        assert "Second piece" in evidence
