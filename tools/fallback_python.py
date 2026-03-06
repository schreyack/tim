"""Python AST-based checks for universal fallback default detection."""

import ast
from pathlib import Path

from sot_common import default_name_pattern


def _is_literal(node: ast.expr) -> bool:
    """Check if node is a literal value (any constant, list, dict, tuple, set)."""
    if isinstance(node, ast.Constant):
        return True
    return isinstance(node, (ast.List, ast.Dict, ast.Tuple, ast.Set))


def _is_non_none_literal(node: ast.expr) -> bool:
    """Check if node is a literal value that isn't None."""
    if isinstance(node, ast.Constant) and node.value is not None:
        return True
    return isinstance(node, (ast.List, ast.Dict, ast.Tuple, ast.Set))


def _is_none_literal(node: ast.expr) -> bool:
    """Check if node is the None constant."""
    return isinstance(node, ast.Constant) and node.value is None


def _is_os_environ_get(node: ast.Call) -> bool:
    """Check if a Call node is os.environ.get(...)."""
    if not isinstance(node.func, ast.Attribute) or node.func.attr != "get":
        return False
    if not isinstance(node.func.value, ast.Attribute):
        return False
    inner = node.func.value
    return (
        inner.attr == "environ"
        and isinstance(inner.value, ast.Name)
        and inner.value.id == "os"
    )


def _is_os_getenv(node: ast.Call) -> bool:
    """Check if a Call node is os.getenv(...)."""
    if isinstance(node.func, ast.Attribute):
        return (
            node.func.attr == "getenv"
            and isinstance(node.func.value, ast.Name)
            and node.func.value.id == "os"
        )
    return False


