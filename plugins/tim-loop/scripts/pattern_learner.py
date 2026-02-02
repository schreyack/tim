#!/usr/bin/env python3
"""
Pattern Learner CLI

Reviews LLM catches and helps convert them to YAML patterns.
This creates a feedback loop where the system improves over time.

Usage:
    python pattern_learner.py review     # Review pending catches
    python pattern_learner.py stats      # Show catch statistics
    python pattern_learner.py suggest    # Generate pattern suggestions
"""

import argparse
import json
import sys
from collections import Counter
from datetime import datetime
from pathlib import Path

CATCH_LOG_PATH = Path(__file__).parent / "llm_catches.jsonl"
PATTERNS_YAML_PATH = Path(__file__).parent / "excuse_patterns.yaml"


def load_catches() -> list[dict]:
    """Load all catches from the log file."""
    if not CATCH_LOG_PATH.exists():
        return []
    catches = []
    with open(CATCH_LOG_PATH, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line:
                try:
                    catches.append(json.loads(line))
                except json.JSONDecodeError:
                    continue
    return catches


def get_pending_catches() -> list[dict]:
    """Get catches that haven't been converted to patterns yet."""
    return [c for c in load_catches() if not c.get("pattern_added")]


def show_stats():
    """Show statistics about LLM catches."""
    catches = load_catches()
    if not catches:
        print("No catches logged yet.")
        return

    pending = [c for c in catches if not c.get("pattern_added")]
    converted = [c for c in catches if c.get("pattern_added")]

    print(f"Total catches: {len(catches)}")
    print(f"Pending (need patterns): {len(pending)}")
    print(f"Converted to patterns: {len(converted)}")
    print()

    # Category breakdown
    categories = Counter(c.get("category", "unknown") for c in catches)
    print("By category:")
    for cat, count in categories.most_common():
        print(f"  {cat}: {count}")


def suggest_pattern(catch: dict) -> str:
    """Generate a suggested YAML pattern entry."""
    excerpt = catch.get("transcript_excerpt", "")
    reason = catch.get("failure_reason", "")
    category = catch.get("category", "general")

    # Try to extract a potential pattern from the excerpt
    # This is a simple heuristic - human review is still needed
    words = excerpt.split()[:10]
    hint = " ".join(words) if words else "TODO"

    return f"""  # Suggested pattern from LLM catch on {catch.get('timestamp', 'unknown')[:10]}
  # Reason: {reason[:80]}
  - pattern: "TODO: Create regex from: {hint}..."
    category: {category}
    description: "{reason[:60]}..."
    example: "{excerpt[:60]}..."
    added_from_llm: true
    added_date: "{datetime.now().strftime('%Y-%m-%d')}"
"""


def review_catches():
    """Interactive review of pending catches."""
    pending = get_pending_catches()
    if not pending:
        print("No pending catches to review.")
        print("The LLM-as-judge hasn't caught anything that regex missed.")
        return

    print(f"Found {len(pending)} pending catches.\n")

    for i, catch in enumerate(pending, 1):
        print(f"=== Catch {i}/{len(pending)} ===")
        print(f"Timestamp: {catch.get('timestamp', 'unknown')}")
        print(f"Category: {catch.get('category', 'unknown')}")
        print(f"Reason: {catch.get('failure_reason', 'unknown')}")
        print(f"\nTranscript excerpt:")
        print(f"  {catch.get('transcript_excerpt', '')[:300]}...")
        print(f"\nSuggested YAML pattern:")
        print(suggest_pattern(catch))
        print()

        # In a full implementation, we'd prompt for action here
        # For now, just show the suggestions


def generate_suggestions():
    """Generate all pattern suggestions for pending catches."""
    pending = get_pending_catches()
    if not pending:
        print("No pending catches.")
        return

    print("# Suggested patterns to add to excuse_patterns.yaml")
    print("# Review each one and create appropriate regex patterns\n")

    for catch in pending:
        print(suggest_pattern(catch))


def mark_catch_as_added(timestamp: str):
    """Mark a catch as having been converted to a pattern."""
    catches = load_catches()
    updated = []
    for catch in catches:
        if catch.get("timestamp") == timestamp:
            catch["pattern_added"] = True
        updated.append(catch)

    with open(CATCH_LOG_PATH, "w", encoding="utf-8") as f:
        for catch in updated:
            f.write(json.dumps(catch) + "\n")


def main():
    parser = argparse.ArgumentParser(description="Pattern Learner CLI")
    parser.add_argument(
        "command",
        choices=["review", "stats", "suggest"],
        help="Command to run",
    )

    args = parser.parse_args()

    if args.command == "review":
        review_catches()
    elif args.command == "stats":
        show_stats()
    elif args.command == "suggest":
        generate_suggestions()


if __name__ == "__main__":
    main()
