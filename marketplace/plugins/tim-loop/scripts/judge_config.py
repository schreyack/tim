#!/usr/bin/env python3
"""
LLM Judge Configuration

Handles loading and caching of LLM judge configuration from:
1. Environment variables (highest priority)
2. User config (~/.claude/tim-loop-config.yaml)
3. Plugin default config (config.yaml)
"""

import os
from pathlib import Path

# Config file locations (in precedence order after env vars)
USER_CONFIG_PATH = Path.home() / ".claude" / "tim-loop-config.yaml"
PLUGIN_CONFIG_PATH = Path(__file__).parent.parent / "config.yaml"

# Cached config to avoid repeated file reads
_config_cache: dict | None = None


def _parse_yaml_value(value: str) -> str | bool | int:
    """Parse a YAML value string into appropriate Python type."""
    value_lower = value.lower()
    if value_lower == "true":
        return True
    if value_lower == "false":
        return False
    if value.isdigit():
        return int(value)
    return value


def _parse_yaml_line(line: str, current_section: str | None, result: dict) -> str | None:
    """Parse a single YAML line, returning the current section name."""
    line = line.rstrip()
    if not line or line.startswith("#"):
        return current_section

    # Section header (no leading space, ends with colon)
    if not line.startswith(" ") and line.endswith(":"):
        section = line[:-1].strip()
        result[section] = {}
        return section

    # Key-value pair (has leading space)
    if ":" in line and current_section:
        key, value = line.split(":", 1)
        result[current_section][key.strip()] = _parse_yaml_value(value.strip())

    return current_section


def _load_yaml_simple(path: Path) -> dict:
    """Load YAML file without external dependencies."""
    if not path.exists():
        return {}
    try:
        content = path.read_text(encoding="utf-8")
        result: dict = {}
        current_section: str | None = None
        for line in content.split("\n"):
            current_section = _parse_yaml_line(line, current_section, result)
        return result
    except Exception:
        return {}


def _get_config() -> dict:
    """Load config with precedence: env vars > user config > plugin default."""
    global _config_cache
    if _config_cache is not None:
        return _config_cache

    # Start with plugin defaults
    config = _load_yaml_simple(PLUGIN_CONFIG_PATH)

    # Override with user config
    user_config = _load_yaml_simple(USER_CONFIG_PATH)
    if "llm_judge" in user_config:
        config.setdefault("llm_judge", {})
        config["llm_judge"].update(user_config["llm_judge"])

    _config_cache = config
    return config


def is_llm_judge_enabled() -> bool:
    """Check if LLM judge feature is enabled."""
    # Env var takes precedence
    env_val = os.environ.get("TIM_LLM_JUDGE_ENABLED", "").lower()
    if env_val:
        return env_val in ("true", "1", "yes")
    # Fall back to config file
    config = _get_config()
    return config.get("llm_judge", {}).get("enabled", False)


def get_llm_config() -> dict:
    """Get LLM configuration from env vars or config file."""
    config = _get_config()
    llm_config = config.get("llm_judge", {})

    return {
        "server": os.environ.get("TIM_LLM_SERVER") or llm_config.get("server", "http://localhost:11434"),
        "model": os.environ.get("TIM_LLM_MODEL") or llm_config.get("model", "llama3.1:8b"),
        "timeout": int(os.environ.get("TIM_LLM_TIMEOUT") or llm_config.get("timeout", 30)),
    }
