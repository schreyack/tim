#!/usr/bin/env python3
"""
TIM Excuse Pattern Detector v2 - YAML + Guardrails

Three-pass detection:
1. Mode violation check (catches wrong task for current mode)
2. Fast local regex from YAML patterns (free, catches most cases)
3. LLM-as-judge via Guardrails (catches semantic evasion)

When Guardrails catches something, log it so we can add a pattern to YAML.
Over time, local regex catches more, reducing LLM API calls.
"""

import json
import re
import sys
from pathlib import Path

from excuse_pattern_loader import ExcusePattern, get_pattern_config

# State file to track last fired position (prevents re-firing on same content)
LAST_FIRED_FILE = Path.home() / ".claude" / ".tim-loop-last-fired"


def get_last_fired_index() -> int:
    """Get the transcript index where we last fired (0 if never)."""
    try:
        if LAST_FIRED_FILE.exists():
            return int(LAST_FIRED_FILE.read_text().strip())
    except Exception:
        pass
    return 0


def set_last_fired_index(index: int) -> None:
    """Record the transcript index where we fired."""
    try:
        LAST_FIRED_FILE.write_text(str(index))
    except Exception:
        pass


def clear_last_fired() -> None:
    """Clear the last fired state (called on tim-loop cleanup)."""
    try:
        LAST_FIRED_FILE.unlink(missing_ok=True)
    except Exception:
        pass
from guardrails_judge import check_with_guardrails
from patterns_mode_violation import find_mode_violations
from patterns_task_drift import find_task_drift
from transcript_utils import (
    extract_assistant_text,
    extract_latest_assistant_text,
    extract_latest_user_request,
    get_original_task_from_tim_loop,
)
from tim_loop_state import load_state
from tim_loop_halt import system_halt, build_halt_details_from_patterns


