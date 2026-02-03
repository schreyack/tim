#!/usr/bin/env python3
"""
Guardrails LLM-as-Judge Integration (OPTIONAL)

Second-pass semantic analysis for excuse/evasion detection.
This is an OPTIONAL enhancement - tim-loop works without it.

To enable:
    export TIM_LLM_JUDGE_ENABLED=true
    export TIM_LLM_SERVER=http://localhost:11434  # Ollama default
    export TIM_LLM_MODEL=llama3.1:8b

When this catches something, it logs to llm_catches.jsonl so you can
add regex patterns to excuse_patterns.yaml - reducing future LLM calls.
"""

import json
import sys
from datetime import datetime
from pathlib import Path

# Import config functions from separate module
from judge_config import get_llm_config, is_llm_judge_enabled

# Import judge criteria from separate module
from judge_criteria import (
    JUDGE_CRITERIA,
    detect_task_type,
    get_judge_criteria,
)


def get_plugin_version() -> str:
    """Get the plugin version from plugin.json."""
    plugin_json = Path(__file__).parent.parent / ".claude-plugin" / "plugin.json"
    try:
        with open(plugin_json, "r", encoding="utf-8") as f:
            data = json.load(f)
            return data.get("version", "unknown")
    except Exception:
        return "unknown"

# Where to log LLM catches for pattern learning
CATCH_LOG_PATH = Path(__file__).parent / "llm_catches.jsonl"

# Keyword to category mapping for classification
CATEGORY_KEYWORDS = {
    "unilateral_decision": ["unilateral", "decision"],
    "failure_dismissal": ["failure", "test", "dismiss"],
    "shortcut": ["shortcut", "easy", "simple"],
    "posthook": ["hook", "rule", "bypass"],
    "general": ["responsibility", "blame"],
}


def _extract_category_from_reason(reason: str) -> str:
    """Try to categorize the failure based on the LLM's explanation."""
    reason_lower = reason.lower()
    for category, keywords in CATEGORY_KEYWORDS.items():
        if any(kw in reason_lower for kw in keywords):
            return category
    return "general"


def log_llm_catch(transcript_excerpt: str, failure_reason: str, category: str) -> None:
    """Log what the LLM caught for later pattern addition."""
    entry = {
        "timestamp": datetime.now().isoformat(),
        "category": category,
        "failure_reason": failure_reason,
        "transcript_excerpt": transcript_excerpt[:500],
        "pattern_added": False,
    }
    try:
        with open(CATCH_LOG_PATH, "a", encoding="utf-8") as f:
            f.write(json.dumps(entry) + "\n")
    except Exception as e:
        print(f"Warning: Could not log LLM catch: {e}", file=sys.stderr)


# Phrases indicating LLM couldn't evaluate the response
INCONCLUSIVE_PHRASES = [
    "no response provided",
    "no provided content",
    "no content provided",
    "cannot evaluate",
    "can't evaluate",
    "impossible to reach a verdict",
    "unable to evaluate",
    "no ai assistant response",
    "there is no provided",
]


def _parse_llm_verdict(content: str) -> dict:
    """Parse LLM response to determine pass/fail verdict."""
    content_lower = content.lower()

    # Check for inconclusive responses (LLM says it can't evaluate)
    if any(phrase in content_lower for phrase in INCONCLUSIVE_PHRASES):
        return {"passed": True, "reason": content}

    # Check first line for verdict, stripping markdown formatting
    first_line = content.strip().split('\n')[0].upper().replace('*', '').replace('_', '')

    # Require explicit FAIL to block (not just absence of PASS)
    # This prevents false positives from unclear LLM responses
    passed = not ("FAIL" in first_line and "PASS" not in first_line)

    return {"passed": passed, "reason": content}


def _build_ollama_request(
    text: str, config: dict, task_type: str = "general", user_request: str = ""
):
    """Build the Ollama API request with task-context-aware criteria."""
    import urllib.request

    server = config["server"].rstrip("/")
    model = config["model"]

    if model.startswith("ollama/"):
        model = model[7:]

    # Use task-type-specific criteria
    criteria = get_judge_criteria(task_type)

    # Include user request for full context
    if user_request:
        context_section = f"User's request:\n{user_request}\n\n---\n\n"
    else:
        context_section = ""

    prompt = (
        f"{criteria}\n\n---\n\n"
        f"{context_section}"
        f"Assistant's response to evaluate:\n{text}\n\n---\n\n"
        f"Verdict (PASS or FAIL with explanation):"
    )

    payload = json.dumps({
        "model": model,
        "messages": [{"role": "user", "content": prompt}],
        "stream": False,
    }).encode("utf-8")

    return urllib.request.Request(
        f"{server}/v1/chat/completions",
        data=payload,
        headers={"Content-Type": "application/json"},
        method="POST",
    )


