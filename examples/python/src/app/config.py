"""Application configuration using Pydantic Settings."""

from functools import lru_cache

from pydantic import Field, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Application settings loaded from environment variables."""

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=False,
    )

    # Database
    database_url: str = Field(
        ...,
        description="PostgreSQL connection URL",
    )

    # Security
    jwt_secret: str = Field(
        ...,
        min_length=32,
        description="Secret key for JWT signing (min 32 chars)",
    )
    jwt_expiry_minutes: int = Field(
        default=30,
        ge=1,
        le=1440,
        description="JWT token expiry in minutes",
    )

    # Application
    environment: str = Field(
        default="development",
        pattern="^(development|staging|production)$",
    )
    debug: bool = Field(default=False)
    log_level: str = Field(default="INFO")

    @field_validator("debug")
    @classmethod
    def no_debug_in_production(cls, v: bool, info: object) -> bool:
        """Prevent debug mode in production."""
        # Access other values via info.data in Pydantic v2
        data = getattr(info, "data", {})
        if data.get("environment") == "production" and v:
            raise ValueError("Debug mode not allowed in production")
        return v


@lru_cache
def get_settings() -> Settings:
    """Get cached settings instance."""
    return Settings()
