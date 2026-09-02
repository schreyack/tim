#!/usr/bin/env python3
"""
TIM Code Quality Checker

Enforces CLAUDE.md requirements:
- File size: 500 lines max
- Function size: 50 lines max
- Cyclomatic complexity: 10 max

Usage:
    python check-code-quality.py <directory> [--language python|typescript|native]
"""

import argparse
import ast
import re
import sys
from pathlib import Path


MAX_FILE_LINES = 500
MAX_FUNCTION_LINES = 50
MAX_COMPLEXITY = 10

PYTHON_SKIP_DIRS = {"__pycache__", ".venv", "venv", ".git", "lib", "node_modules"}
TS_SKIP_DIRS = {"node_modules", "dist", ".git", "lib"}
NATIVE_SKIP_DIRS = {".git", "lib", "build", ".build", "DerivedData", "node_modules"}

# C++/Swift source extensions. Function size & cyclomatic complexity for these
# are owned by clang-tidy / swiftlint (as ESLint owns TS complexity); here we
# enforce only the language-agnostic file-size limit.
NATIVE_SOURCE_EXTENSIONS = {".h", ".hpp", ".hh", ".cc", ".cpp", ".cxx", ".swift"}
# Browser sources. `.js` gets file size AND function length; `.css` gets file
# size only, there being no functions in it to measure.
WEB_SOURCE_EXTENSIONS = {".js", ".css"}
WEB_SKIP_DIRS = {"node_modules", "dist", ".git", "vendor"}


class PythonAnalyzer(ast.NodeVisitor):
    """Analyze Python files for function sizes and complexity."""

    def __init__(self, filepath: str):
        self.filepath = filepath
        self.violations: list[str] = []
        self.current_class: str | None = None

    def visit_ClassDef(self, node: ast.ClassDef) -> None:
        self.current_class = node.name
        self.generic_visit(node)
        self.current_class = None

    def visit_FunctionDef(self, node: ast.FunctionDef) -> None:
        self._check_function(node)
        self.generic_visit(node)

    def visit_AsyncFunctionDef(self, node: ast.AsyncFunctionDef) -> None:
        self._check_function(node)
        self.generic_visit(node)

    def _get_function_name(self, node: ast.FunctionDef | ast.AsyncFunctionDef) -> str:
        """Get fully qualified function name."""
        return f"{self.current_class}.{node.name}" if self.current_class else node.name

    def _check_function(self, node: ast.FunctionDef | ast.AsyncFunctionDef) -> None:
        self._check_function_length(node)
        self._check_function_complexity(node)

    def _check_function_length(self, node: ast.FunctionDef | ast.AsyncFunctionDef) -> None:
        if not node.body:
            return
        start_line = node.lineno
        end_line = max(self._get_end_line(n) for n in ast.walk(node))
        length = end_line - start_line + 1

        if length > MAX_FUNCTION_LINES:
            name = self._get_function_name(node)
            self.violations.append(
                f"{self.filepath}:{node.lineno}: Function '{name}' is {length} lines (max: {MAX_FUNCTION_LINES})"
            )

    def _check_function_complexity(self, node: ast.FunctionDef | ast.AsyncFunctionDef) -> None:
        complexity = self._calculate_complexity(node)
        if complexity > MAX_COMPLEXITY:
            name = self._get_function_name(node)
            self.violations.append(
                f"{self.filepath}:{node.lineno}: Function '{name}' has complexity {complexity} (max: {MAX_COMPLEXITY})"
            )

    def _get_end_line(self, node: ast.AST) -> int:
        """Get the end line of a node."""
        return getattr(node, "end_lineno", getattr(node, "lineno", 0))

    def _calculate_complexity(self, node: ast.AST) -> int:
        """Calculate cyclomatic complexity of a function."""
        complexity = 1
        complexity_types = (
            ast.If, ast.While, ast.For, ast.AsyncFor,
            ast.ExceptHandler, ast.With, ast.AsyncWith,
            ast.Assert, ast.comprehension, ast.IfExp,
        )

        for child in ast.walk(node):
            if isinstance(child, complexity_types):
                complexity += 1
            elif isinstance(child, ast.BoolOp):
                complexity += len(child.values) - 1

        return complexity


