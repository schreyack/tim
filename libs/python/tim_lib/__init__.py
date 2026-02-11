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

from tim_lib.api import (
    AppError,
    ConflictError,
    ForbiddenError,
    NotFoundError,
    RateLimitMiddleware,
    UnauthorizedError,
    ValidationError,
    create_health_router,
    security_headers_middleware,
    setup_exception_handlers,
)
from tim_lib.config import BaseAppSettings
from tim_lib.db import (
    Base,
    DatabaseHealthCheck,
    create_async_engine_with_pool,
    dependency_get_db,
    get_db_session,
    get_session_factory,
)
from tim_lib.logging import configure_logging, get_logger
from tim_lib.security import (
    TokenValidationError,
    create_access_token,
    hash_password,
    verify_password,
    verify_token,
)

__all__ = [
    # API
    "AppError",
    # Database
    "Base",
    # Config
    "BaseAppSettings",
    "ConflictError",
    "DatabaseHealthCheck",
    "ForbiddenError",
    "NotFoundError",
    "RateLimitMiddleware",
    "TokenValidationError",
    "UnauthorizedError",
    "ValidationError",
    # Logging
    "configure_logging",
    "create_access_token",
    "create_async_engine_with_pool",
    "create_health_router",
    "dependency_get_db",
    "get_db_session",
    "get_logger",
    "get_session_factory",
    # Security
    "hash_password",
    "security_headers_middleware",
    "setup_exception_handlers",
    "verify_password",
    "verify_token",
]
