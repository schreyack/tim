#!/usr/bin/env bash
# commands.sh - Command implementations for tim-test
# Provides unit, integration, e2e, all, watch, and info commands

# Run unit tests
cmd_unit() {
    local passthrough_args=("$@")
    local target_dir="$PROJECT_ROOT"

    # Handle --backend and --frontend flags for monorepos
    if [[ "$TARGET_BACKEND" == "1" ]] && [[ -n "$MONOREPO_BACKEND" ]]; then
        target_dir="$MONOREPO_BACKEND"
        log_info "Targeting backend: $target_dir"
    elif [[ "$TARGET_FRONTEND" == "1" ]] && [[ -n "$MONOREPO_FRONTEND" ]]; then
        target_dir="$MONOREPO_FRONTEND"
        log_info "Targeting frontend: $target_dir"
    fi

    cd "$target_dir" || { log_error "Cannot cd to $target_dir"; return 1; }

    # Re-detect frameworks for target directory
    detect_all "$target_dir"

    if [[ "$HAS_PYTEST" == "1" ]]; then
        run_pytest_unit "${passthrough_args[@]}"
    elif [[ "$HAS_VITEST" == "1" ]]; then
        run_vitest_unit "${passthrough_args[@]}"
    elif [[ "$HAS_JEST" == "1" ]]; then
        run_jest_unit "${passthrough_args[@]}"
    else
        log_error "No test framework detected in $target_dir"
        log_info "Looking for: pytest.ini, pyproject.toml, jest.config.*, vitest.config.*"
        return 1
    fi
}

# Run integration tests
cmd_integration() {
    local passthrough_args=("$@")
    local target_dir="$PROJECT_ROOT"

    if [[ "$TARGET_BACKEND" == "1" ]] && [[ -n "$MONOREPO_BACKEND" ]]; then
        target_dir="$MONOREPO_BACKEND"
    elif [[ "$TARGET_FRONTEND" == "1" ]] && [[ -n "$MONOREPO_FRONTEND" ]]; then
        target_dir="$MONOREPO_FRONTEND"
    fi

    cd "$target_dir" || { log_error "Cannot cd to $target_dir"; return 1; }
    detect_all "$target_dir"

    if [[ "$HAS_PYTEST" == "1" ]]; then
        run_pytest_integration "${passthrough_args[@]}"
    elif [[ "$HAS_VITEST" == "1" ]]; then
        run_vitest_integration "${passthrough_args[@]}"
    elif [[ "$HAS_JEST" == "1" ]]; then
        run_jest_integration "${passthrough_args[@]}"
    else
        log_error "No test framework detected in $target_dir"
        return 1
    fi
}

# Run e2e tests (Playwright)
cmd_e2e() {
    local passthrough_args=("$@")
    local target_dir="$PROJECT_ROOT"

    # For e2e, check project root first, then frontend
    if [[ "$HAS_PLAYWRIGHT" != "1" ]] && [[ -n "$MONOREPO_FRONTEND" ]]; then
        if [[ -f "$MONOREPO_FRONTEND/playwright.config.ts" ]] || [[ -f "$MONOREPO_FRONTEND/playwright.config.js" ]]; then
            target_dir="$MONOREPO_FRONTEND"
        fi
    fi

    cd "$target_dir" || { log_error "Cannot cd to $target_dir"; return 1; }
    detect_all "$target_dir"

    if [[ "$HAS_PLAYWRIGHT" == "1" ]]; then
        run_playwright "${passthrough_args[@]}"
    else
        log_error "Playwright not detected in $target_dir"
        log_info "Looking for: playwright.config.ts, playwright.config.js"
        return 1
    fi
}