def check_file_size(filepath: Path) -> str | None:
    """Check if file exceeds maximum line count."""
    try:
        line_count = len(filepath.read_text().splitlines())
        if line_count > MAX_FILE_LINES:
            return f"{filepath}: File has {line_count} lines (max: {MAX_FILE_LINES})"
    except (OSError, UnicodeDecodeError):
        pass
    return None


def check_python_file(filepath: Path) -> list[str]:
    """Check a Python file for all quality issues."""
    violations: list[str] = []

    size_violation = check_file_size(filepath)
    if size_violation:
        violations.append(size_violation)

    try:
        source = filepath.read_text()
        tree = ast.parse(source, filename=str(filepath))
        analyzer = PythonAnalyzer(str(filepath))
        analyzer.visit(tree)
        violations.extend(analyzer.violations)
    except SyntaxError as e:
        violations.append(f"{filepath}: Syntax error - {e}")
    except (OSError, UnicodeDecodeError) as e:
        violations.append(f"{filepath}: Could not read file - {e}")

    return violations


def check_typescript_file(filepath: Path) -> list[str]:
    """Check a TypeScript file for size issues.

    Note: ESLint handles function complexity. We only check file size here.
    """
    violations: list[str] = []
    size_violation = check_file_size(filepath)
    if size_violation:
        violations.append(size_violation)
    return violations


def js_functions(lines: list[str]) -> list[tuple[int, int]]:
    """Every JavaScript function's (start line, length), by brace balance.

    A MODULE IIFE IS A SCOPE, NOT A FUNCTION. `(function () { ... })();`
    wraps a whole page module, and counting it reports the module as one
    300-line function -- which is what an earlier ad-hoc version of this
    reader did to a 407-line file. So an IIFE is stepped INTO and the
    functions inside it are measured instead.
    """
    opens = re.compile(
        r"(\bfunction\b[^(]*\([^)]*\)\s*\{)"
        r"|(=>\s*\{)"
        r"|(^\s*(?:async\s+)?[A-Za-z_$][\w$]*\s*\([^)]*\)\s*\{\s*$)"
    )
    out: list[tuple[int, int]] = []
    i = 0
    while i < len(lines):
        if not opens.search(lines[i]):
            i += 1
            continue
        depth, j, started = 0, i, False
        while j < len(lines):
            depth += lines[j].count("{") - lines[j].count("}")
            started = started or "{" in lines[j]
            if started and depth <= 0:
                break
            j += 1
        close = lines[j] if j < len(lines) else ""
        if lines[i].lstrip().startswith("(function") and ")(" in close:
            i += 1  # step INTO the wrapper, do not skip its body
            continue
        out.append((i + 1, j - i + 1))
        i = j + 1
    return out


def check_web_file(filepath: Path) -> list[str]:
    """Check a browser source: file size for both, function length for .js."""
    violations: list[str] = []
    size_violation = check_file_size(filepath)
    if size_violation:
        violations.append(size_violation)
    if filepath.suffix != ".js":
        return violations
    try:
        lines = filepath.read_text(encoding="utf-8").splitlines()
    except OSError as exc:
        return violations + [f"{filepath}: cannot read: {exc}"]
    for start, length in js_functions(lines):
        if length > MAX_FUNCTION_LINES:
            violations.append(
                f"{filepath}:{start}: Function is {length} lines "
                f"(max: {MAX_FUNCTION_LINES})"
            )
    return violations


def check_native_file(filepath: Path) -> list[str]:
    """Check a C++/Swift file for size issues.

    Note: clang-tidy / swiftlint handle function size and complexity. We only
    check file size here.
    """
    violations: list[str] = []
    size_violation = check_file_size(filepath)
    if size_violation:
        violations.append(size_violation)
    return violations


