"""Tests for block_bypass_flags.py destructive git command patterns."""

import unittest

from block_bypass_flags import BYPASS_PATTERNS


class TestBlockBypassFlags(unittest.TestCase):
    """Verify destructive git commands are blocked and safe commands are allowed."""

    def assert_blocked(self, command: str) -> None:
        matched = any(pattern.search(command) for pattern, _ in BYPASS_PATTERNS)
        self.assertTrue(matched, f"Expected BLOCKED but no pattern matched: {command}")

    def assert_allowed(self, command: str) -> None:
        for pattern, message in BYPASS_PATTERNS:
            self.assertIsNone(
                pattern.search(command),
                f"Expected ALLOWED but matched by '{message}': {command}",
            )

    # --- git stash blocked ---

    def test_git_stash_when_bare_command_then_denied(self) -> None:
        self.assert_blocked("git stash")

    def test_git_stash_when_push_subcommand_then_denied(self) -> None:
        self.assert_blocked("git stash push")

    def test_git_stash_when_pop_subcommand_then_denied(self) -> None:
        self.assert_blocked("git stash pop")

    def test_git_stash_when_drop_subcommand_then_denied(self) -> None:
        self.assert_blocked("git stash drop")

    def test_git_stash_when_apply_subcommand_then_denied(self) -> None:
        self.assert_blocked("git stash apply")

    # --- git reset blocked ---

    def test_git_reset_when_hard_flag_then_denied(self) -> None:
        self.assert_blocked("git reset --hard")

    def test_git_reset_when_hard_with_ref_then_denied(self) -> None:
        self.assert_blocked("git reset --hard HEAD~1")

    def test_git_reset_when_hard_flag_after_ref_then_denied(self) -> None:
        self.assert_blocked("git reset HEAD~1 --hard")

    # --- git clean blocked ---

    def test_git_clean_when_force_flag_then_denied(self) -> None:
        self.assert_blocked("git clean -f")

    def test_git_clean_when_combined_flags_then_denied(self) -> None:
        self.assert_blocked("git clean -fd")

    def test_git_clean_when_xdf_flags_then_denied(self) -> None:
        self.assert_blocked("git clean -xdf")

    def test_git_clean_when_long_force_then_denied(self) -> None:
        self.assert_blocked("git clean --force")

    # --- git checkout . blocked ---

    def test_git_checkout_when_dot_then_denied(self) -> None:
        self.assert_blocked("git checkout .")

    def test_git_checkout_when_doubledash_dot_then_denied(self) -> None:
        self.assert_blocked("git checkout -- .")

    def test_git_checkout_when_ref_dot_then_denied(self) -> None:
        self.assert_blocked("git checkout main -- .")

    def test_git_checkout_when_head_dot_then_denied(self) -> None:
        self.assert_blocked("git checkout HEAD -- .")

    def test_git_checkout_when_hash_dot_then_denied(self) -> None:
        self.assert_blocked("git checkout abc123 -- .")

    def test_git_checkout_when_remote_dot_then_denied(self) -> None:
        self.assert_blocked("git checkout origin/main -- .")

    def test_git_checkout_when_tag_dot_then_denied(self) -> None:
        self.assert_blocked("git checkout v1.0.0 -- .")

    def test_git_checkout_when_ref_dot_piped_then_denied(self) -> None:
        self.assert_blocked("git checkout main -- . 2>/dev/null && npm test")

    # --- git restore . blocked ---

    def test_git_restore_when_dot_then_denied(self) -> None:
        self.assert_blocked("git restore .")

    def test_git_restore_when_staged_dot_then_denied(self) -> None:
        self.assert_blocked("git restore --staged .")

    def test_git_restore_when_source_head_dot_then_denied(self) -> None:
        self.assert_blocked("git restore --source=HEAD .")

    # --- git push --force blocked ---

    def test_git_push_when_force_then_denied(self) -> None:
        self.assert_blocked("git push --force")

    def test_git_push_when_short_force_then_denied(self) -> None:
        self.assert_blocked("git push -f")

    def test_git_push_when_force_origin_main_then_denied(self) -> None:
        self.assert_blocked("git push --force origin main")

    # --- git branch -D blocked ---

    def test_git_branch_when_uppercase_D_then_denied(self) -> None:
        self.assert_blocked("git branch -D feature")

    # --- git checkout --force blocked ---

    def test_git_checkout_when_force_flag_then_denied(self) -> None:
        self.assert_blocked("git checkout -f main")

    def test_git_checkout_when_long_force_flag_then_denied(self) -> None:
        self.assert_blocked("git checkout --force main")

    # === Allowed commands ===

    def test_git_stash_when_list_then_allowed(self) -> None:
        self.assert_allowed("git stash list")

    def test_git_stash_when_show_then_allowed(self) -> None:
        self.assert_allowed("git stash show")

    def test_git_status_when_called_then_allowed(self) -> None:
        self.assert_allowed("git status")

    def test_git_diff_when_called_then_allowed(self) -> None:
        self.assert_allowed("git diff")

    def test_git_add_when_called_then_allowed(self) -> None:
        self.assert_allowed("git add .")

    def test_git_commit_when_called_then_allowed(self) -> None:
        self.assert_allowed('git commit -m "msg"')

    def test_git_checkout_when_specific_file_then_allowed(self) -> None:
        self.assert_allowed("git checkout -- src/app.ts")

    def test_git_checkout_when_ref_specific_file_then_allowed(self) -> None:
        self.assert_allowed("git checkout main -- src/app.ts")

    def test_git_checkout_when_dotenv_then_allowed(self) -> None:
        self.assert_allowed("git checkout -- .env")

    def test_git_checkout_when_ref_dotenv_then_allowed(self) -> None:
        self.assert_allowed("git checkout main -- .env")

    def test_git_checkout_when_dotgitignore_then_allowed(self) -> None:
        self.assert_allowed("git checkout -- .gitignore")

    def test_git_checkout_when_ref_eslintrc_then_allowed(self) -> None:
        self.assert_allowed("git checkout HEAD -- .eslintrc.json")

    def test_git_restore_when_specific_file_then_allowed(self) -> None:
        self.assert_allowed("git restore src/app.ts")

    def test_git_push_when_no_force_then_allowed(self) -> None:
        self.assert_allowed("git push origin main")

    def test_git_push_when_force_with_lease_then_allowed(self) -> None:
        self.assert_allowed("git push --force-with-lease")

    def test_git_branch_when_lowercase_d_then_allowed(self) -> None:
        self.assert_allowed("git branch -d feature")

    def test_git_reset_when_soft_then_allowed(self) -> None:
        self.assert_allowed("git reset --soft HEAD~1")

    def test_git_reset_when_mixed_then_allowed(self) -> None:
        self.assert_allowed("git reset HEAD~1")

    def test_git_log_when_called_then_allowed(self) -> None:
        self.assert_allowed("git log --oneline")

    # === Edge cases ===

    def test_no_verify_when_in_command_then_still_denied(self) -> None:
        self.assert_blocked('git commit --no-verify -m "msg"')

    def test_git_stash_when_in_multicommand_then_denied(self) -> None:
        self.assert_blocked("git add . && git stash")

    def test_git_checkout_when_branch_name_then_allowed(self) -> None:
        self.assert_allowed("git checkout main")

    def test_git_checkout_when_new_branch_then_allowed(self) -> None:
        self.assert_allowed("git checkout -b feature/new")

    def test_git_push_when_force_with_lease_and_force_then_denied(self) -> None:
        self.assert_blocked("git push --force-with-lease --force")


if __name__ == "__main__":
    unittest.main()
