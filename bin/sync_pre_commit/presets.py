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
}