def should_skip_path(filepath: Path, skip_dirs: set[str]) -> bool:
    """Check if path should be skipped based on directory names."""
    return any(skip_dir in filepath.parts for skip_dir in skip_dirs)


def collect_python_violations(directory: Path) -> list[str]:
    """Collect violations from all Python files in directory."""
    violations: list[str] = []
    for filepath in directory.rglob("*.py"):
        if not should_skip_path(filepath, PYTHON_SKIP_DIRS):
            violations.extend(check_python_file(filepath))
    return violations


def collect_typescript_violations(directory: Path) -> list[str]:
    """Collect violations from all TypeScript files in directory."""
    violations: list[str] = []
    for ext in ("*.ts", "*.tsx"):
        for filepath in directory.rglob(ext):
            if not should_skip_path(filepath, TS_SKIP_DIRS):
                violations.extend(check_typescript_file(filepath))
    return violations


def collect_native_violations(directory: Path) -> list[str]:
    """Collect violations from a native project.

    Python files get the full AST check; C++/Swift files get file-size only.
    """
    violations: list[str] = []
    for filepath in directory.rglob("*.py"):
        if not should_skip_path(filepath, NATIVE_SKIP_DIRS):
            violations.extend(check_python_file(filepath))
    for ext in NATIVE_SOURCE_EXTENSIONS:
        for filepath in directory.rglob(f"*{ext}"):
            if not should_skip_path(filepath, NATIVE_SKIP_DIRS):
                violations.extend(check_native_file(filepath))
    return violations


def collect_web_violations(directory: Path) -> list[str]:
    """Collect violations from every browser source in a directory."""
    violations: list[str] = []
    for ext in WEB_SOURCE_EXTENSIONS:
        for filepath in directory.rglob(f"*{ext}"):
            if not should_skip_path(filepath, WEB_SKIP_DIRS):
                violations.extend(check_web_file(filepath))
    return violations


def report_violations(violations: list[str]) -> int:
    """Report violations and return exit code."""
    if not violations:
        return 0

    print("Code quality violations found:", file=sys.stderr)
    for violation in violations:
        print(f"  {violation}", file=sys.stderr)
    return 1


def main() -> int:
    parser = argparse.ArgumentParser(description="Check code quality standards")
    parser.add_argument("paths", nargs="+", help="Files or directories to check")
    parser.add_argument(
        "--language",
        choices=["python", "typescript", "native", "both", "web", "all"],
        default="both",
        help="Language to check",
    )
    args = parser.parse_args()

    violations: list[str] = []

    for path_str in args.paths:
        path = Path(path_str)
        if not path.exists():
            print(f"Error: '{path}' does not exist", file=sys.stderr)
            return 1

        if path.is_file():
            violations.extend(check_file(path, args.language))
        else:
            if args.language in ("python", "both", "all"):
                violations.extend(collect_python_violations(path))
            if args.language in ("typescript", "both", "all"):
                violations.extend(collect_typescript_violations(path))
            if args.language in ("native", "all"):
                violations.extend(collect_native_violations(path))
            if args.language in ("web", "all"):
                violations.extend(collect_web_violations(path))

    return report_violations(violations)


def check_file(path: Path, language: str) -> list[str]:
    """Dispatch a single file to the right checker based on suffix and language."""
    if path.suffix == ".py" and language in ("python", "native", "both"):
        return check_python_file(path)
    if path.suffix in (".ts", ".tsx") and language in ("typescript", "both"):
        return check_typescript_file(path)
    if path.suffix in NATIVE_SOURCE_EXTENSIONS and language in ("native", "all"):
        return check_native_file(path)
    if path.suffix in WEB_SOURCE_EXTENSIONS and language in ("web", "all"):
        return check_web_file(path)
    return []


if __name__ == "__main__":
    sys.exit(main())
