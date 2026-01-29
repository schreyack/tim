#!/usr/bin/env bash
# plan-ops/security.sh - AI bypass prevention and permissions
# Part of plan-ops.sh modular refactor
#
# Dependencies: core.sh
# Exports: is_claude_descendant, verify_interactive_terminal, ensure_tim_loop_permissions
#
# This file is sourced by plan-ops.sh, not executed directly.
# shellcheck source=plan-ops/core.sh

# Guard against direct execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "ERROR: This module must be sourced, not executed directly" >&2
    exit 1
fi

# =============================================================================
# PROCESS LINEAGE CHECKS
# =============================================================================

# Check if process is a descendant of Claude Code
# Returns: 0 (true) if descendant, 1 (false) otherwise
is_claude_descendant() {
    local pid=$$
    while [[ $pid -ne 1 ]]; do
        local parent_cmd
        parent_cmd=$(ps -p "$pid" -o comm= 2>/dev/null || echo "")
        if [[ "$parent_cmd" == *"claude"* ]]; then
            return 0  # Is a descendant
        fi
        pid=$(ps -p "$pid" -o ppid= 2>/dev/null | tr -d ' ')
        [[ -z "$pid" ]] && break
    done
    return 1  # Not a descendant
}

# Verify command is running from interactive terminal (human, not AI)
# Used by approval commands to block AI bypass attempts
verify_interactive_terminal() {
    # Check if stdin is a terminal (interactive)
    if [[ ! -t 0 ]]; then
        log_error "BLOCKED: This command must be run interactively."
        log_error "AI/scripts cannot run approval commands."
        log_error ""
        log_error "Open a terminal and run this command manually."
        exit 1
    fi

    # Check if we're running under Claude Code session
    if [[ -n "${CLAUDE_CODE_SESSION:-}" ]] || [[ -n "${TIM_LOOP_SESSION_ID:-}" ]]; then
        log_error "BLOCKED: Cannot approve from within Claude Code session."
        log_error "Open a SEPARATE terminal to approve."
        exit 1
    fi

    # Check process lineage for Claude Code
    if is_claude_descendant; then
        log_error "BLOCKED: Cannot approve from within Claude Code process tree."
        log_error "Open a SEPARATE terminal to approve."
        exit 1
    fi
}

# =============================================================================
# PERMISSIONS MANAGEMENT
# =============================================================================

# Check and configure tim-loop permissions in Claude Code settings
# Ensures the project has the necessary permissions to run /tim-loop:tim-loop
ensure_tim_loop_permissions() {
    local project_dir="${1:-.}"

    # Check if tim-loop is installed as a plugin (preferred method)
    # Plugin permissions are handled via allowed-tools in the command frontmatter
    if [[ -f "$HOME/.claude/plugins/installed_plugins.json" ]]; then
        if grep -q 'tim-loop@' "$HOME/.claude/plugins/installed_plugins.json" 2>/dev/null; then
            # Plugin handles its own permissions - no project settings needed
            return 0
        fi
    fi

    # Check for legacy symlink installation
    if [[ ! -f "$HOME/.claude/commands/tim-loop.md" ]] && \
       [[ ! -f "$HOME/.claude/commands/scripts/tim-loop-setup.sh" ]]; then
        # Neither plugin nor symlinks - tim-loop not installed
        echo ""
        log_warn "Tim-loop is not installed."
        echo ""
        echo "Install via Claude Code plugin system:"
        echo "  1. Register the tim marketplace"
        echo "  2. Install the tim-loop plugin"
        echo ""
        echo "Or visit: https://github.com/schreyack/tim"
        echo ""
        return 1
    fi

    # Legacy symlink installation - ensure permissions exist
    local settings_file="${project_dir}/.claude/settings.local.json"

    if [[ ! -d "${project_dir}/.claude" ]]; then
        mkdir -p "${project_dir}/.claude"
    fi

    if [[ ! -f "$settings_file" ]]; then
        cat > "$settings_file" << 'EOF'
{
  "permissions": {
    "allow": [
      "Bash(~/.claude/commands/scripts/*)"
    ]
  }
}
EOF
        log_info "Created $settings_file with legacy tim-loop permissions"
        return 0
    fi

    # Check if legacy permission exists
    if grep -q 'Bash(~/.claude/commands/scripts/\*)' "$settings_file" 2>/dev/null; then
        return 0
    fi

    # Offer to add legacy permission
    echo ""
    log_warn "Legacy tim-loop permissions not found."
    echo ""
    echo "Consider upgrading to the tim-loop plugin for easier management."
    echo ""
    echo -n "Add legacy permission to settings? [Y/n] "
    read -r response </dev/tty

    if [[ ! "$response" =~ ^[Nn] ]]; then
        python3 << PYTHON_EOF
import json
settings_file = "$settings_file"
try:
    with open(settings_file, 'r') as f:
        data = json.load(f)
except:
    data = {}
if 'permissions' not in data:
    data['permissions'] = {}
if 'allow' not in data['permissions']:
    data['permissions']['allow'] = []
perm = 'Bash(~/.claude/commands/scripts/*)'
if perm not in data['permissions']['allow']:
    data['permissions']['allow'].insert(0, perm)
with open(settings_file, 'w') as f:
    json.dump(data, f, indent=2)
PYTHON_EOF
        log_info "Added legacy permission to $settings_file"
        log_warn "Restart Claude Code for permissions to take effect."
    fi
}
