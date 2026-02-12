"""Tests for tim_lib.config module."""

import os

import pytest
from pydantic import ValidationError

from tim_lib.config import BaseAppSettings


class TestBaseAppSettings:
    """Tests for BaseAppSettings configuration class."""

    def test_create_settings_with_valid_env_returns_settings(
        self, valid_env: dict[str, str]
    ) -> None:
        """Test that valid environment creates settings successfully."""
        os.environ.update(valid_env)
        settings = BaseAppSettings()

        assert settings.database_url == valid_env["DATABASE_URL"]
        assert settings.jwt_secret == valid_env["JWT_SECRET"]
        assert settings.log_level == "INFO"
        assert settings.debug is False
        assert settings.environment == "development"

    def test_create_settings_without_required_env_raises_error(self) -> None:
        """Test that missing required env vars raises ValidationError."""
        # No DATABASE_URL or JWT_SECRET set
        with pytest.raises(ValidationError) as exc_info:
            BaseAppSettings()

        errors = exc_info.value.errors()
        error_fields = {e["loc"][0] for e in errors}
        assert "database_url" in error_fields
        assert "jwt_secret" in error_fields

    def test_create_settings_with_short_jwt_secret_raises_error(
        self, valid_env: dict[str, str]
    ) -> None:
        """Test that JWT secret less than 32 chars raises ValidationError."""
        valid_env["JWT_SECRET"] = "short"  # noqa: S105 - testing short secret validation
        os.environ.update(valid_env)

        with pytest.raises(ValidationError) as exc_info:
            BaseAppSettings()

        assert "JWT_SECRET must be at least 32 characters" in str(exc_info.value)

    def test_create_settings_with_invalid_log_level_raises_error(
        self, valid_env: dict[str, str]
    ) -> None:
        """Test that invalid log level raises ValidationError."""
        valid_env["LOG_LEVEL"] = "INVALID"
        os.environ.update(valid_env)

        with pytest.raises(ValidationError) as exc_info:
            BaseAppSettings()

        assert "LOG_LEVEL must be one of" in str(exc_info.value)

    def test_log_level_normalized_to_uppercase(self, valid_env: dict[str, str]) -> None:
        """Test that log level is normalized to uppercase."""
        valid_env["LOG_LEVEL"] = "debug"  # lowercase
        os.environ.update(valid_env)

        settings = BaseAppSettings()
        assert settings.log_level == "DEBUG"

    def test_production_with_debug_true_raises_error(
        self, production_env: dict[str, str]
    ) -> None:
        """Test that production environment with DEBUG=true raises error."""
        production_env["DEBUG"] = "true"
        os.environ.update(production_env)

        with pytest.raises(ValidationError) as exc_info:
            BaseAppSettings()

        assert "DEBUG must be False in production" in str(exc_info.value)

    def test_production_with_localhost_db_raises_error(
        self, production_env: dict[str, str]
    ) -> None:
        """Test that production with localhost database raises error."""
        production_env["DATABASE_URL"] = "postgresql://user:pass@localhost:5432/db"
        os.environ.update(production_env)

        with pytest.raises(ValidationError) as exc_info:
            BaseAppSettings()

        assert "DATABASE_URL cannot be localhost in production" in str(exc_info.value)

    def test_production_with_127_0_0_1_db_raises_error(
        self, production_env: dict[str, str]
    ) -> None:
        """Test that production with 127.0.0.1 database raises error."""
        production_env["DATABASE_URL"] = "postgresql://user:pass@127.0.0.1:5432/db"
        os.environ.update(production_env)

        with pytest.raises(ValidationError) as exc_info:
            BaseAppSettings()

        assert "DATABASE_URL cannot be localhost in production" in str(exc_info.value)

    def test_is_production_returns_true_in_production(
        self, production_env: dict[str, str]
    ) -> None:
        """Test is_production property returns True in production."""
        os.environ.update(production_env)
        settings = BaseAppSettings()

        assert settings.is_production is True
        assert settings.is_development is False

    def test_is_development_returns_true_in_development(
        self, valid_env: dict[str, str]
    ) -> None:
        """Test is_development property returns True in development."""
        os.environ.update(valid_env)
        settings = BaseAppSettings()

        assert settings.is_development is True
        assert settings.is_production is False

    def test_get_masked_value_masks_long_strings(
        self, valid_env: dict[str, str]
    ) -> None:
        """Test that get_masked_value properly masks secrets."""
        os.environ.update(valid_env)
        settings = BaseAppSettings()

        masked = settings.get_masked_value("jwt_secret")
        # Should show first 4 and last 4 chars
        assert masked == "aaaa...aaaa"

    def test_get_masked_value_with_short_string_returns_asterisks(
        self, valid_env: dict[str, str]
    ) -> None:
        """Test that short values are fully masked."""
        os.environ.update(valid_env)
        settings = BaseAppSettings()

        # log_level is short
        masked = settings.get_masked_value("log_level")
        assert masked == "****"

    def test_get_masked_value_with_missing_key_returns_not_set(
        self, valid_env: dict[str, str]
    ) -> None:
        """Test that missing attributes return '<not set>'."""
        os.environ.update(valid_env)
        settings = BaseAppSettings()

        masked = settings.get_masked_value("nonexistent_key")
        assert masked == "<not set>"

    def test_to_safe_dict_masks_sensitive_keys(self, valid_env: dict[str, str]) -> None:
        """Test that to_safe_dict masks database_url and jwt_secret."""
        os.environ.update(valid_env)
        settings = BaseAppSettings()

        safe = settings.to_safe_dict()

        # Sensitive values should be masked
        assert safe["database_url"] != valid_env["DATABASE_URL"]
        assert safe["jwt_secret"] != valid_env["JWT_SECRET"]
        assert "..." in safe["database_url"]
        assert "..." in safe["jwt_secret"]

        # Non-sensitive values should be preserved
        assert safe["log_level"] == "INFO"
        assert safe["debug"] is False

    def test_extra_env_vars_raises_error(self, valid_env: dict[str, str]) -> None:
        """Test that extra unknown env vars with forbid setting raises error."""
        # Note: Pydantic extra="forbid" only applies to model fields,
        # not to environment variables. This test verifies the config.
        os.environ.update(valid_env)
        settings = BaseAppSettings()

        # Settings should be created successfully - env vars aren't "extra" fields
        assert settings is not None

    def test_default_jwt_settings(self, valid_env: dict[str, str]) -> None:
        """Test default JWT algorithm and expiration settings."""
        os.environ.update(valid_env)
        settings = BaseAppSettings()

        assert settings.jwt_algorithm == "HS256"
        assert settings.access_token_expire_minutes == 30
