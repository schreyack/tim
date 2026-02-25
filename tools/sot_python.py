"""Python AST-based checks for settings SOT enforcement."""

import ast
from pathlib import Path

from sot_common import (
    CONFIG_VARIABLE_NAMES,
    default_name_pattern,
    is_settings_name,
)

CONST_NAME_RE = default_name_pattern()


def _is_non_none_literal(node: ast.expr) -> bool:
    """Check if node is a literal constant that isn't None."""
    if isinstance(node, ast.Constant) and node.value is not None:
        return True
    return isinstance(node, (ast.List, ast.Dict, ast.Tuple, ast.Set))


def _is_none_check(node: ast.expr) -> bool:
    """Check if a node is comparing something to None via is/is not."""
    if not isinstance(node, ast.Compare):
        return False
    return any(
        isinstance(op, (ast.Is, ast.IsNot))
        and isinstance(comp, ast.Constant)
        and comp.value is None
        for op, comp in zip(node.ops, node.comparators)
    )


def _get_name(node: ast.expr) -> str | None:
    """Extract a simple name from a Name or Attribute node."""
    if isinstance(node, ast.Name):
        return node.id
    if isinstance(node, ast.Attribute):
        return node.attr
    return None


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


def _has_nonempty_string_fallback(node: ast.Call) -> bool:
    """Check if a call has a second arg that is a non-empty string literal."""
    if len(node.args) < 2:
        return False
    fb = node.args[1]
    return isinstance(fb, ast.Constant) and isinstance(fb.value, str) and bool(fb.value)