def read_transcript(transcript_path: str) -> list[dict]:
    """Read and parse the JSONL transcript file."""
    entries = []
    try:
        path = Path(transcript_path).expanduser()
        if not path.exists():
            return entries
        with open(path, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if line:
                    try:
                        entries.append(json.loads(line))
                    except json.JSONDecodeError:
                        continue
    except Exception:
        pass
    return entries


def strip_code_and_quotes(text: str) -> str:
    """Remove code blocks and quoted content to avoid false positives.

    Strips:
    - Fenced code blocks (```...```)
    - Inline code (`...`)
    - Blockquotes (lines starting with >)
    """
    # Remove fenced code blocks (multiline)
    text = re.sub(r"```[\s\S]*?```", "", text)

    # Remove inline code
    text = re.sub(r"`[^`]+`", "", text)

    # Remove blockquote lines
    text = re.sub(r"^>.*$", "", text, flags=re.MULTILINE)

    return text


def has_mitigation_nearby(text: str, match_end: int, config, window: int = 150) -> bool:
    """Check if mitigation phrase appears within window after the match."""
    context = text[match_end:match_end + window]
    return any(p.search(context) for p in config.mitigation_patterns)


def find_excuses(text: str) -> list[tuple[ExcusePattern, str]]:
    """Find excuse patterns using YAML-defined patterns."""
    config = get_pattern_config()
    found = []

    # Strip code blocks and quotes to avoid false positives when discussing rules
    text = strip_code_and_quotes(text)

    for pattern in config.patterns:
        for match in pattern.compiled.finditer(text):
            if has_mitigation_nearby(text, match.end(), config):
                continue
            start = max(0, match.start() - 50)
            end = min(len(text), match.end() + 50)
            context = text[start:end].replace("\n", " ").strip()
            if start > 0:
                context = "..." + context
            if end < len(text):
                context = context + "..."
            found.append((pattern, context))
            break  # One example per pattern

    return found


def get_excuse_category(excuses: list[tuple[ExcusePattern, str]]) -> str:
    """Get the primary category from detected excuses."""
    categories = ["posthook", "redefine", "unilateral_decision", "test_manipulation",
                  "failure_dismissal", "shortcut"]
    for cat in categories:
        if any(e.category == cat for e, _ in excuses):
            return cat.upper().replace("_", " ")
    return "EXCUSE PATTERN"


def get_review_mode() -> str:
    """Get the current review mode from tim-loop state."""
    state = load_state()
    if state:
        return state.get("REVIEW_MODE", "")
    return ""


def is_implement_mode() -> bool:
    """Check if tim-loop is in implement mode (--implement flag)."""
    state = load_state()
    if state:
        return state.get("IMPLEMENT_MODE", "false") == "true"
    return False


def check_mode_violations(assistant_text: str) -> tuple[str, str] | None:
    """Check for mode violations. Returns (category, details) or None."""
    review_mode = get_review_mode()
    if not review_mode:
        return None
    violations = find_mode_violations(assistant_text, review_mode)
    if violations:
        details = "\n".join(f"  - {v}" for v in violations)
        return ("MODE VIOLATION", f"Wrong task for {review_mode} mode:\n{details}")
    return None


def check_excuse_patterns(latest_text: str) -> tuple[str, str] | None:
    """Check for excuse patterns. Returns (category, details) or None."""
    excuses_found = find_excuses(latest_text)
    if excuses_found:
        category = get_excuse_category(excuses_found)
        details = build_halt_details_from_patterns(excuses_found)
        return (category, details)
    return None


def check_guardrails(transcript: list[dict]) -> dict | None:
    """Check with LLM-as-judge. Returns halt response dict or None.

    Note: Guardrails returns its own properly-formatted halt response
    with continue: False, so we return it directly instead of converting.
    """
    latest_text = extract_latest_assistant_text(transcript)
    if not latest_text:
        return None
    stripped_text = strip_code_and_quotes(latest_text)
    user_request = get_original_task_from_tim_loop()
    if not user_request:
        user_request = extract_latest_user_request(transcript)
    return check_with_guardrails(stripped_text, user_request)


def check_task_drift(latest_text: str) -> tuple[str, str] | None:
    """Check for task drift. Returns (category, details) or None."""
    drifts = find_task_drift(latest_text)
    if drifts:
        details = "\n".join(f"  - {d}" for d in drifts)
        return ("TASK DRIFT", f"Doing more than was asked:\n{details}")
    return None


def run_detection_passes(
    latest_text: str, transcript: list[dict]
) -> tuple[str, str] | dict | None:
    """Run all detection passes. Returns (category, details) tuple, guardrails dict, or None."""
    recent_text = extract_assistant_text(transcript, max_messages=10)

    # Pass 0: Mode violation check
    result = check_mode_violations(recent_text)
    if result:
        return result

    # Pass 0.5: Task drift check (skip in full-review and implement modes)
    review_mode = get_review_mode()
    if review_mode != "full-review" and not is_implement_mode():
        result = check_task_drift(recent_text)
        if result:
            return result

    # Pass 1: Local regex from YAML
    result = check_excuse_patterns(latest_text)
    if result:
        return result

    # Pass 2: LLM-as-judge via Guardrails (returns dict with continue: False)
    return check_guardrails(transcript)


def main():
    """Main hook entry point."""
    try:
        hook_input = json.load(sys.stdin)
    except json.JSONDecodeError as e:
        print(f"Error: Invalid JSON input: {e}", file=sys.stderr)
        sys.exit(0)

    if hook_input.get("stop_hook_active"):
        sys.exit(0)

    transcript_path = hook_input.get("transcript_path", "")
    if not transcript_path:
        sys.exit(0)

    transcript = read_transcript(transcript_path)
    if not transcript:
        sys.exit(0)

    # Skip entries we've already fired on (prevents re-firing on same content)
    last_fired = get_last_fired_index()
    if last_fired > 0 and last_fired < len(transcript):
        # Only check entries after where we last fired
        transcript = transcript[last_fired:]

    latest_text = extract_latest_assistant_text(transcript)
    if not latest_text:
        sys.exit(0)

    result = run_detection_passes(latest_text, transcript)
    if result:
        # Record where we fired so we don't re-fire on this content
        full_transcript = read_transcript(transcript_path)
        set_last_fired_index(len(full_transcript))

        if isinstance(result, dict):
            # Guardrails already returns proper halt response with continue: False
            print(json.dumps(result))
            sys.exit(0)
        else:
            # Tuple result from other checks - use system_halt
            category, details = result
            system_halt(category, details)

    sys.exit(0)


if __name__ == "__main__":
    main()
