#!/usr/bin/env python3
"""Unit tests for cyclomatic complexity calculation."""

import ast
import tempfile
from pathlib import Path
import importlib.util

# Load the hyphenated module name using importlib
scripts_dir = Path(__file__).parent.parent / "scripts"
spec = importlib.util.spec_from_file_location(
    "code_quality_validator",
    scripts_dir / "code-quality-validator.py"
)
cqv = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cqv)
calculate_cyclomatic_complexity = cqv.calculate_cyclomatic_complexity
check_python_complexity = cqv.check_python_complexity


def get_function_node(code: str) -> ast.FunctionDef:
    """Parse code and return the first function definition."""
    tree = ast.parse(code)
    for node in ast.walk(tree):
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
            return node
    raise ValueError("No function found")


def test_complexity_no_branches():
    """Function with no branches has complexity 1."""
    code = "def simple(): return 42"
    assert calculate_cyclomatic_complexity(get_function_node(code)) == 1


def test_complexity_single_if():
    """Single if statement adds 1."""
    code = "def f():\n  if x: pass"
    assert calculate_cyclomatic_complexity(get_function_node(code)) == 2


def test_complexity_if_elif_else():
    """if/elif/else: if=1, elif=1, else=0 (not a branch point)."""
    code = "def f():\n  if x: pass\n  elif y: pass\n  else: pass"
    assert calculate_cyclomatic_complexity(get_function_node(code)) == 3


def test_complexity_nested_loops():
    """Nested for loops each add 1."""
    code = "def f():\n  for i in x:\n    for j in y: pass"
    assert calculate_cyclomatic_complexity(get_function_node(code)) == 3


def test_complexity_boolean_operators():
    """and/or each add 1."""
    code = "def f(): return a and b or c"
    assert calculate_cyclomatic_complexity(get_function_node(code)) == 3


def test_complexity_comprehension_with_if():
    """List comprehension with if clause adds 1."""
    code = "def f(): return [x for x in y if z]"
    assert calculate_cyclomatic_complexity(get_function_node(code)) == 2


def test_complexity_ternary():
    """Ternary expression adds 1."""
    code = "def f(): return x if condition else y"
    assert calculate_cyclomatic_complexity(get_function_node(code)) == 2


def test_complexity_while_loop():
    """While loop adds 1."""
    code = "def f():\n  while x: pass"
    assert calculate_cyclomatic_complexity(get_function_node(code)) == 2


def test_complexity_try_except():
    """Except handler adds 1."""
    code = "def f():\n  try: pass\n  except: pass"
    assert calculate_cyclomatic_complexity(get_function_node(code)) == 2


def test_complexity_with_statement():
    """With statement adds 1."""
    code = "def f():\n  with x: pass"
    assert calculate_cyclomatic_complexity(get_function_node(code)) == 2


def test_complexity_assert():
    """Assert statement adds 1."""
    code = "def f():\n  assert x"
    assert calculate_cyclomatic_complexity(get_function_node(code)) == 2


def test_complexity_exceeds_limit():
    """Function with complexity 12 returns violation."""
    code = "def f():\n" + "\n".join(f"  if x{i}: pass" for i in range(11))
    # Write to temp file since check_python_complexity reads from file
    with tempfile.NamedTemporaryFile(mode='w', suffix='.py', delete=False) as f:
        f.write(code)
        f.flush()
        violations = check_python_complexity(Path(f.name))
    assert len(violations) == 1
    assert "complexity" in violations[0].rule


def test_complexity_within_limit():
    """Function with complexity 10 returns no violation."""
    code = "def f():\n" + "\n".join(f"  if x{i}: pass" for i in range(9))
    with tempfile.NamedTemporaryFile(mode='w', suffix='.py', delete=False) as f:
        f.write(code)
        f.flush()
        violations = check_python_complexity(Path(f.name))
    assert len(violations) == 0


if __name__ == "__main__":
    import sys

    tests = [
        test_complexity_no_branches,
        test_complexity_single_if,
        test_complexity_if_elif_else,
        test_complexity_nested_loops,
        test_complexity_boolean_operators,
        test_complexity_comprehension_with_if,
        test_complexity_ternary,
        test_complexity_while_loop,
        test_complexity_try_except,
        test_complexity_with_statement,
        test_complexity_assert,
        test_complexity_exceeds_limit,
        test_complexity_within_limit,
    ]

    passed = 0
    failed = 0
    for test in tests:
        try:
            test()
            print(f"PASS: {test.__name__}")
            passed += 1
        except AssertionError as e:
            print(f"FAIL: {test.__name__} - {e}")
            failed += 1
        except Exception as e:
            print(f"ERROR: {test.__name__} - {e}")
            failed += 1

    print(f"\nResults: {passed} passed, {failed} failed")
    sys.exit(0 if failed == 0 else 1)
