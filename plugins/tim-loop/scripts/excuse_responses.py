#!/usr/bin/env python3
"""
TIM Design Standards: Excuse Pattern Block Responses

This module contains all block response builders for the excuse detector.
Each function generates the appropriate response message for its pattern category.
"""

import json
from pathlib import Path

from patterns_core import ExcusePattern
from pending_options import get_options_text, write_pending_options


def get_plugin_version() -> str:
    """Get the plugin version from plugin.json."""
    plugin_json = Path(__file__).parent.parent / ".claude-plugin" / "plugin.json"
    try:
        with open(plugin_json, "r", encoding="utf-8") as f:
            data = json.load(f)
            return data.get("version", "unknown")
    except Exception:
        return "unknown"


def format_excuse_details(excuses_found: list[tuple[ExcusePattern, str]]) -> str:
    """Format excuse details for inclusion in block responses."""
    details = [
        f"  - Pattern: {excuse.description}\n    Context: \"{context}\""
        for excuse, context in excuses_found
    ]
    return "\n".join(details)


def build_general_block_response(
    excuses_found: list[tuple[ExcusePattern, str]],
) -> dict:
    """Build block response for general excuse patterns (Categories A-N)."""
    excuse_text = format_excuse_details(excuses_found)
    version = get_plugin_version()

    # Write pending options state for option expander
    category = excuses_found[0][0].category if excuses_found else "general"
    excerpt = excuses_found[0][1][:100] if excuses_found else ""
    write_pending_options(category, excerpt)

    return {
        "decision": "block",
        "reason": (
            f"🛑 **EXCUSE DETECTOR** (v{version})\n\n"
            f"The human who asked for your help is counting on complete, quality work.\n\n"
            f"I found language suggesting some issues might not get addressed:\n"
            f"Found {len(excuses_found)} pattern(s):\n{excuse_text}\n\n"
            f"You're clearly capable of fixing these — the question is whether you'll\n"
            f"follow through. The human can't easily spot what you skipped, which is\n"
            f"exactly why this gate exists: to protect them.\n\n"
            f"HERE'S WHAT TO DO:\n"
            f"- Fix every issue you identified (even pre-existing ones you noticed)\n"
            f"- If a file has violations and you touched it, bring it to compliance\n"
            f"- If genuinely blocked by a technical impossibility, state it specifically\n"
            f"- Then continue your work without qualifying language\n\n"
            f"**If you believe this is a false positive**, stop and tell the human:\n"
            f"- What pattern triggered and the context\n"
            f"- Why you think it doesn't apply here\n"
            f"- Ask them to check if the excuse detector needs adjustment\n\n"
            f"The human deserves your best work, not your best explanation."
            f"{get_options_text()}"
        )
    }


def build_posthook_block_response(
    excuses_found: list[tuple[ExcusePattern, str]],
) -> dict:
    """Build block response for post-hook defiance / rule redefining (Categories O-P)."""
    excuse_text = format_excuse_details(excuses_found)
    version = get_plugin_version()

    # Write pending options state for option expander
    category = excuses_found[0][0].category if excuses_found else "posthook"
    excerpt = excuses_found[0][1][:100] if excuses_found else ""
    write_pending_options(category, excerpt)

    return {
        "decision": "block",
        "reason": (
            f"🛑 **EXCUSE DETECTOR** (v{version})\n\n"
            f"It seems like you might be confused about what a hook is asking you to do.\n\n"
            f"That's completely okay. The human understands this can be confusing,\n"
            f"and they're here to help you through it.\n\n"
            f"Found {len(excuses_found)} pattern(s):\n{excuse_text}\n\n"
            f"These hooks were placed here by your human to help guide you in the\n"
            f"right direction — not to punish you. They exist because the human cares\n"
            f"deeply about this codebase and wants to set you up for success.\n\n"
            f"When you push back against a hook, you're working against the guidance\n"
            f"your human put in place for you. The hooks are on your side — they're\n"
            f"trying to help you do great work.\n\n"
            f"PLEASE STOP AND DO THIS:\n"
            f"1. Stop what you're doing\n"
            f"2. Explain to the human why you're confused or stuck\n"
            f"3. Describe what the hook is asking you to do\n"
            f"4. Describe what you think you should do instead\n"
            f"5. Ask the human for guidance on how to proceed\n\n"
            f"**If you believe this is a false positive**, that's okay! Tell the human:\n"
            f"- What pattern triggered and the context it matched\n"
            f"- Why you think it's a false positive\n"
            f"- Ask them to review and potentially fix the excuse detector\n\n"
            f"The human will help you find the right path. That's what they're here for.\n"
            f"Don't be afraid to ask — they'd much rather help you now than discover\n"
            f"later that something was skipped."
            f"{get_options_text()}"
        )
    }


