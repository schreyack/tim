"""TIM Shared Python Library.

Provides common utilities for all TIM Python projects:
- config: Pydantic base settings
- logging: Structured logging setup
- security: Password hashing, JWT helpers
- db: Database session patterns
- api: FastAPI middleware and error handlers
- testing: Test fixtures and utilities
"""

__version__ = "1.0.0"

from tim_lib.config import BaseAppSettings
from tim_lib.logging import configure_logging, get_logger
from tim_lib.security import (
    create_access_token,
    hash_password,
    verify_password,
    verify_token,
)

__all__ = [
    # Config
    "BaseAppSettings",
    # Logging
    "configure_logging",
    "get_logger",
    # Security
    "hash_password",
    "verify_password",
    "create_access_token",
    "verify_token",
]
