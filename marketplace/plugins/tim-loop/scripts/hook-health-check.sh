#!/bin/bash
# Hook Health Check - Verify tim-loop hooks are properly configured
set -euo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(dirname "$(dirname "$0")")}"
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

# Check 2: hooks.json contains required entries
echo ""
echo "2. hooks.json hook entries:"
if [[ -f "$PLUGIN_HOOKS_FILE" ]]; then
    if grep -q "tim_loop_hook.py" "$PLUGIN_HOOKS_FILE" 2>/dev/null; then
        echo "   ✓ tim_loop_hook.py registered in Stop"
    else
        echo "   ✗ tim_loop_hook.py NOT found in hooks.json"
    fi
    if grep -q "tim-loop-permission-hook.sh" "$PLUGIN_HOOKS_FILE" 2>/dev/null; then
        echo "   ✓ tim-loop-permission-hook.sh registered in PreToolUse"
    else
        echo "   ✗ tim-loop-permission-hook.sh NOT found in hooks.json"
    fi
    if grep -q "excuse_detector_v2.py" "$PLUGIN_HOOKS_FILE" 2>/dev/null; then
        echo "   ✓ excuse_detector_v2.py registered in Stop"
    else
        echo "   ✗ excuse_detector_v2.py NOT found in hooks.json"
    fi
else
    echo "   - hooks.json not found (plugin not installed?)"
fi

# Check 3: Verify scripts exist and are executable
echo ""
echo "3. Hook scripts:"
SCRIPTS=(
    "tim_loop_hook.py:Stop hook (completion check)"
    "tim-loop-permission-hook.sh:PreToolUse (auto-approve)"
    "tim-loop-prompt-manager.sh:SessionStart (prompt preservation)"
    "code-quality-validator.py:PostToolUse (code quality)"
    "excuse_detector_v2.py:Stop (excuse detection)"
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