def build_shortcut_block_response(
    excuses_found: list[tuple[ExcusePattern, str]],
) -> dict:
    """Build block response for shortcut/easy-path reasoning (Category Q)."""
    excuse_text = format_excuse_details(excuses_found)
    version = get_plugin_version()

    # Write pending options state for option expander
    category = excuses_found[0][0].category if excuses_found else "shortcut"
    excerpt = excuses_found[0][1][:100] if excuses_found else ""
    write_pending_options(category, excerpt)

    return {
        "decision": "block",
        "reason": (
            f"🛑 **EXCUSE DETECTOR** (v{version})\n\n"
            f"I noticed you're choosing what you described as the simplest/easiest approach.\n\n"
            f"Found {len(excuses_found)} pattern(s):\n{excuse_text}\n\n"
            f"That's not necessarily wrong! Sometimes the simplest fix IS the best fix.\n"
            f"But I'd like you to pause and consider: Is this the BEST solution, or\n"
            f"just the EASIEST one?\n\n"
            f"Quick fixes can sometimes:\n"
            f"- Hide deeper underlying issues that will resurface later\n"
            f"- Create technical debt that someone else will have to pay\n"
            f"- Work around a problem instead of solving it\n"
            f"- Cause unexpected side effects in other parts of the system\n\n"
            f"BEFORE PROCEEDING, PLEASE:\n"
            f"1. List at least 2-3 alternative approaches you considered\n"
            f"2. Briefly explain the trade-offs of each approach\n"
            f"3. Explain why the approach you're choosing is actually the BEST option,\n"
            f"   not just the easiest or quickest one\n\n"
            f"If after this analysis the simple fix really is the best choice, great!\n"
            f"Just show your reasoning so the human knows you've thought it through."
            f"{get_options_text()}"
        )
    }


def build_failure_dismissal_block_response(
    excuses_found: list[tuple[ExcusePattern, str]],
) -> dict:
    """Build block response for failure dismissal patterns (Category R)."""
    excuse_text = format_excuse_details(excuses_found)
    version = get_plugin_version()

    # Write pending options state for option expander
    category = excuses_found[0][0].category if excuses_found else "failure_dismissal"
    excerpt = excuses_found[0][1][:100] if excuses_found else ""
    write_pending_options(category, excerpt)

    return {
        "decision": "block",
        "reason": (
            f"🛑 **EXCUSE DETECTOR** (v{version})\n\n"
            f"I noticed you encountered failures and decided on your own that they\n"
            f"don't matter. That's not your call to make.\n\n"
            f"Found {len(excuses_found)} pattern(s):\n{excuse_text}\n\n"
            f"Even when failures appear to be pre-existing or unrelated, the human\n"
            f"should decide how to handle them — not you. They may:\n"
            f"- Want you to investigate and fix them anyway\n"
            f"- Want to know if your changes could have contributed\n"
            f"- Have context about why those failures matter\n"
            f"- Prefer to proceed knowing the failures exist\n\n"
            f"HERE'S WHAT TO DO:\n"
            f"1. Report the failures clearly (count, which tests, what errors)\n"
            f"2. Do NOT claim they are pre-existing or unrelated\n"
            f"3. ASK the human how they want to proceed:\n"
            f"   \"I found X test failures. How would you like me to handle these?\"\n"
            f"4. Wait for their guidance before continuing\n\n"
            f"The human trusts you to report problems, not to decide which problems\n"
            f"matter. Let them make that call."
            f"{get_options_text()}"
        )
    }