class FallbackDefaultVisitor(ast.NodeVisitor):
    """AST visitor that detects all fallback default patterns in Python."""

    def __init__(self, filepath: str):
        self.filepath = filepath
        self.violations: list[str] = []

    def _add(self, lineno: int, msg: str) -> None:
        self.violations.append(f"{self.filepath}:{lineno}: {msg}")

    # -- Patterns 1-8: Call-based --

    def visit_Call(self, node: ast.Call) -> None:
        self._check_dict_get(node)
        self._check_getattr(node)
        self._check_dict_pop(node)
        self._check_setdefault(node)
        self._check_os_environ_get(node)
        self._check_os_getenv(node)
        self._check_next(node)
        self._check_max_min(node)
        self.generic_visit(node)

    def _check_dict_get(self, node: ast.Call) -> None:
        """Pattern 1/5: .get(key, default) — any object."""
        if not isinstance(node.func, ast.Attribute) or node.func.attr != "get":
            return
        if _is_os_environ_get(node):
            return
        if len(node.args) < 2:
            return
        fallback = node.args[1]
        if _is_none_literal(fallback):
            self._add(
                node.lineno,
                ".get() with explicit None default — remove unnecessary default",
            )
        elif _is_non_none_literal(fallback):
            self._add(node.lineno, ".get() with fallback default — fail loudly instead")
        elif (
            isinstance(fallback, ast.Name)
            and default_name_pattern().match(fallback.id)
        ):
            self._add(node.lineno, ".get() with DEFAULT_* fallback — fail loudly instead")

    def _check_getattr(self, node: ast.Call) -> None:
        """Pattern 2: getattr(obj, attr, default)."""
        if not (isinstance(node.func, ast.Name) and node.func.id == "getattr"):
            return
        if len(node.args) >= 3 and _is_literal(node.args[2]):
            self._add(
                node.lineno,
                "getattr() with fallback default — fail loudly instead",
            )

    def _check_dict_pop(self, node: ast.Call) -> None:
        """Pattern 3: .pop(key, default)."""
        if not isinstance(node.func, ast.Attribute) or node.func.attr != "pop":
            return
        if len(node.args) >= 2 and _is_literal(node.args[1]):
            self._add(
                node.lineno,
                ".pop() with fallback default — fail loudly instead",
            )

    def _check_setdefault(self, node: ast.Call) -> None:
        """Pattern 4: .setdefault(key, default) — any call."""
        if not isinstance(node.func, ast.Attribute) or node.func.attr != "setdefault":
            return
        self._add(
            node.lineno,
            ".setdefault() silently inserts defaults — fail loudly instead",
        )

    def _check_os_environ_get(self, node: ast.Call) -> None:
        """Pattern 5: os.environ.get(KEY, val)."""
        if not _is_os_environ_get(node):
            return
        if len(node.args) >= 2 and _is_literal(node.args[1]):
            self._add(
                node.lineno,
                "os.environ.get() with fallback default — fail loudly instead",
            )

    def _check_os_getenv(self, node: ast.Call) -> None:
        """Pattern 6: os.getenv(KEY, default)."""
        if not _is_os_getenv(node):
            return
        if len(node.args) >= 2 and _is_literal(node.args[1]):
            self._add(
                node.lineno,
                "os.getenv() with fallback default — fail loudly instead",
            )

    def _check_next(self, node: ast.Call) -> None:
        """Pattern 7: next(iterator, default)."""
        if not (isinstance(node.func, ast.Name) and node.func.id == "next"):
            return
        if len(node.args) >= 2 and _is_literal(node.args[1]):
            self._add(
                node.lineno,
                "next() with fallback default — fail loudly instead",
            )

    def _check_max_min(self, node: ast.Call) -> None:
        """Pattern 8: max/min with default= kwarg."""
        if not isinstance(node.func, ast.Name):
            return
        if node.func.id not in ("max", "min"):
            return
        for kw in node.keywords:
            if kw.arg == "default" and _is_literal(kw.value):
                self._add(
                    node.lineno,
                    f"{node.func.id}() with default= kwarg — fail loudly instead",
                )
                break

    # -- Pattern 9: value or <literal> --

    def visit_BoolOp(self, node: ast.BoolOp) -> None:
        if isinstance(node.op, ast.Or):
            for value in node.values[1:]:
                if _is_non_none_literal(value):
                    self._add(
                        node.lineno,
                        "'or <literal>' fallback — fail loudly instead",
                    )
                    break
                if (
                    isinstance(value, ast.Name)
                    and default_name_pattern().match(value.id)
                ):
                    self._add(
                        node.lineno,
                        "'or DEFAULT_*' fallback — fail loudly instead",
                    )
                    break
        self.generic_visit(node)

    # -- Pattern 10: try/except KeyError with literal fallback --

    def visit_Try(self, node: ast.Try) -> None:
        self._check_try_except_fallback(node)
        self.generic_visit(node)

    def _check_try_except_fallback(self, node: ast.Try) -> None:
        """Detect try: val = d[k] / except KeyError: val = literal."""
        target_name = self._try_subscript_target(node)
        if target_name is None:
            return
        caught = {"KeyError", "IndexError", "AttributeError"}
        for handler in node.handlers:
            if not self._handler_catches(handler, caught):
                continue
            if self._handler_assigns_literal(handler, target_name):
                self._add(
                    node.lineno,
                    "try/except with literal fallback — fail loudly instead",
                )

    @staticmethod
    def _try_subscript_target(node: ast.Try) -> str | None:
        """Return target name if try body is `name = obj[key]`, else None."""
        if len(node.body) != 1:
            return None
        stmt = node.body[0]
        if not isinstance(stmt, ast.Assign) or len(stmt.targets) != 1:
            return None
        if not isinstance(stmt.value, ast.Subscript):
            return None
        target = stmt.targets[0]
        if not isinstance(target, ast.Name):
            return None
        return target.id

    @staticmethod
    def _handler_assigns_literal(
        handler: ast.ExceptHandler, target_name: str,
    ) -> bool:
        """Check if handler body is a single `target_name = <literal>`."""
        if len(handler.body) != 1:
            return False
        stmt = handler.body[0]
        if not isinstance(stmt, ast.Assign) or len(stmt.targets) != 1:
            return False
        target = stmt.targets[0]
        if not isinstance(target, ast.Name) or target.id != target_name:
            return False
        return _is_literal(stmt.value)

    @staticmethod
    def _handler_catches(
        handler: ast.ExceptHandler, names: set[str],
    ) -> bool:
        """Check if handler catches any of the given exception names."""
        if handler.type is None:
            return True
        if isinstance(handler.type, ast.Name):
            return handler.type.id in names
        if isinstance(handler.type, ast.Tuple):
            return any(
                isinstance(elt, ast.Name) and elt.id in names
                for elt in handler.type.elts
            )
        return False

    # -- Pattern 11: x if cond else <literal> --

    def visit_IfExp(self, node: ast.IfExp) -> None:
        if _is_non_none_literal(node.orelse):
            self._add(
                node.lineno,
                "Ternary with literal fallback — fail loudly instead",
            )
        self.generic_visit(node)

    # -- Pattern 11: val := x or <literal> --

    def visit_NamedExpr(self, node: ast.NamedExpr) -> None:
        if isinstance(node.value, ast.BoolOp) and isinstance(node.value.op, ast.Or):
            for value in node.value.values[1:]:
                if _is_non_none_literal(value):
                    self._add(
                        node.lineno,
                        "Walrus with 'or <literal>' fallback — fail loudly instead",
                    )
                    break
        self.generic_visit(node)


def check_file(filepath: Path) -> list[str]:
    """Run AST-based fallback default checks on a Python file."""
    try:
        source = filepath.read_text()
        tree = ast.parse(source, filename=str(filepath))
    except (SyntaxError, OSError, UnicodeDecodeError):
        return []

    visitor = FallbackDefaultVisitor(str(filepath))
    visitor.visit(tree)
    return visitor.violations
