#!/usr/bin/env python3
"""Tests for is_agent_coordination_turn detection."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

from transcript_utils import is_agent_coordination_turn


def _assistant_entry(content: list) -> dict:
    """Build an assistant transcript entry."""
    return {"message": {"role": "assistant", "content": content}}


def _user_entry(text: str = "hello") -> dict:
    """Build a user transcript entry."""
    return {"message": {"role": "user", "content": text}}


def _text_block(text: str) -> dict:
    return {"type": "text", "text": text}


def _tool_block(name: str, input_data: dict | None = None) -> dict:
    return {"type": "tool_use", "name": name, "input": input_data or {}}


class TestAgentCoordinationTurn:
    def test_empty_transcript_returns_false(self) -> None:
        assert is_agent_coordination_turn([]) is False

    def test_no_assistant_entries_returns_false(self) -> None:
        assert is_agent_coordination_turn([_user_entry()]) is False

    def test_task_output_with_short_text_is_coordination(self) -> None:
        transcript = [
            _assistant_entry([
                _text_block("Waiting for agents to complete."),
                _tool_block("TaskOutput", {"task_id": "abc"}),
            ])
        ]
        assert is_agent_coordination_turn(transcript) is True

    def test_task_launch_with_short_text_is_coordination(self) -> None:
        transcript = [
            _assistant_entry([
                _text_block("Launching verification agents."),
                _tool_block("Task", {"prompt": "verify stuff"}),
                _tool_block("Task", {"prompt": "verify more"}),
            ])
        ]
        assert is_agent_coordination_turn(transcript) is True

    def test_task_stop_is_coordination(self) -> None:
        transcript = [
            _assistant_entry([
                _text_block("Stopping agent."),
                _tool_block("TaskStop", {"task_id": "abc"}),
            ])
        ]
        assert is_agent_coordination_turn(transcript) is True

    def test_mixed_agent_tools_is_coordination(self) -> None:
        transcript = [
            _assistant_entry([
                _text_block("Checking results."),
                _tool_block("TaskOutput", {"task_id": "a"}),
                _tool_block("TaskOutput", {"task_id": "b"}),
                _tool_block("Task", {"prompt": "more work"}),
            ])
        ]
        assert is_agent_coordination_turn(transcript) is True

    def test_non_agent_tools_is_real_work(self) -> None:
        transcript = [
            _assistant_entry([
                _text_block("Reading the plan file."),
                _tool_block("Read", {"file_path": "/tmp/plan.md"}),
            ])
        ]
        assert is_agent_coordination_turn(transcript) is False

    def test_mixed_agent_and_non_agent_tools_is_real_work(self) -> None:
        transcript = [
            _assistant_entry([
                _text_block("Got agent results, now reading files."),
                _tool_block("TaskOutput", {"task_id": "abc"}),
                _tool_block("Read", {"file_path": "/tmp/plan.md"}),
            ])
        ]
        assert is_agent_coordination_turn(transcript) is False

    def test_agent_tools_with_long_text_is_real_work(self) -> None:
        long_review = "I found several issues in the plan. " * 20  # ~720 chars
        transcript = [
            _assistant_entry([
                _text_block(long_review),
                _tool_block("TaskOutput", {"task_id": "abc"}),
            ])
        ]
        assert is_agent_coordination_turn(transcript) is False

    def test_no_tools_no_agent_coordination(self) -> None:
        transcript = [
            _assistant_entry([
                _text_block("Here is my review of the plan."),
            ])
        ]
        assert is_agent_coordination_turn(transcript) is False

    def test_uses_latest_assistant_entry(self) -> None:
        """Earlier entries with real work shouldn't matter; only latest counts."""
        transcript = [
            _assistant_entry([
                _text_block("Doing review work."),
                _tool_block("Read", {"file_path": "/tmp/plan.md"}),
            ]),
            _user_entry("continue"),
            _assistant_entry([
                _text_block("Checking agent."),
                _tool_block("TaskOutput", {"task_id": "abc"}),
            ]),
        ]
        assert is_agent_coordination_turn(transcript) is True

    def test_string_content_returns_false(self) -> None:
        """Content as string (not list) is not agent coordination."""
        transcript = [
            {"message": {"role": "assistant", "content": "just text"}}
        ]
        assert is_agent_coordination_turn(transcript) is False

    def test_skips_non_assistant_entries(self) -> None:
        """User entries before the last assistant entry are skipped."""
        transcript = [
            _assistant_entry([
                _text_block("Agent check."),
                _tool_block("TaskOutput", {"task_id": "x"}),
            ]),
            _user_entry("tool result here"),
        ]
        # Latest assistant entry has TaskOutput + short text
        assert is_agent_coordination_turn(transcript) is True

    def test_threshold_boundary_below(self) -> None:
        text_499 = "x" * 499
        transcript = [
            _assistant_entry([
                _text_block(text_499),
                _tool_block("TaskOutput", {"task_id": "a"}),
            ])
        ]
        assert is_agent_coordination_turn(transcript) is True

    def test_threshold_boundary_at(self) -> None:
        text_500 = "x" * 500
        transcript = [
            _assistant_entry([
                _text_block(text_500),
                _tool_block("TaskOutput", {"task_id": "a"}),
            ])
        ]
        assert is_agent_coordination_turn(transcript) is False
