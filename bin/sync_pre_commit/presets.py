"""Project type presets for pre-commit configuration."""

from __future__ import annotations

from typing import Any

PRESETS: dict[str, dict[str, Any]] = {
    "hardware": {
        "disable": ["no-hardcoded-settings", "no-fallback-defaults", "pattern-drift"],
        "hooks": {
            "ruff": {"exclude": "lib/"},
            "ruff-format": {"exclude": "lib/"},
            "bandit": {"exclude": "^lib/"},
            "check-added-large-files": {"exclude": r"\.uf2$"},
        },
    },
    # Native desktop app (C++/Swift, optional Python tooling). No remote-first
    # deploy: Gate 3 (ops.sh --env / k3s / canary) does not apply - release is
    # build -> code-sign -> notarize, handled outside pre-commit. Keeps all
    # Gate 1 + Gate 4 hooks; only excludes the vendored tim submodule from the
    # python linters (the native template ships no lib/ exclusion by default).
    "native-app": {
        "hooks": {
            "ruff": {"exclude": "^lib/"},
            "ruff-format": {"exclude": "^lib/"},
            "bandit": {"exclude": "^lib/"},
        },
    },
}
