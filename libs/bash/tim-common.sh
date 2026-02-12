#!/usr/bin/env bash
#
# tim-common.sh - Shared bash library for TIM scripts
#
# Provides color constants and common utility functions.
# Source this file from any TIM bash script:
#   source "$TIM_ROOT/libs/bash/tim-common.sh"
#
# Requires TIM_ROOT to be set before sourcing.

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

# Load registered projects from .tim-projects into PROJECTS array.
# Returns 1 if .tim-projects is not found.
load_projects() {
    PROJECTS=()
    local projects_file="$TIM_ROOT/.tim-projects"
    if [[ ! -f "$projects_file" ]]; then
        echo -e "${YELLOW}Warning: .tim-projects not found at $projects_file${NC}" >&2
        return 1
    fi
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "$line" || "$line" == \#* ]] && continue
        PROJECTS+=("$line")
    done < "$projects_file"
}
