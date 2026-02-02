#!/usr/bin/env bash
# detection.sh - Framework detection for tim-test
# Detects pytest, Jest, Playwright, monorepo structure, and package manager

# Detect if pytest is configured
# Returns 0 if pytest found, 1 otherwise
# Sets PYTEST_CONFIG_FILE if found
detect_pytest() {
    local root="${1:-$(pwd)}"
    PYTEST_CONFIG_FILE=""

    # Check for pytest.ini
    if [[ -f "$root/pytest.ini" ]]; then
        PYTEST_CONFIG_FILE="$root/pytest.ini"
        return 0
    fi

    # Check for pyproject.toml with pytest section
    if [[ -f "$root/pyproject.toml" ]]; then
        if grep -q '\[tool\.pytest' "$root/pyproject.toml" 2>/dev/null; then
            PYTEST_CONFIG_FILE="$root/pyproject.toml"
            return 0
        fi
        # Also check for pytest in dependencies (common pattern)
        if grep -q 'pytest' "$root/pyproject.toml" 2>/dev/null; then
            PYTEST_CONFIG_FILE="$root/pyproject.toml"
            return 0
        fi
    fi

    # Check for setup.cfg with pytest section
    if [[ -f "$root/setup.cfg" ]]; then
        if grep -q '\[tool:pytest\]' "$root/setup.cfg" 2>/dev/null; then
            PYTEST_CONFIG_FILE="$root/setup.cfg"
            return 0
        fi
    fi

    # Check for conftest.py (indicates pytest usage)
    if [[ -f "$root/conftest.py" ]] || [[ -f "$root/tests/conftest.py" ]]; then
        PYTEST_CONFIG_FILE="conftest.py"
        return 0
    fi

    return 1
}

# Detect if Jest is configured
# Returns 0 if Jest found, 1 otherwise
# Sets JEST_CONFIG_FILE if found
detect_jest() {
    local root="${1:-$(pwd)}"
    JEST_CONFIG_FILE=""

    # Check for jest.config.js or jest.config.ts
    if [[ -f "$root/jest.config.js" ]]; then
        JEST_CONFIG_FILE="$root/jest.config.js"
        return 0
    fi
    if [[ -f "$root/jest.config.ts" ]]; then
        JEST_CONFIG_FILE="$root/jest.config.ts"
        return 0
    fi
    if [[ -f "$root/jest.config.mjs" ]]; then
        JEST_CONFIG_FILE="$root/jest.config.mjs"
        return 0
    fi
    if [[ -f "$root/jest.config.cjs" ]]; then
        JEST_CONFIG_FILE="$root/jest.config.cjs"
        return 0
    fi

    # Check for package.json with jest config
    if [[ -f "$root/package.json" ]]; then
        if grep -q '"jest"' "$root/package.json" 2>/dev/null; then
            JEST_CONFIG_FILE="$root/package.json"
            return 0
        fi
    fi

    return 1
}

# Detect if Vitest is configured
# Returns 0 if Vitest found, 1 otherwise
# Sets VITEST_CONFIG_FILE if found
detect_vitest() {
    local root="${1:-$(pwd)}"
    VITEST_CONFIG_FILE=""

    # Check for vitest.config.ts or vitest.config.js
    if [[ -f "$root/vitest.config.ts" ]]; then
        VITEST_CONFIG_FILE="$root/vitest.config.ts"
        return 0
    fi
    if [[ -f "$root/vitest.config.js" ]]; then
        VITEST_CONFIG_FILE="$root/vitest.config.js"
        return 0
    fi
    if [[ -f "$root/vitest.config.mts" ]]; then
        VITEST_CONFIG_FILE="$root/vitest.config.mts"
        return 0
    fi

    # Check for vite.config with test section
    if [[ -f "$root/vite.config.ts" ]]; then
        if grep -q 'test:' "$root/vite.config.ts" 2>/dev/null; then
            VITEST_CONFIG_FILE="$root/vite.config.ts"
            return 0
        fi
    fi

    return 1
}

