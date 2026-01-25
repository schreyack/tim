#!/bin/bash
#
# TIM Design Standards: Claude Code Hooks Installer
#
# This script installs the TIM enforcement hooks into a project's
# .claude/settings.json configuration.
#
# Usage:
#   ./install-hooks.sh [project_path]
#
# If no project path is provided, installs to the current directory.
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${1:-.}"
PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"

CLAUDE_DIR="$PROJECT_DIR/.claude"
HOOKS_DIR="$CLAUDE_DIR/hooks"
SETTINGS_FILE="$CLAUDE_DIR/settings.json"

echo "TIM Design Standards: Claude Code Hooks Installer"
echo "================================================="
echo ""
echo "Project: $PROJECT_DIR"
echo ""

# Create directories
mkdir -p "$HOOKS_DIR"

# Copy hook scripts
echo "Installing hook scripts..."
cp "$SCRIPT_DIR/code-quality-validator.py" "$HOOKS_DIR/"
cp "$SCRIPT_DIR/excuse-detector.py" "$HOOKS_DIR/"

# Make executable
chmod +x "$HOOKS_DIR/code-quality-validator.py"
chmod +x "$HOOKS_DIR/excuse-detector.py"

echo "  - code-quality-validator.py (PostToolUse)"
echo "  - excuse-detector.py (Stop)"

# Configure settings.json
echo ""
echo "Configuring settings.json..."

# Create or merge settings
if [ -f "$SETTINGS_FILE" ]; then
    echo "  Existing settings.json found, merging hooks configuration..."

    # Use Python to merge JSON (handles comments, preserves other settings)
    python3 << 'PYTHON_SCRIPT'
import json
import sys
from pathlib import Path

settings_file = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(".claude/settings.json")

# Read existing settings
try:
    content = settings_file.read_text()
    # Strip comments (simple approach - won't handle all edge cases)
    lines = []
    for line in content.split('\n'):
        stripped = line.strip()
        if not stripped.startswith('//'):
            lines.append(line)
    settings = json.loads('\n'.join(lines))
except:
    settings = {}

# Define TIM hooks
tim_hooks = {
    "PostToolUse": [
        {
            "matcher": "Write|Edit",
            "hooks": [
                {
                    "type": "command",
                    "command": "python3 \"$CLAUDE_PROJECT_DIR/.claude/hooks/code-quality-validator.py\""
                }
            ]
        }
    ],
    "Stop": [
        {
            "matcher": "",
            "hooks": [
                {
                    "type": "command",
                    "command": "python3 \"$CLAUDE_PROJECT_DIR/.claude/hooks/excuse-detector.py\""
                }
            ]
        }
    ]
}

# Merge hooks (TIM hooks take precedence)
if "hooks" not in settings:
    settings["hooks"] = {}

for event, hooks_list in tim_hooks.items():
    if event not in settings["hooks"]:
        settings["hooks"][event] = hooks_list
    else:
        # Append TIM hooks, avoiding duplicates based on command
        existing_commands = set()
        for hook_config in settings["hooks"][event]:
            for hook in hook_config.get("hooks", []):
                existing_commands.add(hook.get("command", ""))

        for hook_config in hooks_list:
            for hook in hook_config.get("hooks", []):
                if hook.get("command", "") not in existing_commands:
                    settings["hooks"][event].append(hook_config)
                    break

# Write updated settings
settings_file.write_text(json.dumps(settings, indent=2) + '\n')
print("  Merged successfully")
PYTHON_SCRIPT

else
    echo "  Creating new settings.json..."
    cat > "$SETTINGS_FILE" << 'EOF'
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [
          {
            "type": "command",
            "command": "python3 \"$CLAUDE_PROJECT_DIR/.claude/hooks/code-quality-validator.py\""
          }
        ]
      }
    ],
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "python3 \"$CLAUDE_PROJECT_DIR/.claude/hooks/excuse-detector.py\""
          }
        ]
      }
    ]
  }
}
EOF
    echo "  Created successfully"
fi

echo ""
echo "Installation complete!"
echo ""
echo "Hooks installed:"
echo "  1. Code Quality Validator (PostToolUse)"
echo "     - Enforces 400-line file limit"
echo "     - Enforces 50-line function limit"
echo "     - Blocks on violation until fixed"
echo ""
echo "  2. Excuse Pattern Detector (Stop)"
echo "     - Detects deflection/excuse patterns"
echo "     - Blocks completion until issues addressed"
echo "     - Enforces accountability for touched files"
echo ""
echo "To verify installation:"
echo "  cat $SETTINGS_FILE"
echo ""
echo "To test hooks:"
echo "  1. Edit a file to exceed 400 lines"
echo "  2. Claude will be blocked from continuing"
echo "  3. The file must be refactored to proceed"
echo ""
