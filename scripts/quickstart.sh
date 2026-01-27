#!/usr/bin/env bash
#
# TIM Standards - Quick Start Script
# Checks prerequisites and installs the Tim Loop plugin
#
# Usage: curl -fsSL https://raw.githubusercontent.com/schreyack/tim/main/scripts/quickstart.sh | bash
#    or: ./scripts/quickstart.sh
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_header() {
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  TIM Standards - Quick Start${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo ""
}

print_step() {
    echo -e "${BLUE}▶${NC} $1"
}

print_success() {
    echo -e "  ${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "  ${YELLOW}!${NC} $1"
}

print_error() {
    echo -e "  ${RED}✗${NC} $1"
}

check_command() {
    if command -v "$1" &> /dev/null; then
        return 0
    else
        return 1
    fi
}

get_claude_version() {
    if check_command claude; then
        claude --version 2>/dev/null | head -1 || echo "unknown"
    else
        echo "not installed"
    fi
}

print_header

# Track overall status
ALL_CHECKS_PASSED=true

# ─────────────────────────────────────────────────────────────
# Check Prerequisites
# ─────────────────────────────────────────────────────────────

print_step "Checking prerequisites..."
echo ""

# Check: Bash
if check_command bash; then
    BASH_VERSION_STR=$(bash --version | head -1)
    print_success "Bash: $BASH_VERSION_STR"
else
    print_error "Bash: not found"
    ALL_CHECKS_PASSED=false
fi

# Check: Claude Code CLI
if check_command claude; then
    CLAUDE_VERSION=$(get_claude_version)
    print_success "Claude Code: $CLAUDE_VERSION"
else
    print_error "Claude Code: not installed"
    print_warning "Install from: https://claude.ai/code"
    ALL_CHECKS_PASSED=false
fi

# Check: Git (recommended)
if check_command git; then
    GIT_VERSION=$(git --version)
    print_success "Git: $GIT_VERSION"
else
    print_warning "Git: not installed (recommended for version control)"
fi

# Check: OS
OS_TYPE="unknown"
if [[ "$OSTYPE" == "darwin"* ]]; then
    OS_TYPE="macOS"
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    OS_TYPE="Linux"
elif [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "cygwin" ]]; then
    OS_TYPE="Windows (WSL/Git Bash)"
fi
print_success "OS: $OS_TYPE"

echo ""

# ─────────────────────────────────────────────────────────────
# Install Plugin (if Claude Code is available)
# ─────────────────────────────────────────────────────────────

if check_command claude; then
    print_step "Ready to install Tim Loop plugin"
    echo ""
    echo "  Run these commands in Claude Code:"
    echo ""
    echo -e "    ${GREEN}/plugin marketplace add schreyack/tim${NC}"
    echo -e "    ${GREEN}/plugin install tim-loop@tim${NC}"
    echo ""
    echo "  Then restart Claude Code."
    echo ""
else
    print_step "Install Claude Code first, then run this script again"
    echo ""
fi

# ─────────────────────────────────────────────────────────────
# Optional: Add plan-ops to PATH
# ─────────────────────────────────────────────────────────────

print_step "Optional: Add plan-ops to PATH"
echo ""

PLUGIN_BIN_PATH="\$HOME/.claude/plugins/marketplaces/tim/bin"
SHELL_RC=""

if [[ -f "$HOME/.zshrc" ]]; then
    SHELL_RC="~/.zshrc"
elif [[ -f "$HOME/.bashrc" ]]; then
    SHELL_RC="~/.bashrc"
fi

if [[ -n "$SHELL_RC" ]]; then
    echo "  After installing the plugin, add this to $SHELL_RC:"
    echo ""
    echo -e "    ${GREEN}export PATH=\"$PLUGIN_BIN_PATH:\$PATH\"${NC}"
    echo ""
    echo "  Then reload your shell:"
    echo ""
    echo -e "    ${GREEN}source $SHELL_RC${NC}"
    echo ""
else
    echo "  Add this to your shell config:"
    echo ""
    echo -e "    ${GREEN}export PATH=\"$PLUGIN_BIN_PATH:\$PATH\"${NC}"
    echo ""
fi

# ─────────────────────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────────────────────

echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"

if $ALL_CHECKS_PASSED; then
    echo -e "${GREEN}All prerequisites met. Ready to install Tim Loop.${NC}"
else
    echo -e "${YELLOW}Some prerequisites missing. See above for details.${NC}"
fi

echo ""
echo "Documentation: https://github.com/schreyack/tim"
echo ""
