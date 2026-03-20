#!/usr/bin/env bash
# plan-ops/commands-playbook.sh - Playbook commands
# Part of plan-ops.sh modular refactor
#
# Dependencies: core.sh, search.sh, security.sh, status.sh, status-init.sh,
#               reset.sh, verification.sh, commands-utility.sh
# Exports: cmd_playbook
#
# This file is sourced by plan-ops.sh, not executed directly.
# shellcheck source=plan-ops/core.sh

# Guard against direct execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "ERROR: This module must be sourced, not executed directly" >&2
    exit 1
fi

# Insert Run Log section after the --- that follows Progress Log
_insert_run_log() {
    local file="$1"
    local progress_end_line
    progress_end_line=$(awk '/^### Progress Log/{found=1} found && /^---/{print NR; exit}' "$file")
    if [[ -n "$progress_end_line" ]]; then
        # Write block to temp file to avoid awk multiline -v issues
        local run_log_tmp="${file}.runlog.tmp"
        cat > "$run_log_tmp" << 'RUNLOG'

### Run Log

| Run # | Started | Result | Notes |
|-------|---------|--------|-------|

---
RUNLOG
        awk -v n="$progress_end_line" '
            NR == n { print; while ((getline line < "'"$run_log_tmp"'") > 0) print line; next }
            { print }
        ' "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"
        rm -f "$run_log_tmp"
    fi
}

