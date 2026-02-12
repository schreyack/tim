# setup-help.sh - Help display for tim-loop-setup
# Sourced by tim-loop-setup.sh - no shebang or set options

# Show help
show_help() {
    cat << 'HELP_EOF'
Tim Loop - Goal in, working code out: iterative convergence

USAGE:
  /tim-loop TASK [OPTIONS]
  /tim-loop --implement FILE [OPTIONS]
  /tim-loop --wizard FILE

MODES (mutually exclusive):
  Full Workflow (default):  /tim-loop "add feature X"
  Plan Only (--plan):       /tim-loop --plan "design feature X"
  Implement Existing:       /tim-loop --implement plans/active/my-plan.md
  Full Review:              /tim-loop --full-review plans/drafts/my-plan.md
  Tech Review:              /tim-loop --tech-review plans/drafts/my-plan.md
  PM Review:                /tim-loop --pm-review plans/drafts/my-plan.md
  AI-Ready Review:          /tim-loop --ai-ready plans/active/my-plan.md
  Verify Implementation:    /tim-loop --verify plans/active/my-plan.md
  Quick Mode:               /tim-loop --no-review "fix typo"
  Wizard Mode:              /tim-loop --wizard plans/active/my-plan.md

MODIFIER OPTIONS:
  --force, -f               Override existing active session detection
  --team                    Use agent teams for parallel implementation (experimental)
  --auto-approve            Auto-approve all tool permissions
  --max-iterations <n>      Safety limit (default: 30)
  --min-review-iterations <n> Minimum review passes before allowing completion (default: 5)
  --completion-promise      Phrase signaling completion (default: COMPLETE)
  --dry-run                 Preview prompt without executing

CLEANUP OPTIONS:
  --cleanup                 Remove orphan state files (>24h old)
  --cleanup-all             Remove ALL state files (use if stuck)

PLAN-OPS:
    Tim Loop uses plan-ops.sh bundled in the plugin for plan lifecycle
    management. Run plan-ops commands directly from the plugin:

    $PLUGIN_ROOT/scripts/plan-ops.sh wizard <plan-file>
    $PLUGIN_ROOT/scripts/plan-ops.sh help

BEST PRACTICE:
    Always clear context before starting. Copy-paste this block:

      /clear
      /tim-loop "your task"
HELP_EOF
}
