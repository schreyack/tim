# AI Developer Ready Checklist

This checklist is used before a plan is approved for AI developer implementation. The goal is to catch issues that AI developers commonly face: ambiguous instructions, hallucination opportunities, over-engineering risks, and incomplete specifications.

**When to use:** Before running `./plugins/tim-loop/scripts/plan-ops.sh ai-ready <plan> --reviewer <name>`

**Who reviews:** A human with understanding of both the codebase and AI developer behavior.

---

## 1. Clarity and Unambiguity

Every instruction must have exactly one possible interpretation.

- [ ] **No ambiguous instructions** - Each step has one clear interpretation
  - Bad: "Update the function appropriately"
  - Good: "Add a `timeout` parameter with default value 30 to `fetch_data()`"

- [ ] **No implicit knowledge required** - All necessary context is provided
  - Bad: "Use the standard pattern for this"
  - Good: "Use the repository pattern as implemented in `src/repos/user_repo.py`"

- [ ] **No subjective judgment calls** - Criteria are objective
  - Bad: "Make the code cleaner"
  - Good: "Extract the validation logic into a `validate_input()` function"

- [ ] **File paths are absolute or relative to project root**
  - Bad: "Update the config file"
  - Good: "Update `config/settings.yaml` in the project root"

- [ ] **Success criteria are measurable** - Binary pass/fail, not subjective
  - Bad: "The feature should work well"
  - Good: "All tests in `tests/test_feature.py` pass; coverage >= 90%"

---

## 2. AI-Specific Pitfalls

Prevent common AI developer mistakes.

- [ ] **No hallucination opportunities** - All referenced items exist
  - Verify: APIs, methods, files, and dependencies actually exist
  - If creating new items, specify the exact name and location

- [ ] **No deprecated patterns** - References use current APIs
  - Check: The plan doesn't reference deprecated methods or old patterns
  - Specify: Current versions and APIs to use

- [ ] **No over-engineering risks** - Scope is clearly bounded
  - Bad: "Add a flexible configuration system"
  - Good: "Add a `CONFIG` dict at module level with keys: `timeout`, `retries`"

- [ ] **No incomplete implementations** - Specific, not vague
  - Bad: "Add basic error handling"
  - Good: "Catch `ConnectionError` and `TimeoutError`, log with context, re-raise as `ServiceError`"

- [ ] **Test expectations are specific** - Not open-ended
  - Bad: "Test thoroughly"
  - Good: "Add tests for: valid input, empty input, invalid format, timeout scenario"

---

## 3. Guard Rails

Define boundaries and stop conditions.

- [ ] **Error handling is explicit** - Specific exceptions and responses
  - Enumerate: Which exceptions to catch
  - Specify: What to log, what to return, what to re-raise

- [ ] **Edge cases are enumerated** - Not "handle edge cases"
  - List: Empty input, null values, concurrent access, etc.
  - Specify: Expected behavior for each

- [ ] **Scope boundaries are clear** - What NOT to change
  - Explicitly state: "Do NOT modify files in `src/legacy/`"
  - Explicitly state: "Only change the specified function, not callers"

- [ ] **Stop conditions defined** - When to ask vs proceed
  - State: "If the API doesn't exist, STOP and ask"
  - State: "If tests fail after fix, document and continue to next item"

- [ ] **No placeholder opportunities** - Everything must be implemented
  - Bad: "Add authentication (details TBD)"
  - Good: "Add JWT authentication using `python-jose` library with RS256 algorithm"

---

## 4. Verification

Ensure the implementation can be verified.

- [ ] **Completion criteria are code-checkable** - Can grep/test for it
  - Good: "Function `validate_input()` exists in `src/validators.py`"
  - Good: "All tests pass: `pytest tests/test_feature.py -v`"

- [ ] **Test commands are exact** - Copy-paste runnable
  - Good: `pytest tests/test_auth.py -v --cov=src/auth --cov-fail-under=90`
  - Bad: "Run the tests"

- [ ] **Expected outputs are specified** - Know what success looks like
  - Specify: Expected return values
  - Specify: Expected log messages
  - Specify: Expected file contents or structure

- [ ] **Rollback path documented** - How to undo if needed
  - State: Which commits to revert
  - State: Which files to restore
  - State: Any database migrations to rollback

---

## Approval Process

After reviewing all items:

1. **If all items pass:**
   ```bash
   ./plugins/tim-loop/scripts/plan-ops.sh ai-ready <plan-file> --reviewer "<Your Name>"
   ```

2. **If items fail:**
   - Update the plan to address failures
   - Re-review the updated plan
   - Do NOT approve until all items pass

3. **Approval adds this stamp to the plan:**
   ```markdown
   ### AI Developer Ready Approval

   **Reviewer**: [Name]
   **Date**: YYYY-MM-DD
   **Iteration**: N (FINAL)
   **Status**: APPROVED
   ```

---

## Common Red Flags

These patterns almost always cause AI implementation problems:

| Red Flag | Why It's Bad | Fix |
|----------|--------------|-----|
| "Improve the code" | Too vague | Specify exactly what to change |
| "Use best practices" | Subjective | Reference specific pattern/standard |
| "Handle errors appropriately" | Ambiguous | List specific exceptions and handling |
| "Add tests" | Open-ended | Specify exact test cases |
| "Make it configurable" | Over-engineering risk | Specify exact config options |
| "Update related files" | Unbounded scope | List specific files |
| "Follow the existing pattern" | Requires inference | Reference specific file/function |
| "Clean up the code" | Subjective | Specify exact changes |

---

## Quick Reference

Before approving, verify:

1. **Every step has one interpretation** (no ambiguity)
2. **All references exist** (no hallucination opportunities)
3. **Scope is bounded** (explicit "do not" statements)
4. **Tests are specific** (exact commands and expectations)
5. **Rollback is documented** (how to undo)

If any of these are missing or unclear, the plan is NOT ready for AI implementation.
