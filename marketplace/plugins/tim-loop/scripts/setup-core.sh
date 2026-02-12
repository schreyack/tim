# setup-core.sh - Core utility functions for tim-loop-setup
# Sourced by tim-loop-setup.sh - no shebang or set options

# Initialize plans folder structure if not present
init_plans_folders() {
    for stage in drafts active completed abandoned; do
        if [[ ! -d "./plans/${stage}" ]]; then
            mkdir -p "./plans/${stage}"
            touch "./plans/${stage}/.gitkeep"
            echo "Created: ./plans/${stage}/" >&2
        fi
    done
}

# Generate plan filename slug from task description
generate_plan_slug() {
    local task="$1"
    local slug=$(echo "$task" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9 ]//g' | tr ' ' '-' | sed 's/--*/-/g' | cut -c1-50)
    echo "$(date +%Y-%m-%d)-${slug}.md"
}

# Ensure plans/drafts directory exists and return its path
ensure_plans_dir() {
    local plans_dir="${PWD}/plans/drafts"
    [[ ! -d "$plans_dir" ]] && mkdir -p "$plans_dir" && echo "Created plans directory: $plans_dir" >&2
    echo "$plans_dir"
}