# Run all tests
cmd_all() {
    local passthrough_args=("$@")
    local exit_code=0

    log_header "Running all tests..."

    # Run backend tests if backend exists or pytest detected
    if [[ "$IS_MONOREPO" == "1" ]] && [[ -n "$MONOREPO_BACKEND" ]]; then
        log_header "=== Backend Tests ==="
        TARGET_BACKEND=1 TARGET_FRONTEND=0 cmd_unit "${passthrough_args[@]}" || exit_code=1
    elif [[ "$HAS_PYTEST" == "1" ]]; then
        log_header "=== Python Tests ==="
        cmd_unit "${passthrough_args[@]}" || exit_code=1
    fi

    # Run frontend tests if frontend exists or Jest/Vitest detected
    if [[ "$IS_MONOREPO" == "1" ]] && [[ -n "$MONOREPO_FRONTEND" ]]; then
        log_header "=== Frontend Tests ==="
        TARGET_BACKEND=0 TARGET_FRONTEND=1 cmd_unit "${passthrough_args[@]}" || exit_code=1
    elif [[ "$HAS_JEST" == "1" ]] || [[ "$HAS_VITEST" == "1" ]]; then
        if [[ "$HAS_PYTEST" != "1" ]]; then
            log_header "=== JavaScript Tests ==="
            cmd_unit "${passthrough_args[@]}" || exit_code=1
        fi
    fi

    # Run e2e tests if Playwright is detected
    if [[ "$HAS_PLAYWRIGHT" == "1" ]]; then
        log_header "=== E2E Tests ==="
        cmd_e2e "${passthrough_args[@]}" || exit_code=1
    fi

    return $exit_code
}

# Run tests in watch mode
cmd_watch() {
    local passthrough_args=("$@")
    local target_dir="$PROJECT_ROOT"

    if [[ "$TARGET_BACKEND" == "1" ]] && [[ -n "$MONOREPO_BACKEND" ]]; then
        target_dir="$MONOREPO_BACKEND"
    elif [[ "$TARGET_FRONTEND" == "1" ]] && [[ -n "$MONOREPO_FRONTEND" ]]; then
        target_dir="$MONOREPO_FRONTEND"
    fi

    cd "$target_dir" || { log_error "Cannot cd to $target_dir"; return 1; }
    detect_all "$target_dir"

    if [[ "$HAS_PYTEST" == "1" ]]; then
        run_pytest_watch "${passthrough_args[@]}"
    elif [[ "$HAS_VITEST" == "1" ]]; then
        run_vitest_watch "${passthrough_args[@]}"
    elif [[ "$HAS_JEST" == "1" ]]; then
        run_jest_watch "${passthrough_args[@]}"
    else
        log_error "No test framework detected in $target_dir"
        return 1
    fi
}

# Show detection results
cmd_info() {
    log_header "tim-test Detection Results"
    echo ""
    echo "Project Root: $PROJECT_ROOT"
    echo ""

    log_header "Test Frameworks Detected:"
    if [[ "$HAS_PYTEST" == "1" ]]; then
        echo "  ✓ pytest (config: $PYTEST_CONFIG_FILE)"
    else
        echo "  ✗ pytest"
    fi
    if [[ "$HAS_JEST" == "1" ]]; then
        echo "  ✓ Jest (config: $JEST_CONFIG_FILE)"
    else
        echo "  ✗ Jest"
    fi
    if [[ "$HAS_VITEST" == "1" ]]; then
        echo "  ✓ Vitest (config: $VITEST_CONFIG_FILE)"
    else
        echo "  ✗ Vitest"
    fi
    if [[ "$HAS_PLAYWRIGHT" == "1" ]]; then
        echo "  ✓ Playwright (config: $PLAYWRIGHT_CONFIG_FILE)"
    else
        echo "  ✗ Playwright"
    fi
    echo ""

    log_header "Package Manager:"
    if [[ -n "$PACKAGE_MANAGER" ]]; then
        echo "  $PACKAGE_MANAGER"
    else
        echo "  (none detected)"
    fi
    echo ""

    log_header "Monorepo Structure:"
    if [[ "$IS_MONOREPO" == "1" ]]; then
        echo "  ✓ Monorepo detected"
        [[ -n "$MONOREPO_FRONTEND" ]] && echo "    Frontend: $MONOREPO_FRONTEND"
        [[ -n "$MONOREPO_BACKEND" ]] && echo "    Backend: $MONOREPO_BACKEND"
    else
        echo "  ✗ Not a monorepo"
    fi
    echo ""

    log_header "Available Commands:"
    [[ "$HAS_PYTEST" == "1" ]] || [[ "$HAS_JEST" == "1" ]] || [[ "$HAS_VITEST" == "1" ]] && echo "  tim-test unit"
    [[ "$HAS_PYTEST" == "1" ]] || [[ "$HAS_JEST" == "1" ]] || [[ "$HAS_VITEST" == "1" ]] && echo "  tim-test integration"
    [[ "$HAS_PLAYWRIGHT" == "1" ]] && echo "  tim-test e2e"
    echo "  tim-test all"
    [[ "$HAS_PYTEST" == "1" ]] || [[ "$HAS_JEST" == "1" ]] || [[ "$HAS_VITEST" == "1" ]] && echo "  tim-test watch"
    if [[ "$IS_MONOREPO" == "1" ]]; then
        echo ""
        echo "  Monorepo flags: --backend, --frontend"
    fi
}

