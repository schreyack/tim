#!/bin/bash
# Hook Health Check - Verify tim-loop hooks are properly configured
set -euo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(dirname "$(dirname "$0")")}"
SETTINGS_FILE="$HOME/.claude/settings.local.json"
PLUGIN_HOOKS_FILE="${PLUGIN_ROOT}/hooks/hooks.json"

echo "=== Tim Loop Hook Health Check ==="
echo ""

# Check 1: Plugin hooks.json exists
echo "1. Plugin hooks definition:"
if [[ -f "$PLUGIN_HOOKS_FILE" ]]; then
    echo "   ✓ hooks.json exists at: $PLUGIN_HOOKS_FILE"
else
    echo "   ✗ hooks.json NOT FOUND at: $PLUGIN_HOOKS_FILE"
fi

# Check 2: Settings file exists and has hooks
echo ""
echo "2. Settings file hooks (runtime):"
if [[ -f "$SETTINGS_FILE" ]]; then
    echo "   ✓ settings.local.json exists"

    # Check for each hook type
    for hook_type in stop PreToolUse SessionStart PostToolUse Stop; do
        if grep -q "\"$hook_type\"" "$SETTINGS_FILE" 2>/dev/null; then
            echo "   ✓ $hook_type hook registered"
        fi
    done
else
    echo "   - settings.local.json not found (hooks not yet registered)"
fi

# Check 3: Verify scripts exist and are executable
echo ""
echo "3. Hook scripts:"
SCRIPTS=(
    "tim_loop_hook.py:stop hook (completion check)"
    "tim-loop-permission-hook.sh:PreToolUse (auto-approve)"
    "tim-loop-prompt-manager.sh:SessionStart (prompt preservation)"
    "code-quality-validator.py:PostToolUse (code quality)"
    "excuse-detector.py:Stop (excuse detection)"
)

for script_info in "${SCRIPTS[@]}"; do
    script="${script_info%%:*}"
    desc="${script_info#*:}"
    script_path="${PLUGIN_ROOT}/scripts/${script}"

    if [[ -f "$script_path" ]]; then
        if [[ -x "$script_path" ]] || [[ "$script" == *.py ]]; then
            echo "   ✓ $script ($desc)"
        else
            echo "   ⚠ $script exists but not executable"
        fi
    else
        echo "   ✗ $script NOT FOUND"
    fi
done

# Check 4: Active session
echo ""
echo "4. Active sessions:"
ACTIVE_FILE="$HOME/.claude/.tim-loop-active"
if [[ -f "$ACTIVE_FILE" ]]; then
    STATE_FILE=$(cat "$ACTIVE_FILE")
    if [[ -f "$STATE_FILE" ]]; then
        SESSION_ID=$(grep "^SESSION_ID=" "$STATE_FILE" | cut -d'=' -f2 | tr -d '"')
        echo "   Active session: $SESSION_ID"
        echo "   State file: $STATE_FILE"
    else
        echo "   ⚠ Active marker exists but state file missing"
    fi
else
    echo "   No active tim-loop session"
fi

echo ""
echo "=== Health Check Complete ==="
