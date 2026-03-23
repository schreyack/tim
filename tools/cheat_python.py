"""
AST-based cheat detection for Python files.

Detects patterns that AI agents use to bypass type safety and error handling:
- Empty except handlers (pass, ..., continue)
- Broad exception catches (Exception, BaseException)
- Log-and-swallow (log in except without re-raise)
- typing.cast() usage
- defaultdict() usage
"""

import ast
import sys
from pathlib import Path


LOG_METHODS = {
    "log", "warning", "error", "exception",
    "info", "debug", "critical", "warn",
}


class CheatDetectorVisitor(ast.NodeVisitor):
    """Visits AST nodes to detect cheat patterns."""

    def __init__(self, filepath: str) -> None:
        self.filepath = filepath
        self.violations: list[str] = []
        self._cast_names: set[str] = set()
        self._defaultdict_names: set[str] = set()
        self._cast_modules: set[str] = set()
        self._defaultdict_modules: set[str] = set()
        self._loop_depth: int = 0

    def visit_ImportFrom(self, node: ast.ImportFrom) -> None:
        if node.module in ("typing", "typing_extensions"):
            for alias in node.names:
                if alias.name == "cast":
                    self._cast_names.add(alias.asname or alias.name)
        if node.module == "collections":
            for alias in node.names:
                if alias.name == "defaultdict":
                    self._defaultdict_names.add(
                        alias.asname or alias.name
                    )
        self.generic_visit(node)

    def visit_Import(self, node: ast.Import) -> None:
        for alias in node.names:
            bound = alias.asname or alias.name
            if alias.name in ("typing", "typing_extensions"):
                self._cast_modules.add(bound)
            if alias.name == "collections":
                self._defaultdict_modules.add(bound)
        self.generic_visit(node)

    def visit_Call(self, node: ast.Call) -> None:
        self._check_cast_call(node)
        self._check_defaultdict_call(node)
        self.generic_visit(node)

    def _check_cast_call(self, node: ast.Call) -> None:
        func = node.func
        if isinstance(func, ast.Name) and func.id in self._cast_names:
            self._add(node.lineno, "typing.cast() bypasses type safety")
        elif isinstance(func, ast.Attribute) and func.attr == "cast":
            if (
                isinstance(func.value, ast.Name)
                and func.value.id in self._cast_modules
            ):
                self._add(node.lineno, "typing.cast() bypasses type safety")

    def _check_defaultdict_call(self, node: ast.Call) -> None:
        func = node.func
        if isinstance(func, ast.Name) and func.id in self._defaultdict_names:
            self._add(node.lineno, "defaultdict() silently hides missing keys")
        elif isinstance(func, ast.Attribute) and func.attr == "defaultdict":
            if (
                isinstance(func.value, ast.Name)
                and func.value.id in self._defaultdict_modules
            ):
                self._add(
                    node.lineno, "defaultdict() silently hides missing keys"
                )

    def visit_For(self, node: ast.For) -> None:
        self._loop_depth += 1
        self.generic_visit(node)
        self._loop_depth -= 1

    def visit_While(self, node: ast.While) -> None:
        self._loop_depth += 1
        self.generic_visit(node)
        self._loop_depth -= 1

    def visit_ExceptHandler(self, node: ast.ExceptHandler) -> None:
        self._check_empty_except(node)
        self._check_broad_exception(node)
        self._check_log_and_swallow(node)
        self.generic_visit(node)

    def _check_empty_except(self, node: ast.ExceptHandler) -> None:
        if not node.body:
            return
        if len(node.body) == 1:
            stmt = node.body[0]
            if isinstance(stmt, ast.Pass):
                self._add(node.lineno, "Empty except handler (pass)")
                return
            if isinstance(stmt, ast.Continue):
                self._add(node.lineno, "Empty except handler (continue)")
                return
            if isinstance(stmt, ast.Expr) and isinstance(
                stmt.value, ast.Constant
            ):
                if stmt.value.value is ...:
                    self._add(node.lineno, "Empty except handler (Ellipsis)")

    def _check_broad_exception(self, node: ast.ExceptHandler) -> None:
        if node.type is None:
            return
        broad = {"Exception", "BaseException"}
        names = _extract_exception_names(node.type)
        for name in names:
            if name in broad:
                self._add(node.lineno, f"Broad exception catch: {name}")

    def _check_log_and_swallow(self, node: ast.ExceptHandler) -> None:
        if not _has_log_call(node):
            return
        if _has_reraise(node):
            return
        if self._loop_depth > 0 and _is_batch_handler(node):
            return
        self._add(node.lineno, "Log-and-swallow: logs error without re-raise")

    def _add(self, lineno: int, message: str) -> None:
        self.violations.append(f"{self.filepath}:{lineno}: {message}")


def _has_log_call(node: ast.ExceptHandler) -> bool:
    """Check if an except handler body contains a logging call."""
    for child in node.body:
        if not isinstance(child, ast.Expr):
            continue
        if not isinstance(child.value, ast.Call):
            continue
        func = child.value.func
        if isinstance(func, ast.Attribute) and func.attr in LOG_METHODS:
            return True
    return False


def _has_reraise(node: ast.ExceptHandler) -> bool:
    """Check if an except handler contains a raise statement."""
    return any(isinstance(d, ast.Raise) for d in ast.walk(node))


def _is_batch_handler(node: ast.ExceptHandler) -> bool:
    """Detect catch-and-continue in loops: explicit continue or counter increment."""
    for child in node.body:
        if isinstance(child, ast.Continue):
            return True
        if isinstance(child, ast.AugAssign) and isinstance(
            child.op, ast.Add
        ):
            return True
    return False


def _extract_exception_names(node: ast.expr) -> list[str]:
    """Extract exception class names from an except clause type node."""
    if isinstance(node, ast.Name):
        return [node.id]
    if isinstance(node, ast.Attribute):
        return [node.attr]
    if isinstance(node, ast.Tuple):
        names: list[str] = []
        for elt in node.elts:
            names.extend(_extract_exception_names(elt))
        return names
    return []


def check_file(filepath: Path) -> list[str]:
    """Check a Python file for cheat patterns. Returns violation strings."""
    try:
        source = filepath.read_text()
    except (OSError, UnicodeDecodeError):
        return []

    try:
        tree = ast.parse(source, filename=str(filepath))
    except SyntaxError:
        return []

    visitor = CheatDetectorVisitor(str(filepath))
    visitor.visit(tree)
    return visitor.violations


if __name__ == "__main__":
    all_violations: list[str] = []
    for arg in sys.argv[1:]:
        all_violations.extend(check_file(Path(arg)))
    for v in all_violations:
        print(v, file=sys.stderr)
    sys.exit(1 if all_violations else 0)
