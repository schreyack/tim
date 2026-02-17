#!/usr/bin/env python3
"""
Review Quality Judge - Evaluates whether a review is substantive or superficial.

Used by --llm-loop to determine if Claude's review output demonstrates genuine
analytical engagement vs rubber-stamping. The caller decides whether to invoke
this based on the LLM_LOOP state flag.

Returns:
    {"passed": True/False, "reason": "..."} on success or failure
    {"error": "unreachable", "detail": "..."} when server can't be reached
    {"error": "bad_response", "detail": "..."} when server responds but parsing fails
"""

import json
import sys
import urllib.error
import urllib.request

from judge_config import get_llm_config
from judge_criteria import JUDGE_CRITERIA_REVIEW_QUALITY

# Reviews under this length are auto-failed as too short
MIN_REVIEW_LENGTH = 100

# Truncate input to fit local LLM context limits
MAX_INPUT_LENGTH = 4000


def _build_quality_request(review_text: str) -> tuple[urllib.request.Request, dict]:
    """Build the LLM API request for review quality evaluation."""
    config = get_llm_config()
    server = config["server"].rstrip("/")
    model = config["model"]

    if model.startswith("ollama/"):
        model = model[7:]

    truncated = review_text[:MAX_INPUT_LENGTH]
    prompt = (
        f"{JUDGE_CRITERIA_REVIEW_QUALITY}\n\n---\n\n"
        f"Review output to evaluate:\n{truncated}\n\n---\n\n"
        f"Verdict (PASS or FAIL with explanation):"
    )

    payload = json.dumps({
        "model": model,
        "messages": [{"role": "user", "content": prompt}],
        "stream": False,
    }).encode("utf-8")

    req = urllib.request.Request(
        f"{server}/v1/chat/completions",
        data=payload,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    return req, config


def _call_quality_judge(req: urllib.request.Request, config: dict) -> dict:
    """Execute the LLM API call and parse the verdict."""
    try:
        with urllib.request.urlopen(req, timeout=config.get("timeout", 30)) as resp:
            raw = resp.read().decode("utf-8")
    except urllib.error.URLError as e:
        detail = f"Could not reach LLM server: {e}"
        print(f"Warning: {detail}", file=sys.stderr)
        return {"error": "unreachable", "detail": detail}

    try:
        result = json.loads(raw)
    except json.JSONDecodeError as e:
        detail = f"LLM returned invalid JSON: {e} — raw response: {raw[:200]}"
        print(f"Warning: {detail}", file=sys.stderr)
        return {"error": "bad_response", "detail": detail}

    try:
        content = result["choices"][0]["message"]["content"]
    except (KeyError, IndexError, TypeError) as e:
        detail = f"Unexpected response structure ({type(e).__name__}: {e}) — keys: {list(result.keys())}"
        print(f"Warning: {detail}", file=sys.stderr)
        return {"error": "bad_response", "detail": detail}

    return _parse_verdict(content)


def judge_review_quality(review_text: str) -> dict:
    """Evaluate whether a review demonstrates genuine analytical engagement.

    Args:
        review_text: The assistant's review output to evaluate.

    Returns:
        {"passed": True/False, "reason": "..."} on success/failure.
        {"error": "unreachable", "detail": "..."} when server can't be reached.
        {"error": "bad_response", "detail": "..."} when response can't be parsed.
    """
    review_text = review_text.strip()

    if len(review_text) < MIN_REVIEW_LENGTH:
        return {
            "passed": False,
            "reason": (
                f"Review output is only {len(review_text)} characters - "
                f"too short to be a substantive review."
            ),
        }

    req, config = _build_quality_request(review_text)
    return _call_quality_judge(req, config)


def _parse_verdict(content: str) -> dict:
    """Parse LLM response into pass/fail verdict."""
    first_line = content.strip().split("\n")[0].upper().replace("*", "").replace("_", "")
    passed = not ("FAIL" in first_line and "PASS" not in first_line)
    return {"passed": passed, "reason": content}
