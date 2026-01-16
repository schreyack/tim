"""Shared test fixtures for tim_lib tests."""

import os
from collections.abc import Generator
from typing import Any

import pytest


@pytest.fixture(autouse=True)
def clean_env() -> Generator[None, None, None]:
    """Clean environment variables before and after each test."""
    # Save original env
    original_env = os.environ.copy()

    # Clear any tim-related env vars
    for key in list(os.environ.keys()):
        if key in {"DATABASE_URL", "JWT_SECRET", "LOG_LEVEL", "DEBUG", "ENVIRONMENT"}:
            del os.environ[key]

    yield

    # Restore original env
    os.environ.clear()
    os.environ.update(original_env)


@pytest.fixture
def valid_env() -> dict[str, str]:
    """Valid environment variables for testing."""
    return {
        "DATABASE_URL": "postgresql://user:pass@localhost:5432/testdb",
        "JWT_SECRET": "a" * 32,  # 32 chars minimum
        "LOG_LEVEL": "INFO",
        "DEBUG": "false",
        "ENVIRONMENT": "development",
    }


@pytest.fixture
def production_env() -> dict[str, str]:
    """Production environment variables."""
    return {
        "DATABASE_URL": "postgresql://user:pass@prod-db.example.com:5432/proddb",
        "JWT_SECRET": "b" * 64,
        "LOG_LEVEL": "WARNING",
        "DEBUG": "false",
        "ENVIRONMENT": "production",
    }


@pytest.fixture
def mock_asgi_scope() -> dict[str, Any]:
    """Mock ASGI scope for testing middleware."""
    return {
        "type": "http",
        "method": "GET",
        "path": "/test",
        "headers": [],
        "client": ("127.0.0.1", 8000),
    }