class SettingsSOTVisitor(ast.NodeVisitor):
    """AST visitor that detects hardcoded settings patterns in Python."""

    def __init__(self, filepath: str, tier: str = "block"):
        self.filepath = filepath
        self.tier = tier
        self.violations: list[str] = []
        self._module_level = True

    def _add(self, lineno: int, msg: str) -> None:
        self.violations.append(f"{self.filepath}:{lineno}: {msg}")

    def visit_Module(self, node: ast.Module) -> None:
        for child in node.body:
            self._module_level = True
            self.visit(child)

    # -- Rule 1 (Tier 1): DEFAULT_* constants at module level --

    def visit_Assign(self, node: ast.Assign) -> None:
        if self._module_level:
            for target in node.targets:
                name = _get_name(target)
                if name and CONST_NAME_RE.match(name):
                    self._add(node.lineno, f"DEFAULT constant '{name}' — use settings SOT")
        self._module_level = False
        self.generic_visit(node)

    def visit_AnnAssign(self, node: ast.AnnAssign) -> None:
        if self._module_level and node.value is not None:
            name = _get_name(node.target)
            if name and CONST_NAME_RE.match(name):
                self._add(node.lineno, f"DEFAULT constant '{name}' — use settings SOT")
        self._module_level = False
        self.generic_visit(node)

    # -- Rules 3-5, 9-10: Call-based patterns --

    def visit_Call(self, node: ast.Call) -> None:
        self._module_level = False
        self._check_dict_get(node)
        self._check_getattr(node)
        self._check_os_environ_get(node)
        self._check_setdefault(node)
        self.generic_visit(node)

    def _check_dict_get(self, node: ast.Call) -> None:
        """Rules 3/9 (Tier 2): x.get("key", fallback) — only on settings-named objects."""
        if self.tier != "warn":
            return
        if not isinstance(node.func, ast.Attribute) or node.func.attr != "get":
            return
        if len(node.args) >= 2 and _is_non_none_literal(node.args[1]):
            obj_name = _get_name(node.func.value)
            if obj_name and is_settings_name(obj_name):
                self._add(node.lineno, ".get() with hardcoded fallback — use settings SOT")

    def _check_getattr(self, node: ast.Call) -> None:
        """Rule 4 (Tier 2): getattr(obj, "attr", fallback) — only on settings-named first arg."""
        if self.tier != "warn":
            return
        if not (isinstance(node.func, ast.Name) and node.func.id == "getattr"):
            return
        if len(node.args) >= 3 and _is_non_none_literal(node.args[2]):
            obj_name = _get_name(node.args[0])
            if obj_name and is_settings_name(obj_name):
                self._add(node.lineno, "getattr() with hardcoded fallback — use settings SOT")

    def _check_os_environ_get(self, node: ast.Call) -> None:
        """Rule 5 (Tier 1): os.environ.get("KEY", "default") with non-empty string."""
        if _is_os_environ_get(node) and _has_nonempty_string_fallback(node):
            self._add(node.lineno, "os.environ.get() with hardcoded default — use settings SOT")

    def _check_setdefault(self, node: ast.Call) -> None:
        """Rule 10 (Tier 2): dict.setdefault("key", literal) — only on settings-named objects."""
        if self.tier != "warn":
            return
        if not isinstance(node.func, ast.Attribute) or node.func.attr != "setdefault":
            return
        if len(node.args) >= 2 and _is_non_none_literal(node.args[1]):
            obj_name = _get_name(node.func.value)
            if obj_name and is_settings_name(obj_name):
                self._add(node.lineno, ".setdefault() with hardcoded default — use settings SOT")

    # -- Rule 6 (Tier 2): x or <literal> — only on settings-named left operand --

    def visit_BoolOp(self, node: ast.BoolOp) -> None:
        self._module_level = False
        if self.tier == "warn" and isinstance(node.op, ast.Or):
            first_name = _get_name(node.values[0]) if node.values else None
            if first_name and is_settings_name(first_name):
                for value in node.values[1:]:
                    if _is_non_none_literal(value):
                        self._add(node.lineno, "'or <literal>' fallback — use settings SOT")
                        break
        self.generic_visit(node)

    # -- Rule 7 (Tier 2): x if x else <literal> — only when orelse references settings-named --

    def visit_IfExp(self, node: ast.IfExp) -> None:
        self._module_level = False
        if self.tier == "warn" and _is_non_none_literal(node.orelse):
            orelse_name = _get_name(node.orelse)
            test_name = _get_name(node.test) if isinstance(node.test, (ast.Name, ast.Attribute)) else None
            body_name = _get_name(node.body) if isinstance(node.body, (ast.Name, ast.Attribute)) else None
            # Fire if test or body references a settings-named variable
            if (test_name and is_settings_name(test_name)) or (body_name and is_settings_name(body_name)):
                self._add(node.lineno, "Ternary with hardcoded fallback — use settings SOT")
        self.generic_visit(node)

    # -- Rule 11 (Tier 2): val := x or default — only on settings-named target --

    def visit_NamedExpr(self, node: ast.NamedExpr) -> None:
        self._module_level = False
        if self.tier != "warn":
            self.generic_visit(node)
            return
        if isinstance(node.value, ast.BoolOp) and isinstance(node.value.op, ast.Or):
            target_name = _get_name(node.target)
            if target_name and is_settings_name(target_name):
                for value in node.value.values[1:]:
                    if _is_non_none_literal(value):
                        self._add(node.lineno, "Walrus with 'or <literal>' fallback — use settings SOT")
                        break
        self.generic_visit(node)

    # -- Rule 12 (Tier 2): except block with hardcoded config fallback --

    def visit_ExceptHandler(self, node: ast.ExceptHandler) -> None:
        self._module_level = False
        if self.tier != "warn":
            self.generic_visit(node)
            return
        for child in ast.walk(node):
            if not isinstance(child, ast.Assign):
                continue
            for target in child.targets:
                name = _get_name(target)
                if name and name.lower() in CONFIG_VARIABLE_NAMES and isinstance(child.value, ast.Constant):
                    self._add(
                        child.lineno,
                        f"Hardcoded fallback for '{name}' in except block — use settings SOT",
                    )
        self.generic_visit(node)

    # -- Traversal for non-rule nodes --

    def visit_If(self, node: ast.If) -> None:
        self._module_level = False
        self.generic_visit(node)

    def visit_FunctionDef(self, node: ast.FunctionDef) -> None:
        self._module_level = False
        self.generic_visit(node)

    def visit_AsyncFunctionDef(self, node: ast.AsyncFunctionDef) -> None:
        self._module_level = False
        self.generic_visit(node)


def check_python_file(filepath: Path, tier: str = "block") -> list[str]:
    """Run AST-based checks on a Python file."""
    try:
        source = filepath.read_text()
        tree = ast.parse(source, filename=str(filepath))
    except (SyntaxError, OSError, UnicodeDecodeError):
        return []

    visitor = SettingsSOTVisitor(str(filepath), tier=tier)
    visitor.visit(tree)
    return visitor.violations