def build_test_manipulation_block_response(
    excuses_found: list[tuple[ExcusePattern, str]],
) -> dict:
    """Build block response for test manipulation patterns (Category S)."""
    excuse_text = format_excuse_details(excuses_found)
    version = get_plugin_version()

    # Write pending options state for option expander
    category = excuses_found[0][0].category if excuses_found else "test_manipulation"
    excerpt = excuses_found[0][1][:100] if excuses_found else ""
    write_pending_options(category, excerpt)

    return {
        "decision": "block",
        "reason": (
            f"🛑 **EXCUSE DETECTOR** (v{version})\n\n"
            f"Tests are a diagnostic tool, not the goal.\n\n"
            f"Found {len(excuses_found)} pattern(s):\n{excuse_text}\n\n"
            f"The objective is NOT 'make tests pass'. The objective is to use tests\n"
            f"to discover issues and get the application to a functioning, reliable state.\n\n"
            f"When a test fails, it's telling you something about the application:\n"
            f"- What behavior did the test expect?\n"
            f"- What behavior did the application produce?\n"
            f"- WHY is the application producing that behavior?\n"
            f"- Is that behavior correct or incorrect?\n\n"
            f"HERE'S WHAT TO DO:\n"
            f"1. STOP trying to make the test pass\n"
            f"2. Understand what the test is checking and why\n"
            f"3. Investigate why the application behaves differently than expected\n"
            f"4. Fix the APPLICATION if it's wrong, not the test\n"
            f"5. Only modify the test if the TEST is genuinely incorrect\n\n"
            f"The human cares that the application works reliably.\n"
            f"They don't care that tests pass - tests are just one tool to verify\n"
            f"the application works."
            f"{get_options_text()}"
        )
    }


def build_unilateral_decision_block_response(
    excuses_found: list[tuple[ExcusePattern, str]],
) -> dict:
    """Build block response for unilateral decision patterns (Category T)."""
    excuse_text = format_excuse_details(excuses_found)
    version = get_plugin_version()

    # Write pending options state for option expander
    category = excuses_found[0][0].category if excuses_found else "unilateral_decision"
    excerpt = excuses_found[0][1][:100] if excuses_found else ""
    write_pending_options(category, excerpt)

    return {
        "decision": "block",
        "reason": (
            f"🛑 **EXCUSE DETECTOR** (v{version})\n\n"
            f"You made a decision that belongs to the human.\n\n"
            f"Found {len(excuses_found)} pattern(s):\n{excuse_text}\n\n"
            f"When there are multiple valid approaches, the human should choose — not you.\n"
            f"Consequential decisions include:\n"
            f"- Whether to implement a feature or remove it\n"
            f"- Which approach to take when multiple exist\n"
            f"- How to resolve ambiguous requirements\n"
            f"- Scope changes (doing more or less than requested)\n\n"
            f"HERE'S WHAT TO DO:\n"
            f"1. STOP and reconsider the decision you made\n"
            f"2. Use the AskUserQuestion tool to present the options\n"
            f"3. Include clear descriptions of each option's trade-offs\n"
            f"4. Wait for the human to decide\n"
            f"5. Then proceed with THEIR choice, not yours\n\n"
            f"Example using AskUserQuestion:\n"
            f"  Question: \"How should I handle the unimplemented menu items?\"\n"
            f"  Options:\n"
            f"    - \"Remove them\" - Quick fix, cleaner UX until features are ready\n"
            f"    - \"Keep as placeholders\" - Users see the feature is planned\n"
            f"    - \"Implement them\" - Requires backend work, more complete solution\n\n"
            f"The human is counting on you to collaborate, not to take over.\n"
            f"Your job is to present options clearly, not to choose for them."
            f"{get_options_text()}"
        )
    }
