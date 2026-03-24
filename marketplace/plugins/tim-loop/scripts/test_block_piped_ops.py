"""Tests for block_piped_ops.py piped ops command detection."""

import unittest

from block_piped_ops import find_ops_invocation, has_pipe_in_simple_command


class TestBlockPipedOps(unittest.TestCase):
    """Verify piped ops.sh commands are blocked and safe commands are allowed."""

    def assert_blocked(
        self, command: str, alias_name: str | None = "myapp",
    ) -> None:
        ops_end = find_ops_invocation(command, alias_name)
        self.assertIsNotNone(ops_end, f"Expected ops invocation found: {command}")
        assert ops_end is not None  # narrow type for mypy
        piped = has_pipe_in_simple_command(command[ops_end:])
        self.assertTrue(piped, f"Expected BLOCKED but no pipe detected: {command}")

    def assert_allowed(
        self, command: str, alias_name: str | None = "myapp",
    ) -> None:
        ops_end = find_ops_invocation(command, alias_name)
        if ops_end is None:
            return  # not an ops invocation at all — allowed
        piped = has_pipe_in_simple_command(command[ops_end:])
        self.assertFalse(piped, f"Expected ALLOWED but pipe detected: {command}")

    # --- Blocked: direct ops.sh piped ---

    def test_blocked_when_ops_sh_ship_piped_to_tail_then_blocked(self) -> None:
        self.assert_blocked("ops.sh --config foo --env dev ship | tail -f")

    def test_blocked_when_ops_sh_build_stderr_piped_then_blocked(self) -> None:
        self.assert_blocked("ops.sh --env dev build all 2>&1 | grep error")

    def test_blocked_when_ops_sh_path_pipefail_piped_then_blocked(self) -> None:
        self.assert_blocked("/path/to/ops.sh --env prod deploy |& tee log.txt")

    # --- Blocked: alias piped ---

    def test_blocked_when_alias_ship_piped_to_tail_then_blocked(self) -> None:
        self.assert_blocked("myapp --env dev ship | tail")

    def test_blocked_when_alias_logs_piped_to_head_then_blocked(self) -> None:
        self.assert_blocked("myapp --env dev logs api | head -100")

    def test_blocked_when_alias_deploy_stderr_piped_then_blocked(self) -> None:
        self.assert_blocked("myapp --env prod deploy 2>&1 | grep error")

    # --- Blocked: middle of pipeline ---

    def test_blocked_when_alias_in_middle_of_pipeline_then_blocked(self) -> None:
        self.assert_blocked("echo y | myapp --env dev ship | tail")

    # --- Blocked: --env heuristic piped ---

    def test_blocked_when_unknown_alias_env_heuristic_piped_then_blocked(self) -> None:
        self.assert_blocked("fooapp --env dev ship | grep done", alias_name=None)

    # --- Allowed: no pipe ---

    def test_allowed_when_alias_no_pipe_then_allowed(self) -> None:
        self.assert_allowed("myapp --env dev ship")

    def test_allowed_when_ops_sh_no_pipe_then_allowed(self) -> None:
        self.assert_allowed("ops.sh --config foo --env dev build all")

    # --- Allowed: input pipe only ---

    def test_allowed_when_input_pipe_only_then_allowed(self) -> None:
        self.assert_allowed("echo y | myapp --env dev restart api")

    # --- Allowed: || not a pipe ---

    def test_allowed_when_or_operator_not_pipe_then_allowed(self) -> None:
        self.assert_allowed("myapp --env dev ship || echo failed")

    # --- Allowed: chained — pipe in later command ---

    def test_allowed_when_and_chain_pipe_in_later_cmd_then_allowed(self) -> None:
        self.assert_allowed("myapp --env dev ship && echo done | grep done")

    def test_allowed_when_semicolon_pipe_in_later_cmd_then_allowed(self) -> None:
        self.assert_allowed("myapp --env dev ship; cat log | grep error")

    def test_allowed_when_or_chain_pipe_in_later_cmd_then_allowed(self) -> None:
        self.assert_allowed("myapp --env dev ship || echo fail | tee log")

    # --- Allowed: pipe inside quotes ---

    def test_allowed_when_pipe_inside_quotes_then_allowed(self) -> None:
        self.assert_allowed("myapp --env dev exec api 'echo \"a|b\"'")

    # --- Allowed: not ops.sh ---

    def test_allowed_when_cat_pipe_grep_not_ops_then_allowed(self) -> None:
        self.assert_allowed("cat file | grep pattern")

    def test_allowed_when_docker_env_not_ops_then_allowed(self) -> None:
        self.assert_allowed("docker --env foo run image")

    # --- Allowed: denylist commands with --env ---

    def test_allowed_when_kubectl_env_piped_then_allowed(self) -> None:
        self.assert_allowed("kubectl --env dev get pods | grep running", alias_name=None)

    def test_allowed_when_terraform_env_piped_then_allowed(self) -> None:
        self.assert_allowed("terraform --env prod apply | tee log", alias_name=None)


if __name__ == "__main__":
    unittest.main()