# === Framework-specific runners ===

run_pytest_unit() {
    local args=("$@")
    local test_dir=""

    # Look for tests/unit directory
    if [[ -d "tests/unit" ]]; then
        test_dir="tests/unit"
    elif [[ -d "test/unit" ]]; then
        test_dir="test/unit"
    elif [[ -d "tests" ]]; then
        test_dir="tests"
    fi

    log_info "Running pytest unit tests..."
    if [[ -n "$test_dir" ]]; then
        pytest "$test_dir" "${args[@]}"
    else
        pytest "${args[@]}"
    fi
}

run_pytest_integration() {
    local args=("$@")

    log_info "Running pytest integration tests..."
    # Try integration directory first
    if [[ -d "tests/integration" ]]; then
        pytest "tests/integration" "${args[@]}"
    elif [[ -d "test/integration" ]]; then
        pytest "test/integration" "${args[@]}"
    else
        # Fall back to marker
        pytest -m integration "${args[@]}"
    fi
}

run_pytest_watch() {
    local args=("$@")

    if command_exists ptw; then
        log_info "Running pytest-watch..."
        ptw "${args[@]}"
    elif command_exists pytest-watch; then
        log_info "Running pytest-watch..."
        pytest-watch "${args[@]}"
    else
        log_warn "pytest-watch not installed. Install with: pip install pytest-watch"
        log_info "Running pytest once instead..."
        pytest "${args[@]}"
    fi
}

run_jest_unit() {
    local args=("$@")
    local pm_exec
    pm_exec=$(get_pm_exec "$PACKAGE_MANAGER")

    log_info "Running Jest unit tests..."
    $pm_exec jest "${args[@]}"
}

run_jest_integration() {
    local args=("$@")
    local pm_exec
    pm_exec=$(get_pm_exec "$PACKAGE_MANAGER")

    log_info "Running Jest integration tests..."
    if [[ -d "tests/integration" ]] || [[ -d "__tests__/integration" ]]; then
        $pm_exec jest --testPathPattern="integration" "${args[@]}"
    else
        $pm_exec jest "${args[@]}"
    fi
}

run_jest_watch() {
    local args=("$@")
    local pm_exec
    pm_exec=$(get_pm_exec "$PACKAGE_MANAGER")

    log_info "Running Jest in watch mode..."
    $pm_exec jest --watch "${args[@]}"
}

run_vitest_unit() {
    local args=("$@")
    local pm_exec
    pm_exec=$(get_pm_exec "$PACKAGE_MANAGER")

    log_info "Running Vitest unit tests..."
    $pm_exec vitest run "${args[@]}"
}

run_vitest_integration() {
    local args=("$@")
    local pm_exec
    pm_exec=$(get_pm_exec "$PACKAGE_MANAGER")

    log_info "Running Vitest integration tests..."
    $pm_exec vitest run "${args[@]}"
}

run_vitest_watch() {
    local args=("$@")
    local pm_exec
    pm_exec=$(get_pm_exec "$PACKAGE_MANAGER")

    log_info "Running Vitest in watch mode..."
    $pm_exec vitest "${args[@]}"
}

run_playwright() {
    local args=("$@")
    local pm_exec
    pm_exec=$(get_pm_exec "$PACKAGE_MANAGER")

    log_info "Running Playwright e2e tests..."
    $pm_exec playwright test "${args[@]}"
}
