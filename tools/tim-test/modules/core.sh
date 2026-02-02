#!/usr/bin/env bash
# core.sh - Core utilities for tim-test
# Provides logging, colors, and project root detection

# Colors
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly RED='\033[0;31m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly BOLD='\033[1m'
readonly NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

log_debug() {
    if [[ "${TIM_TEST_DEBUG:-}" == "1" ]]; then
        echo -e "${CYAN}[DEBUG]${NC} $*" >&2
    fi
}

log_header() {
    echo -e "${BOLD}${BLUE}$*${NC}"
}

# Find project root by looking for package.json or pyproject.toml
# Searches from current directory upward
find_project_root() {
    local dir="${1:-$(pwd)}"

    while [[ "$dir" != "/" ]]; do
        if [[ -f "$dir/package.json" ]] || [[ -f "$dir/pyproject.toml" ]] || [[ -f "$dir/pytest.ini" ]]; then
            echo "$dir"
            return 0
        fi
        dir="$(dirname "$dir")"
    done

    # If no project markers found, return current directory
    echo "$(pwd)"
    return 1
}

# Check if a command exists
command_exists() {
    command -v "$1" &>/dev/null
}

# Run a command with optional prefix for output
run_cmd() {
    local cmd="$1"
    shift
    log_info "Running: $cmd $*"
    "$cmd" "$@"
}