# Resolve and validate a playbook is in playbooks/
_resolve_playbook() {
    local arg="$1"

    # If it's a direct path to a file, use it
    if [[ "$arg" == */* && -f "$arg" ]]; then
        local abs_path
        abs_path=$(to_absolute "$arg")
        if [[ "$abs_path" == *"/plans/playbooks/"* ]]; then
            echo "$abs_path"
            return 0
        fi
        log_error "Not a playbook (not in playbooks/): $abs_path"
        exit 1
    fi

    # Search by name — look in playbooks/ first to avoid disambiguation
    # with copies in completed/ or other stages
    local search_name="${arg%.md}"
    local playbooks_dir="${PLANS_DIR}/playbooks"
    if [[ -d "$playbooks_dir" ]]; then
        local match
        match=$(find "$playbooks_dir" -maxdepth 1 -name "*${search_name}*" -type f 2>/dev/null | head -1)
        if [[ -n "$match" ]]; then
            echo "$match"
            return 0
        fi
    fi

    # Fallback to general resolve (for ~/.claude/plans/playbooks/ etc.)
    local playbook_file
    playbook_file=$(resolve_plan_path "$arg") || exit 1
    if [[ "$playbook_file" != *"/plans/playbooks/"* ]]; then
        log_error "Not a playbook (not in playbooks/): $playbook_file"
        exit 1
    fi
    echo "$playbook_file"
}

cmd_playbook() {
    local subcmd="${1:-help}"
    shift || true
    case "$subcmd" in
        create)  cmd_playbook_create "$@" ;;
        import)  cmd_playbook_import "$@" ;;
        list)    cmd_playbook_list ;;
        run)     cmd_playbook_run "$@" ;;
        log)     cmd_playbook_log "$@" ;;
        show)    cmd_playbook_show "$@" ;;
        help)    cmd_playbook_help ;;
        *)
            log_error "Unknown playbook subcommand: $subcmd"
            cmd_playbook_help
            exit 1
            ;;
    esac
}

cmd_playbook_create() {
    local name="${1:-}"
    if [[ -z "$name" ]]; then
        log_error "Usage: $SCRIPT_PATH playbook create <name>"
        exit 1
    fi

    local dest="${PLANS_DIR}/drafts/$(date +%Y-%m-%d-%H-%M)-${name}.md"
    mkdir -p "${PLANS_DIR}/drafts"

    echo "# ${name} (Playbook)" > "$dest"
    add_status_header "$dest"
    ensure_status_header_fields "$dest"
    _add_or_update_status_field "Type" "playbook" "Stage" "$dest"
    _insert_run_log "$dest"

    cat >> "$dest" << 'EOF'

## Instructions

## Verification
EOF

    log_info "Created playbook: $dest"
    echo ""
    log_info "NEXT STEP: Edit the playbook, then run the wizard:"
    show_command "$SCRIPT_PATH wizard $dest"
}

cmd_playbook_import() {
    local file="${1:-}"
    if [[ -z "$file" ]]; then
        log_error "Usage: $SCRIPT_PATH playbook import <file>"
        exit 1
    fi
    # Try to resolve - first as literal path, then by searching
    if [[ -f "$file" ]]; then
        file=$(to_absolute "$file")
    else
        local resolved
        resolved=$(resolve_plan_path "$file" 2>/dev/null) || true
        if [[ -n "$resolved" && -f "$resolved" ]]; then
            file="$resolved"
        else
            log_error "File not found: $file"
            log_info "Searched in: current directory, $PLANS_DIR/*, $CLAUDE_PLANS_DIR"
            exit 1
        fi
    fi

    # Determine where the source lives (its project's plans dir)
    local source_plans_dir
    source_plans_dir=$(get_plans_dir_from_path "$file")

    local basename
    basename=$(basename "$file")
    if [[ ! "$basename" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2} ]]; then
        basename="$(date +%Y-%m-%d-%H-%M)-${basename}"
    fi

    # Copy directly to playbooks/ (not drafts — import is for reviewed plans)
    mkdir -p "${PLANS_DIR}/playbooks"
    local dest="${PLANS_DIR}/playbooks/${basename}"
    cp "$file" "$dest"

    # Set up playbook status
    add_status_header "$dest"
    ensure_status_header_fields "$dest"
    _add_or_update_status_field "Type" "playbook" "Stage" "$dest"
    update_status "$dest" "playbook" "Imported as playbook"

    # Add Run Log if missing
    if ! grep -qE "^### Run Log" "$dest"; then
        _insert_run_log "$dest"
    fi

    log_info "Imported playbook: $dest"

    # Move the original plan to completed (if it's in this project's plans/)
    if [[ "$file" == "${source_plans_dir}/"* && "$file" != *"/plans/completed/"* && "$file" != *"/plans/playbooks/"* ]]; then
        local original_dest
        original_dest="${source_plans_dir}/completed/$(basename "$file")"
        mkdir -p "${source_plans_dir}/completed"
        mv "$file" "$original_dest"
        add_status_header "$original_dest"
        ensure_status_header_fields "$original_dest"
        update_status "$original_dest" "completed" "Promoted to playbook"
        log_info "Original plan moved to completed: $original_dest"
    fi

    echo ""
    log_info "Playbook ready to run:"
    show_command "$SCRIPT_PATH playbook run $(basename "$dest" .md)"
}

cmd_playbook_list() {
    echo "=== playbooks ==="
    list_stage_contents "playbooks"
    echo ""
}

cmd_playbook_run() {
    verify_interactive_terminal

    local playbook_arg="${1:-}"
    if [[ -z "$playbook_arg" ]]; then
        log_error "Usage: $SCRIPT_PATH playbook run <playbook>"
        exit 1
    fi

    local playbook_file
    playbook_file=$(_resolve_playbook "$playbook_arg")

    local plan_type
    plan_type=$(get_plan_type "$playbook_file")
    if [[ "$plan_type" != "playbook" ]]; then
        log_error "Not a playbook (Type: ${plan_type}): $playbook_file"
        exit 1
    fi

    local run_count
    run_count=$(get_status_field "$playbook_file" "Run Count")
    [[ -z "$run_count" || "$run_count" == "-" ]] && run_count=0
    run_count=$((run_count + 1))

    local ts
    ts=$(timestamp)

    _add_or_update_status_field "Run Count" "$run_count" "Type" "$playbook_file"
    _add_or_update_status_field "Last Run" "$ts" "Run Count" "$playbook_file"

    if grep -qE "^### Run Log" "$playbook_file"; then
        local log_row="| ${run_count} | ${ts} | - | - |"
        awk -v row="$log_row" '
            /^\| Run # \| Started \| Result \| Notes \|/ { in_table=1 }
            in_table && /^$/ { print row; in_table=0 }
            in_table && /^---$/ { print row; in_table=0 }
            { print }
        ' "$playbook_file" > "${playbook_file}.tmp" && mv "${playbook_file}.tmp" "$playbook_file"
    fi

    update_status "$playbook_file" "playbook" "Playbook run #${run_count} started"

    log_info "Starting playbook run #${run_count}"
    echo ""
    log_info "Run this command in Claude Code:"
    show_command "/tim-loop:tim-loop --implement $playbook_file"
}

cmd_playbook_log() {
    local playbook_arg=""
    local result=""
    local notes=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --result) result="$2"; shift 2 ;;
            --notes)  notes="$2"; shift 2 ;;
            *)
                [[ -z "$playbook_arg" ]] && playbook_arg="$1"
                shift
                ;;
        esac
    done

    if [[ -z "$playbook_arg" ]]; then
        log_error "Usage: $SCRIPT_PATH playbook log <playbook> --result <success|failure|partial> [--notes \"...\"]"
        exit 1
    fi
    if [[ -z "$result" ]]; then
        log_error "Missing --result flag (required: success|failure|partial)"
        exit 1
    fi
    if [[ "$result" != "success" && "$result" != "failure" && "$result" != "partial" ]]; then
        log_error "Invalid result: $result (must be success|failure|partial)"
        exit 1
    fi

    local playbook_file
    playbook_file=$(_resolve_playbook "$playbook_arg")

    local escaped_notes="${notes//|/\\|}"

    if ! grep -qE "^### Run Log" "$playbook_file"; then
        log_error "No Run Log section found in playbook"
        exit 1
    fi

    local pending_line
    pending_line=$({ grep -nE "^\|[^|]+\|[^|]+\| - \| - \|" "$playbook_file" || true; } | tail -1 | cut -d: -f1)
    if [[ -z "$pending_line" ]]; then
        log_error "No pending run found — run the playbook first"
        exit 1
    fi

    local original_row
    original_row=$(sed -n "${pending_line}p" "$playbook_file")
    local run_num ts_val
    run_num=$(echo "$original_row" | awk -F'|' '{gsub(/^[[:space:]]+|[[:space:]]+$/,"",$2); print $2}')
    ts_val=$(echo "$original_row" | awk -F'|' '{gsub(/^[[:space:]]+|[[:space:]]+$/,"",$3); print $3}')
    local new_row="| ${run_num} | ${ts_val} | ${result} | ${escaped_notes:-"-"} |"
    sed -i '' "${pending_line}s|.*|${new_row}|" "$playbook_file"

    _add_or_update_status_field "Last Result" "$result" "Last Run" "$playbook_file"
    update_status "$playbook_file" "playbook" "Run #${run_num} result: ${result}"
    log_info "Logged result '${result}' for run #${run_num}"
}

cmd_playbook_show() {
    local playbook_arg="${1:-}"
    if [[ -z "$playbook_arg" ]]; then
        log_error "Usage: $SCRIPT_PATH playbook show <playbook>"
        exit 1
    fi

    local playbook_file
    playbook_file=$(_resolve_playbook "$playbook_arg")

    local plan_type run_count last_run last_result
    plan_type=$(get_plan_type "$playbook_file")
    run_count=$(get_status_field "$playbook_file" "Run Count")
    last_run=$(get_status_field "$playbook_file" "Last Run")
    last_result=$(get_status_field "$playbook_file" "Last Result")
    [[ -z "$run_count" ]] && run_count="-"
    [[ -z "$last_run" ]] && last_run="-"
    [[ -z "$last_result" ]] && last_result="-"

    echo ""
    echo "Playbook: $playbook_file"
    echo "Type: $plan_type"
    echo "Run Count: $run_count"
    echo "Last Run: $last_run"
    echo "Last Result: $last_result"
    echo ""

    if grep -qE "^### Run Log" "$playbook_file"; then
        # Extract only rows from the Run Log section (after "### Run Log", before next "---")
        local run_rows
        run_rows=$(awk '/^### Run Log/{found=1; next} found && /^---/{exit} found && /^\| [0-9]/{print}' "$playbook_file" | tail -5)
        if [[ -n "$run_rows" ]]; then
            echo "Recent runs:"
            echo "$run_rows"
        else
            echo "No runs yet."
        fi
        echo ""
    else
        echo "No run history."
        echo ""
    fi
}

cmd_playbook_help() {
    cat << EOF
plan-ops.sh playbook - Playbook Management

USAGE:
    $SCRIPT_PATH playbook <subcommand> [arguments]

SUBCOMMANDS:
    create <name>         Create a new playbook scaffold in drafts/
    import <file>         Import a reviewed plan as a playbook (moves to playbooks/, original to completed/)
    list                  List all playbooks in the playbooks/ stage
    run <playbook>        Start a playbook run (interactive terminal required)
    log <playbook> --result <success|failure|partial> [--notes "..."]
                          Log the result of the most recent run
    show <playbook>       Show playbook status and recent run history
    help                  Show this help message

EXAMPLES:
    $SCRIPT_PATH playbook create deploy-checklist
    $SCRIPT_PATH playbook import auth-e2e-smoke-test
    $SCRIPT_PATH playbook list
    $SCRIPT_PATH playbook run deploy-checklist
    $SCRIPT_PATH playbook log deploy-checklist --result success --notes "All checks passed"
    $SCRIPT_PATH playbook show deploy-checklist

WORKFLOW:
    Create new:  create → wizard (review) → playbook run
    From plan:   import <plan> → playbook run (original moved to completed/)
    After run:   playbook log → playbook show
EOF
}
