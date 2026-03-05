"""Tests for block_precommit_tools.py pre-commit tool blocking patterns."""

import unittest

from block_precommit_tools import BLOCKED_PATTERNS


class TestBlockPrecommitTools(unittest.TestCase):
    """Verify pre-commit tools are blocked at command position and allowed as arguments."""

    def assert_blocked(self, command: str) -> None:
        matched = any(p.search(command) for p in BLOCKED_PATTERNS)
        self.assertTrue(matched, f"Expected BLOCKED but no pattern matched: {command}")

    def assert_allowed(self, command: str) -> None:
        for pattern in BLOCKED_PATTERNS:
            self.assertIsNone(
                pattern.search(command),
                f"Expected ALLOWED but pattern matched: {command}",
            )

    # --- Each of 14 blocked tools at command position ---

    def test_ruff_direct(self) -> None:
        self.assert_blocked("ruff check .")

    def test_prettier_direct(self) -> None:
        self.assert_blocked("prettier --write .")

    def test_eslint_direct(self) -> None:
        self.assert_blocked("eslint src/")

    def test_mypy_direct(self) -> None:
        self.assert_blocked("mypy .")

    def test_pyright_direct(self) -> None:
        self.assert_blocked("pyright .")

    def test_tsc_direct(self) -> None:
        self.assert_blocked("tsc --noEmit")

    def test_black_direct(self) -> None:
        self.assert_blocked("black .")

    def test_isort_direct(self) -> None:
        self.assert_blocked("isort .")

    def test_autopep8_direct(self) -> None:
        self.assert_blocked("autopep8 --in-place f.py")

    def test_flake8_direct(self) -> None:
        self.assert_blocked("flake8 .")

    def test_pylint_direct(self) -> None:
        self.assert_blocked("pylint src/")

    def test_biome_direct(self) -> None:
        self.assert_blocked("biome check .")

    def test_stylelint_direct(self) -> None:
        self.assert_blocked('stylelint "*.css"')

    def test_bandit_direct(self) -> None:
        self.assert_blocked("bandit -r src/")

    # --- Detection method 1: Path-prefixed ---

    def test_node_modules_path(self) -> None:
        self.assert_blocked("./node_modules/.bin/eslint src/")

    def test_venv_path(self) -> None:
        self.assert_blocked(".venv/bin/ruff check .")

    def test_absolute_path(self) -> None:
        self.assert_blocked("/usr/local/bin/mypy .")

    # --- Detection method 2: Node package runners ---

    def test_npx_prettier(self) -> None:
        self.assert_blocked("npx prettier --write .")

    def test_bunx_eslint(self) -> None:
        self.assert_blocked("bunx eslint .")

    def test_pnpx_biome(self) -> None:
        self.assert_blocked("pnpx biome check .")

    # --- Detection method 3: Python package runners ---

    def test_pipx_run_ruff(self) -> None:
        self.assert_blocked("pipx run ruff check .")

    def test_uv_run_mypy(self) -> None:
        self.assert_blocked("uv run mypy .")

    def test_poetry_run_black(self) -> None:
        self.assert_blocked("poetry run black .")

    def test_pdm_run_isort(self) -> None:
        self.assert_blocked("pdm run isort .")

    # --- Detection method 4: Python -m ---

    def test_python3_m_mypy(self) -> None:
        self.assert_blocked("python3 -m mypy .")

    def test_python_m_black(self) -> None:
        self.assert_blocked("python -m black .")

    def test_venv_python_m_pylint(self) -> None:
        self.assert_blocked(".venv/bin/python3 -m pylint src/")

    # --- Detection method 5: Shell prefixes ---

    def test_env_ruff(self) -> None:
        self.assert_blocked("env ruff check .")

    def test_sudo_prettier(self) -> None:
        self.assert_blocked("sudo prettier --write .")

    def test_env_with_var_ruff(self) -> None:
        self.assert_blocked("env FOO=bar ruff check .")

    # --- Multi-command edge cases ---

    def test_after_and_and(self) -> None:
        self.assert_blocked("cd src && ruff check .")

    def test_after_pipe(self) -> None:
        self.assert_blocked("echo foo | eslint --stdin")

    def test_install_then_run(self) -> None:
        self.assert_blocked("pip install ruff && ruff check .")

    def test_after_semicolon(self) -> None:
        self.assert_blocked("cd src; ruff check .")

    def test_after_or(self) -> None:
        self.assert_blocked("test -f x || ruff check .")

    # --- Version/help blocked ---

    def test_version_flag(self) -> None:
        self.assert_blocked("ruff --version")

    def test_help_flag(self) -> None:
        self.assert_blocked("eslint --help")

    # --- False positives: must allow (tool name not at command position) ---

    def test_cat_ruff_toml(self) -> None:
        self.assert_allowed("cat ruff.toml")

    def test_echo_ruff(self) -> None:
        self.assert_allowed('echo "ruff"')

    def test_grep_ruff(self) -> None:
        self.assert_allowed("grep ruff pyproject.toml")

    def test_vim_ruff_toml(self) -> None:
        self.assert_allowed("vim ruff.toml")

    def test_which_ruff(self) -> None:
        self.assert_allowed("which ruff")

    def test_pip_show_ruff(self) -> None:
        self.assert_allowed("pip show ruff")

    def test_pip_install_ruff(self) -> None:
        self.assert_allowed("pip install ruff")

    def test_npm_add_prettier(self) -> None:
        self.assert_allowed("npm add prettier")

    def test_uv_add_ruff(self) -> None:
        self.assert_allowed("uv add ruff")

    def test_pip_install_requirements(self) -> None:
        self.assert_allowed("pip install -r requirements.txt")

    def test_precommit_run_mypy(self) -> None:
        self.assert_allowed("pre-commit run mypy")

    def test_precommit_run_ruff_check(self) -> None:
        self.assert_allowed("pre-commit run ruff-check --all-files")

    def test_precommit_run_all_files(self) -> None:
        self.assert_allowed("pre-commit run --all-files")

    def test_git_commit_with_ruff_in_message(self) -> None:
        self.assert_allowed('git commit -m "fix ruff issues"')


if __name__ == "__main__":
    unittest.main()
