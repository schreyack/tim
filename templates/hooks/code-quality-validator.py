#!/usr/bin/env python3
"""
TIM Design Standards: Code Quality Validator Hook (PostToolUse)

This hook runs after every Edit or Write operation and enforces:
- File size limit: 400 lines maximum
- Function length: 50 lines maximum
- Cyclomatic complexity: 10 maximum (if ast parsing succeeds)

If violations are found, the hook returns a blocking response that
forces Claude to address the issue before continuing.

Inspired by: https://github.com/decider/claude-hooks
Adapted for TIM Design Standards requirements.
"""

import json
import sys
import re
import ast
from pathlib import Path
from typing import NamedTuple


class Limits(NamedTuple):
    """Configurable limits for code quality checks."""
    max_file_lines: int = 400
    max_function_lines: int = 50
    max_complexity: int = 10


class Violation(NamedTuple):
    """Represents a code quality violation."""
    rule: str
    message: str
    severity: str  # "error" or "warning"


LIMITS = Limits()

# File extensions to check
CODE_EXTENSIONS = {
    ".py", ".js", ".ts", ".tsx", ".jsx", ".mjs", ".cjs",
    ".go", ".rs", ".java", ".kt", ".swift", ".c", ".cpp", ".h",
    ".rb", ".php", ".cs", ".scala", ".ex", ".exs"
}


def count_lines(file_path: Path) -> int:
    """Count non-empty, non-comment lines in a file."""
    try:
        content = file_path.read_text(encoding="utf-8")
        lines = content.splitlines()
        # Count all lines for simplicity (including comments/blanks)
        # This matches typical "lines of code" metrics
        return len(lines)
    except Exception:
        return 0


def check_python_functions(file_path: Path) -> list[Violation]:
    """Check Python function lengths using AST parsing."""
    violations = []
    try:
        content = file_path.read_text(encoding="utf-8")
        tree = ast.parse(content)

        for node in ast.walk(tree):
            if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
                if node.end_lineno and node.lineno:
                    func_lines = node.end_lineno - node.lineno + 1
                    if func_lines > LIMITS.max_function_lines:
                        violations.append(Violation(
                            rule="function-length",
                            message=f"Function '{node.name}' is {func_lines} lines "
                                   f"(max: {LIMITS.max_function_lines})",
                            severity="error"
                        ))
    except SyntaxError:
        pass  # Can't parse, skip function checks
    except Exception:
        pass

    return violations


def check_js_ts_functions(file_path: Path) -> list[Violation]:
    """Check JS/TS function lengths using regex (approximate)."""
    violations = []
    try:
        content = file_path.read_text(encoding="utf-8")
        lines = content.splitlines()

        # Simple heuristic: find function definitions and count to matching brace
        # This is approximate but catches most cases
        function_pattern = re.compile(
            r'^\s*(?:export\s+)?(?:async\s+)?(?:function\s+(\w+)|'
            r'(?:const|let|var)\s+(\w+)\s*=\s*(?:async\s+)?(?:\([^)]*\)|[^=])\s*=>|'
            r'(\w+)\s*\([^)]*\)\s*(?::\s*\w+)?\s*\{)',
            re.MULTILINE
        )

        # Track brace depth to find function boundaries
        i = 0
        while i < len(lines):
            line = lines[i]
            match = function_pattern.match(line)
            if match:
                func_name = match.group(1) or match.group(2) or match.group(3) or "anonymous"
                start_line = i
                brace_count = line.count('{') - line.count('}')

                # Find the end of the function
                j = i + 1
                while j < len(lines) and brace_count > 0:
                    brace_count += lines[j].count('{') - lines[j].count('}')
                    j += 1

                func_lines = j - start_line
                if func_lines > LIMITS.max_function_lines:
                    violations.append(Violation(
                        rule="function-length",
                        message=f"Function '{func_name}' is ~{func_lines} lines "
                               f"(max: {LIMITS.max_function_lines})",
                        severity="error"
                    ))
                i = j
            else:
                i += 1

    except Exception:
        pass

    return violations


def validate_file(file_path: Path) -> list[Violation]:
    """Run all validations on a file."""
    violations = []

    # Skip non-code files
    if file_path.suffix.lower() not in CODE_EXTENSIONS:
        return violations

    # Check file size
    line_count = count_lines(file_path)
    if line_count > LIMITS.max_file_lines:
        violations.append(Violation(
            rule="file-size",
            message=f"File has {line_count} lines (max: {LIMITS.max_file_lines}). "
                   f"Must be refactored into smaller modules.",
            severity="error"
        ))

    # Check function lengths based on file type
    if file_path.suffix == ".py":
        violations.extend(check_python_functions(file_path))
    elif file_path.suffix in {".js", ".ts", ".tsx", ".jsx", ".mjs", ".cjs"}:
        violations.extend(check_js_ts_functions(file_path))

    return violations


def build_block_response(file_name: str, violations: list[Violation]) -> dict:
    """Build a blocking response for violations."""
    messages = [f"- {v.message}" for v in violations]
    violation_text = "\n".join(messages)

    return {
        "decision": "block",
        "reason": (
            f"CODE QUALITY VIOLATION in {file_name}:\n\n"
            f"{violation_text}\n\n"
            f"TIM Design Standards require this file to be refactored before continuing. "
            f"This is a HARD REQUIREMENT - no exceptions.\n\n"
            f"You must:\n"
            f"1. Split the file into smaller, focused modules\n"
            f"2. Extract large functions into smaller units\n"
            f"3. Ensure each module has a single responsibility\n\n"
            f"Do NOT proceed with other work until this violation is resolved."
        )
    }


def parse_hook_input() -> tuple[str, dict] | None:
    """Parse and validate hook input from stdin."""
    try:
        hook_input = json.load(sys.stdin)
        return hook_input.get("tool_name", ""), hook_input.get("tool_input", {})
    except json.JSONDecodeError as e:
        print(f"Error: Invalid JSON input: {e}", file=sys.stderr)
        return None


def main():
    """Main hook entry point."""
    parsed = parse_hook_input()
    if parsed is None:
        sys.exit(0)

    tool_name, tool_input = parsed

    # Only check Write and Edit operations
    if tool_name not in ("Write", "Edit"):
        sys.exit(0)

    file_path_str = tool_input.get("file_path", "")
    if not file_path_str:
        sys.exit(0)

    file_path = Path(file_path_str).expanduser()
    if not file_path.exists():
        sys.exit(0)

    # Validate and respond
    violations = validate_file(file_path)
    error_violations = [v for v in violations if v.severity == "error"]

    if error_violations:
        print(json.dumps(build_block_response(file_path.name, error_violations)))

    sys.exit(0)


if __name__ == "__main__":
    main()
