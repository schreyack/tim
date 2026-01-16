"""TIM Shared Configuration Module.

Provides a base settings class with common patterns for all TIM projects.
Projects should extend BaseAppSettings for their specific configuration.

Example:
    from tim_lib import BaseAppSettings

    class Settings(BaseAppSettings):
        stripe_api_key: str
        feature_flag_x: bool = False

    settings = Settings()
"""

from typing import Any

from pydantic import field_validator, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class BaseAppSettings(BaseSettings):
    """Base configuration class for TIM applications.

    Provides common settings that all TIM applications need.
    Extend this class and add project-specific settings.

    Required environment variables:
        - DATABASE_URL: PostgreSQL connection string
        - JWT_SECRET: Secret key for JWT signing (min 32 chars)

    Optional environment variables:
        - LOG_LEVEL: Logging level (default: INFO)
        - DEBUG: Enable debug mode (default: False)
        - ENVIRONMENT: Environment name (default: development)
    """

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=False,
        extra="forbid",  # Reject unknown settings
    )

    # Required settings (no defaults)
    database_url: str
    jwt_secret: str

    # Optional settings with safe defaults
    log_level: str = "INFO"
    debug: bool = False
    environment: str = "development"

    # JWT settings
    jwt_algorithm: str = "HS256"
    access_token_expire_minutes: int = 30

    @field_validator("jwt_secret")
    @classmethod
    def validate_jwt_secret(cls, v: str) -> str:
        """Ensure JWT secret meets minimum security requirements."""
        if len(v) < 32:
            msg = "JWT_SECRET must be at least 32 characters"
            raise ValueError(msg)
        return v

    @field_validator("log_level")
    @classmethod
    def validate_log_level(cls, v: str) -> str:
        """Ensure log level is valid."""
        valid_levels = {"DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"}
        if v.upper() not in valid_levels:
            msg = f"LOG_LEVEL must be one of: {valid_levels}"
            raise ValueError(msg)
        return v.upper()

    @model_validator(mode="after")
    def validate_production_settings(self) -> "BaseAppSettings":
        """Validate settings are appropriate for production."""
        if self.environment == "production":
            if self.debug:
                msg = "DEBUG must be False in production"
                raise ValueError(msg)
            if "localhost" in self.database_url or "127.0.0.1" in self.database_url:
                msg = "DATABASE_URL cannot be localhost in production"
                raise ValueError(msg)
        return self

    @property
    def is_production(self) -> bool:
        """Check if running in production environment."""
        return self.environment == "production"

    @property
    def is_development(self) -> bool:
        """Check if running in development environment."""
        return self.environment == "development"

    def get_masked_value(self, key: str) -> str:
        """Get a masked version of a secret value for logging."""
        value = getattr(self, key, None)
        if value is None:
            return "<not set>"
        if isinstance(value, str) and len(value) > 8:
            return f"{value[:4]}...{value[-4:]}"
        return "****"

    def to_safe_dict(self) -> dict[str, Any]:
        """Return settings dict with secrets masked (safe for logging)."""
        sensitive_keys = {"database_url", "jwt_secret"}
        result: dict[str, Any] = {}
        for key, value in self.model_dump().items():
            if key in sensitive_keys:
                result[key] = self.get_masked_value(key)
            else:
                result[key] = value
        return result