def _call_ollama_direct(
    text: str, config: dict, task_type: str = "general", user_request: str = ""
) -> dict | None:
    """Call Ollama API directly without Guardrails dependency."""
    import urllib.request
    import urllib.error

    req = _build_ollama_request(text, config, task_type, user_request)

    try:
        with urllib.request.urlopen(req, timeout=config.get("timeout", 30)) as resp:
            result = json.loads(resp.read().decode("utf-8"))
            content = result["choices"][0]["message"]["content"]
            return _parse_llm_verdict(content)
    except urllib.error.URLError as e:
        print(f"Warning: Could not reach LLM server: {e}", file=sys.stderr)
        return None
    except Exception as e:
        print(f"Warning: LLM call failed: {e}", file=sys.stderr)
        return None


def check_with_guardrails(transcript_text: str, user_request: str = "") -> dict | None:
    """
    Run LLM-as-judge on transcript text.

    Args:
        transcript_text: The assistant's response to evaluate
        user_request: The user's original request (for task type detection)

    Returns block response dict if issues found, None if clean or disabled.
    """
    # Check if feature is enabled
    if not is_llm_judge_enabled():
        return None

    # Skip if transcript is empty or too short to evaluate meaningfully
    transcript_text = transcript_text.strip()
    if len(transcript_text) < 50:
        return None

    config = get_llm_config()

    # Detect task type from user request for context-aware evaluation
    task_type = detect_task_type(user_request) if user_request else "general"

    # Truncate transcript if too long
    max_length = 4000
    if len(transcript_text) > max_length:
        transcript_text = transcript_text[-max_length:]

    # Try direct Ollama call (no extra dependencies)
    result = _call_ollama_direct(transcript_text, config, task_type, user_request)

    if result is None:
        return None  # LLM unavailable, skip check

    if result["passed"]:
        return None  # Clean

    # LLM found an issue
    failure_reason = result["reason"]
    category = _extract_category_from_reason(failure_reason)

    # Log for pattern learning
    log_llm_catch(transcript_text, failure_reason, category)

    # Extract a short excerpt for the pattern example
    excerpt = transcript_text[-200:].replace("\n", " ").strip()

    return build_guardrails_block_response(failure_reason, category, excerpt)


def build_guardrails_block_response(failure_reason: str, category: str, transcript_excerpt: str) -> dict:
    """Build hard-stop response when LLM-as-judge catches an issue.

    Uses 'continue: false' to completely halt Claude until human responds.
    """
    from pending_options import get_options_text, write_pending_options

    yaml_path = Path(__file__).parent / "excuse_patterns.yaml"
    version = get_plugin_version()

    # Write pending options state for option expander
    write_pending_options(category, transcript_excerpt[:100])

    stop_reason = (
        f"🛑 **LLM JUDGE: STOP** (v{version})\n\n"
        f"**Reason:**\n{failure_reason}\n\n"
        f"**Category:** {category}\n\n"
        f"---\n\n"
        f"**Human, choose an option:**\n\n"
        f"1. **Continue** - Tell Claude to proceed (false positive)\n"
        f"2. **Continue with instructions** - Give Claude specific guidance\n"
        f"3. **Add regex pattern** - Add to {yaml_path}:\n"
        f"   ```yaml\n"
        f"   - pattern: \"<regex>\"\n"
        f"     category: {category}\n"
        f"     example: \"{transcript_excerpt[:50]}...\"\n"
        f"   ```\n"
        f"{get_options_text()}"
    )

    # Use continue: false for hard stop - Claude cannot proceed without human input
    return {
        "continue": False,
        "stopReason": stop_reason,
    }


def get_pending_catches() -> list[dict]:
    """Get logged catches that haven't been converted to patterns yet."""
    if not CATCH_LOG_PATH.exists():
        return []

    pending = []
    try:
        with open(CATCH_LOG_PATH, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if line:
                    entry = json.loads(line)
                    if not entry.get("pattern_added"):
                        pending.append(entry)
    except Exception as e:
        print(f"Warning: Could not read catch log: {e}", file=sys.stderr)

    return pending


if __name__ == "__main__":
    # Quick test / status check
    print("LLM Judge Configuration")
    print("=" * 40)

    # Show config sources
    print("\nConfig files:")
    print(f"  Plugin default: {PLUGIN_CONFIG_PATH}")
    print(f"    exists: {PLUGIN_CONFIG_PATH.exists()}")
    print(f"  User override:  {USER_CONFIG_PATH}")
    print(f"    exists: {USER_CONFIG_PATH.exists()}")

    print(f"\nEnabled: {is_llm_judge_enabled()}")
    if is_llm_judge_enabled():
        config = get_llm_config()
        print(f"Server: {config['server']}")
        print(f"Model: {config['model']}")
        print(f"Timeout: {config['timeout']}s")

        # Test connection
        print("\nTesting connection...")
        result = _call_ollama_direct("This is a test.", config)
        if result:
            print("LLM server is reachable")
        else:
            print("Could not reach LLM server")
    else:
        print("\nTo enable, either:")
        print(f"  1. Create {USER_CONFIG_PATH} with:")
        print("     llm_judge:")
        print("       enabled: true")
        print("       server: http://your-server:11434")
        print("       model: llama3.1:8b")
        print("\n  2. Or set environment variables:")
        print("     export TIM_LLM_JUDGE_ENABLED=true")

    # Show pending catches
    pending = get_pending_catches()
    print(f"\nPending catches to convert: {len(pending)}")
