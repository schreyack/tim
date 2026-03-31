#!/usr/bin/env bash
# plan-ops/wizard-playbook.sh - Playbook launcher for wizard
# Handles automation → orchestration → tim-e2e command flow
#
# Dependencies: core.sh, verification.sh (show_command)
# Exports: wizard_playbook_launcher
#
# This file is sourced by plan-ops.sh, not executed directly.
# shellcheck source=plan-ops/core.sh

[[ "${BASH_SOURCE[0]}" == "${0}" ]] && { echo "ERROR: Must be sourced" >&2; exit 1; }

# Extract a field value from YAML frontmatter
_pb_frontmatter_field() {
    local file="$1" field="$2"
    awk -v f="$field" '
        NR==1 && /^---/ { in_fm=1; next }
        in_fm && /^---/ { exit }
        in_fm && $0 ~ "^"f":" { sub("^"f":[[:space:]]*", ""); print; exit }
    ' "$file"
}

# Find the playbooks/ root dir from any file within it
_pb_root_dir() {
    local dir
    dir=$(dirname "$1")
    while [[ "$dir" != "/" ]]; do
        [[ "$(basename "$dir")" == "playbooks" ]] && { echo "$dir"; return; }
        dir=$(dirname "$dir")
    done
}

# Offer review before run (y/N, same pattern as plans)
_pb_offer_review() {
    local file="$1"
    echo ""
    echo -n "Would you like to run a review on this playbook first? [y/N] "
    read -r pb_review </dev/tty
    if [[ "$pb_review" =~ ^[Yy] ]]; then
        echo ""
        echo "Run /clear first, then paste this command in Claude Code:"
        show_command "/tim-loop:tim-loop --full-review ${file} --max-iterations 15"
        echo -n "Press Enter when review completes..."
        read -r </dev/tty
    fi
}

# Emit the tim-e2e command and copy to clipboard
_pb_emit_command() {
    local file="$1"
    _pb_offer_review "$file"
    local cmd="/tim-e2e:tim-e2e ${file}"
    echo ""
    echo "Run /clear first, then paste this command in Claude Code:"
    show_command "$cmd"
}

# Main playbook launcher — called when wizard user picks an automation or orchestration
wizard_playbook_launcher() {
    local selected="$1"

    echo ""
    echo "=== Playbook Launcher ==="

    # Orchestration picked directly → emit command
    if [[ "$selected" == *"/orchestrations/"* ]]; then
        local name desc
        name=$(basename "$selected" .md)
        desc=$(_pb_frontmatter_field "$selected" "description")
        echo "Orchestration: ${name}"
        [[ -n "$desc" ]] && echo "  ${desc}"
        _pb_emit_command "$selected"
        return
    fi

    # Automation picked → find orchestrations that reference it
    local auto_name pb_root orch_dir
    auto_name=$(basename "$selected" .md)
    pb_root=$(_pb_root_dir "$selected")
    orch_dir="${pb_root}/orchestrations"

    echo "Automation: ${auto_name}"

    if [[ ! -d "$orch_dir" ]]; then
        log_warn "No orchestrations/ directory found — running standalone"
        _pb_emit_command "$selected"
        return
    fi

    # Scan orchestrations for bold references to this automation in Flow sections
    local matches=()
    while IFS= read -r -d '' orch_file; do
        if grep -qE "\*\*${auto_name}\*\*" "$orch_file"; then
            matches+=("$orch_file")
        fi
    done < <(find "$orch_dir" -maxdepth 1 -name "*.md" -type f -print0 2>/dev/null)

    if [[ ${#matches[@]} -eq 0 ]]; then
        log_warn "No orchestrations reference '${auto_name}'"
        _pb_emit_command "$selected"
        return
    fi

    # Display orchestration choices
    echo ""
    echo "Available orchestrations:"
    echo ""
    local i=1
    for orch in "${matches[@]}"; do
        local oname odesc
        oname=$(basename "$orch" .md)
        odesc=$(_pb_frontmatter_field "$orch" "description")
        printf "  [%d] %s" "$i" "$oname"
        [[ -n "$odesc" ]] && printf " — %s" "$odesc"
        echo ""
        ((i++))
    done
    printf "  [%d] Run automation standalone\n" "$i"
    echo ""

    local choice
    while true; do
        echo -n "Select [1-${i}]: "
        read -r choice </dev/tty
        if [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 ]] && [[ "$choice" -le "$i" ]]; then
            break
        fi
        echo "Invalid choice."
    done

    if [[ "$choice" -eq "$i" ]]; then
        _pb_emit_command "$selected"
    else
        _pb_emit_command "${matches[$((choice-1))]}"
    fi
}