# Detect if Playwright is configured
# Returns 0 if Playwright found, 1 otherwise
# Sets PLAYWRIGHT_CONFIG_FILE if found
detect_playwright() {
    local root="${1:-$(pwd)}"
    PLAYWRIGHT_CONFIG_FILE=""

    # Check for playwright.config.ts or playwright.config.js
    if [[ -f "$root/playwright.config.ts" ]]; then
        PLAYWRIGHT_CONFIG_FILE="$root/playwright.config.ts"
        return 0
    fi
    if [[ -f "$root/playwright.config.js" ]]; then
        PLAYWRIGHT_CONFIG_FILE="$root/playwright.config.js"
        return 0
    fi

    return 1
}

# Detect if this is a monorepo with frontend/backend structure
# Returns 0 if monorepo detected, 1 otherwise
# Sets IS_MONOREPO=1 and MONOREPO_DIRS array
detect_monorepo() {
    local root="${1:-$(pwd)}"
    IS_MONOREPO=0
    MONOREPO_FRONTEND=""
    MONOREPO_BACKEND=""

    # Check for frontend/ and backend/ directories
    if [[ -d "$root/frontend" ]] && [[ -d "$root/backend" ]]; then
        IS_MONOREPO=1
        MONOREPO_FRONTEND="$root/frontend"
        MONOREPO_BACKEND="$root/backend"
        return 0
    fi

    # Check for apps/ directory (common monorepo pattern)
    if [[ -d "$root/apps" ]]; then
        if [[ -d "$root/apps/frontend" ]] || [[ -d "$root/apps/web" ]]; then
            IS_MONOREPO=1
            [[ -d "$root/apps/frontend" ]] && MONOREPO_FRONTEND="$root/apps/frontend"
            [[ -d "$root/apps/web" ]] && MONOREPO_FRONTEND="$root/apps/web"
        fi
        if [[ -d "$root/apps/backend" ]] || [[ -d "$root/apps/api" ]]; then
            [[ -d "$root/apps/backend" ]] && MONOREPO_BACKEND="$root/apps/backend"
            [[ -d "$root/apps/api" ]] && MONOREPO_BACKEND="$root/apps/api"
        fi
        [[ "$IS_MONOREPO" == "1" ]] && return 0
    fi

    # Check for packages/ directory
    if [[ -d "$root/packages" ]]; then
        local pkg_count
        pkg_count=$(find "$root/packages" -maxdepth 1 -type d | wc -l)
        if [[ "$pkg_count" -gt 2 ]]; then
            IS_MONOREPO=1
            return 0
        fi
    fi

    return 1
}

# Detect the package manager (npm, pnpm, yarn)
# Returns the package manager name
detect_package_manager() {
    local root="${1:-$(pwd)}"

    # Check for lockfiles (most reliable indicator)
    if [[ -f "$root/pnpm-lock.yaml" ]]; then
        echo "pnpm"
        return 0
    fi
    if [[ -f "$root/yarn.lock" ]]; then
        echo "yarn"
        return 0
    fi
    if [[ -f "$root/package-lock.json" ]]; then
        echo "npm"
        return 0
    fi
    if [[ -f "$root/bun.lockb" ]]; then
        echo "bun"
        return 0
    fi

    # Default to npm if package.json exists
    if [[ -f "$root/package.json" ]]; then
        echo "npm"
        return 0
    fi

    echo ""
    return 1
}

# Get the package manager exec command (npx, pnpx, yarn, bunx)
get_pm_exec() {
    local pm="${1:-npm}"
    case "$pm" in
        pnpm) echo "pnpm exec" ;;
        yarn) echo "yarn" ;;
        bun) echo "bunx" ;;
        *) echo "npx" ;;
    esac
}

# Detect all frameworks and store results in global variables
# Call this once at startup
detect_all() {
    local root="${1:-$(pwd)}"

    # Initialize detection results
    HAS_PYTEST=0
    HAS_JEST=0
    HAS_VITEST=0
    HAS_PLAYWRIGHT=0
    PACKAGE_MANAGER=""

    # Run detections (use || true to prevent exit on return 1)
    if detect_pytest "$root"; then
        HAS_PYTEST=1
    fi
    if detect_jest "$root"; then
        HAS_JEST=1
    fi
    if detect_vitest "$root"; then
        HAS_VITEST=1
    fi
    if detect_playwright "$root"; then
        HAS_PLAYWRIGHT=1
    fi
    detect_monorepo "$root" || true
    PACKAGE_MANAGER=$(detect_package_manager "$root" || echo "")
}
