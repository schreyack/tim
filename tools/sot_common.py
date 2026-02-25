"""Shared utilities for settings SOT enforcement."""

import fnmatch
import re
from pathlib import Path


SKIP_DIRS = {
    "__pycache__",
    ".venv",
    "venv",
    ".git",
    "lib",
    "node_modules",
    "dist",
}

SETTINGS_NAMES = {
    "settings",
    "config",
    "cfg",
    "conf",
    "opts",
    "options",
    "preferences",
    "prefs",
    "params",
}

SETTINGS_SUFFIXES = ("_settings", "_config", "_opts", "_options")

CONFIG_VARIABLE_NAMES = {
    "host",
    "port",
    "url",
    "uri",
    "endpoint",
    "timeout",
    "retries",
    "interval",
    "threshold",
    "limit",
    "max_retries",
    "base_url",
    "api_key",
    "api_url",
    "db_url",
    "database_url",
    "secret",
    "password",
    "token",
    "dsn",
}


def find_project_root(start: Path) -> Path | None:
    """Walk up to find project root (directory containing .git)."""
    current = start.resolve()
    while current != current.parent:
        if (current / ".git").exists():
            return current
        current = current.parent
    return None


def load_config(project_root: Path) -> dict | None:
    """Load .tim-settings-sot.yaml if it exists. Returns None to skip."""
    config_path = project_root / ".tim-settings-sot.yaml"
    if not config_path.exists():
        return None

    try:
        import yaml

        return yaml.safe_load(config_path.read_text()) or {}
    except ImportError:
        pass

    return _parse_simple_yaml(config_path.read_text())


def _parse_simple_yaml(text: str) -> dict:
    """Parse simple YAML with top-level keys mapping to lists of strings."""
    result: dict = {}
    current_key: str | None = None
    for line in text.splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        if not line.startswith(" ") and stripped.endswith(":"):
            current_key = stripped[:-1].strip()
            result[current_key] = []
        elif current_key is not None and stripped.startswith("- "):
            value = stripped[2:].strip().strip("\"'")
            result[current_key].append(value)
    return result


def is_settings_name(name: str) -> bool:
    """Check if a name refers to a settings/config object."""
    lower = name.lower()
    if lower in SETTINGS_NAMES:
        return True
    return any(lower.endswith(suffix) for suffix in SETTINGS_SUFFIXES)


def is_exempt(filepath: Path, project_root: Path, patterns: list[str]) -> bool:
    """Check if file matches any exempt_files glob pattern."""
    try:
        rel = filepath.resolve().relative_to(project_root.resolve())
    except ValueError:
        return False
    rel_str = str(rel)
    return any(
        fnmatch.fnmatch(rel_str, pat) or rel_str.startswith(pat.rstrip("/"))
        for pat in patterns
    )


def should_skip_path(filepath: Path) -> bool:
    """Check if path is in a directory we always skip."""
    return any(skip_dir in filepath.parts for skip_dir in SKIP_DIRS)



def default_name_pattern() -> re.Pattern[str]:
    """Compiled regex for DEFAULT_* constant names."""
    return re.compile(r"^_?DEFAULT_")
