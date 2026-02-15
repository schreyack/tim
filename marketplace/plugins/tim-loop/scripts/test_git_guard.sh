#!/bin/sh
# test_git_guard.sh — POSIX shell tests for git-guard
set -e

PASS=0
FAIL=0
TOTAL=0

# Setup temp dir
TMPDIR_TEST=$(mktemp -d)
trap 'rm -rf "$TMPDIR_TEST"' EXIT

# Create mock git
MOCK_GIT="$TMPDIR_TEST/mock-git"
cat > "$MOCK_GIT" <<'MOCKEOF'
#!/bin/sh
echo "MOCK_GIT_OK"
exit 0
MOCKEOF
chmod +x "$MOCK_GIT"

# Install git-guard with REAL_GIT replaced
GUARD="$TMPDIR_TEST/git"
sed "s|%%REAL_GIT%%|$MOCK_GIT|g" "$(dirname "$0")/git-guard" > "$GUARD"
chmod +x "$GUARD"

# Prepend temp dir to PATH so 'git' resolves to our guard
export PATH="$TMPDIR_TEST:$PATH"

assert_blocked() {
    name="$1"; shift
    TOTAL=$((TOTAL + 1))
    out=$("$GUARD" "$@" 2>&1) && rc=0 || rc=$?
    stderr=$(echo "$out" | grep "BLOCKED" || true)
    if [ "$rc" -ne 0 ] && [ -n "$stderr" ]; then
        PASS=$((PASS + 1))
        echo "  PASS: $name"
    else
        FAIL=$((FAIL + 1))
        echo "  FAIL: $name (expected BLOCKED, rc=$rc, out=$out)"
    fi
}

assert_allowed() {
    name="$1"; shift
    TOTAL=$((TOTAL + 1))
    out=$("$GUARD" "$@" 2>&1) && rc=0 || rc=$?
    has_mock=$(echo "$out" | grep "MOCK_GIT_OK" || true)
    has_block=$(echo "$out" | grep "BLOCKED" || true)
    if [ "$rc" -eq 0 ] && [ -n "$has_mock" ] && [ -z "$has_block" ]; then
        PASS=$((PASS + 1))
        echo "  PASS: $name"
    else
        FAIL=$((FAIL + 1))
        echo "  FAIL: $name (expected MOCK_GIT_OK, rc=$rc, out=$out)"
    fi
}

echo "=== git-guard tests ==="
echo ""
echo "--- stash ---"
assert_blocked test_stash_bare_blocked stash
assert_blocked test_stash_push_blocked stash push
assert_blocked test_stash_pop_blocked stash pop
assert_blocked test_stash_drop_blocked stash drop
assert_allowed test_stash_list_allowed stash list
assert_allowed test_stash_show_allowed stash show

echo ""
echo "--- reset ---"
assert_blocked test_reset_hard_blocked reset --hard
assert_blocked test_reset_hard_ref_blocked reset --hard HEAD~1
assert_allowed test_reset_soft_allowed reset --soft HEAD~1

echo ""
echo "--- clean ---"
assert_blocked test_clean_f_blocked clean -f
assert_blocked test_clean_fd_blocked clean -fd
assert_blocked test_clean_force_blocked clean --force
assert_allowed test_clean_n_allowed clean -n

echo ""
echo "--- checkout ---"
assert_blocked test_checkout_dot_blocked checkout .
assert_blocked test_checkout_doubledash_dot_blocked checkout -- .
assert_allowed test_checkout_file_allowed checkout -- src/app.ts
assert_allowed test_checkout_branch_allowed checkout main
assert_blocked test_checkout_force_blocked checkout -f main
assert_blocked test_checkout_long_force_blocked checkout --force main
assert_blocked test_checkout_head_dot_blocked checkout HEAD -- .

echo ""
echo "--- restore ---"
assert_blocked test_restore_dot_blocked restore .
assert_blocked test_restore_staged_dot_blocked restore --staged .
assert_allowed test_restore_file_allowed restore src/app.ts

echo ""
echo "--- push ---"
assert_blocked test_push_force_blocked push --force
assert_blocked test_push_f_blocked push -f
assert_allowed test_push_force_with_lease_allowed push --force-with-lease
assert_allowed test_push_normal_allowed push origin main
assert_blocked test_push_force_with_lease_then_force_blocked push --force-with-lease --force

echo ""
echo "--- branch ---"
assert_blocked test_branch_D_blocked branch -D feature
assert_allowed test_branch_d_allowed branch -d feature

echo ""
echo "--- passthrough ---"
assert_allowed test_status_allowed status
assert_allowed test_version_passthrough --version

echo ""
echo "--- global flags ---"
assert_blocked test_global_flag_stash_blocked -C /tmp stash

echo ""
echo "--- variable bypass ---"
# GIT=$(which git) resolves to our guard via PATH
TOTAL=$((TOTAL + 1))
GIT_CMD=$(which git)
out=$("$GIT_CMD" stash 2>&1) && rc=0 || rc=$?
stderr=$(echo "$out" | grep "BLOCKED" || true)
if [ "$rc" -ne 0 ] && [ -n "$stderr" ]; then
    PASS=$((PASS + 1))
    echo "  PASS: test_variable_bypass_blocked"
else
    FAIL=$((FAIL + 1))
    echo "  FAIL: test_variable_bypass_blocked (expected BLOCKED, rc=$rc, out=$out)"
fi

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="

if [ "$FAIL" -ne 0 ]; then
    exit 1
fi
echo "All tests passed."
exit 0
