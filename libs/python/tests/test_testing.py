"""Tests for tim_lib.testing module."""

from typing import Any
from unittest.mock import AsyncMock, MagicMock

import pytest

from tim_lib.testing import (
    UserFactory,
    assert_response_created,
    assert_response_error,
    assert_response_ok,
    create_mock_settings,
    create_test_db_session,
)


class TestCreateMockSettings:
    """Tests for create_mock_settings function."""

    def test_create_mock_settings_returns_default_values(self) -> None:
        """Test that mock settings have sensible defaults."""
        settings = create_mock_settings()

        assert settings.database_url == "postgresql://test:test@localhost:5432/test_db"
        assert len(settings.jwt_secret) >= 32
        assert settings.jwt_algorithm == "HS256"
        assert settings.access_token_expire_minutes == 30
        assert settings.log_level == "DEBUG"
        assert settings.debug is True
        assert settings.environment == "test"

    def test_create_mock_settings_allows_overrides(self) -> None:
        """Test that settings can be overridden."""
        settings = create_mock_settings(
            debug=False,
            environment="production",
            log_level="WARNING",
        )

        assert settings.debug is False
        assert settings.environment == "production"
        assert settings.log_level == "WARNING"
        # Defaults still work
        assert settings.jwt_algorithm == "HS256"

    def test_create_mock_settings_allows_custom_values(self) -> None:
        """Test that custom values can be added."""
        settings = create_mock_settings(
            custom_setting="custom_value",
            another_setting=42,
        )

        assert settings.custom_setting == "custom_value"
        assert settings.another_setting == 42


class TestAssertResponseOk:
    """Tests for assert_response_ok function."""

    def test_assert_response_ok_passes_for_200(self) -> None:
        """Test that 200 response passes."""
        response = MagicMock()
        response.status_code = 200

        # Should not raise
        assert_response_ok(response)

    def test_assert_response_ok_passes_for_201(self) -> None:
        """Test that 201 response passes."""
        response = MagicMock()
        response.status_code = 201

        # Should not raise
        assert_response_ok(response)

    def test_assert_response_ok_passes_for_299(self) -> None:
        """Test that 299 response passes."""
        response = MagicMock()
        response.status_code = 299

        # Should not raise
        assert_response_ok(response)

    def test_assert_response_ok_fails_for_400(self) -> None:
        """Test that 400 response fails."""
        response = MagicMock()
        response.status_code = 400
        response.text = "Bad Request"

        with pytest.raises(AssertionError) as exc_info:
            assert_response_ok(response)

        assert "Expected 2xx" in str(exc_info.value)
        assert "400" in str(exc_info.value)

    def test_assert_response_ok_fails_for_500(self) -> None:
        """Test that 500 response fails."""
        response = MagicMock()
        response.status_code = 500
        response.text = "Internal Server Error"

        with pytest.raises(AssertionError):
            assert_response_ok(response)


class TestAssertResponseCreated:
    """Tests for assert_response_created function."""

    def test_assert_response_created_passes_for_201(self) -> None:
        """Test that 201 response passes."""
        response = MagicMock()
        response.status_code = 201

        # Should not raise
        assert_response_created(response)

    def test_assert_response_created_fails_for_200(self) -> None:
        """Test that 200 response fails."""
        response = MagicMock()
        response.status_code = 200
        response.text = "OK"

        with pytest.raises(AssertionError) as exc_info:
            assert_response_created(response)

        assert "Expected 201" in str(exc_info.value)

    def test_assert_response_created_fails_for_400(self) -> None:
        """Test that 400 response fails."""
        response = MagicMock()
        response.status_code = 400
        response.text = "Bad Request"

        with pytest.raises(AssertionError):
            assert_response_created(response)


class TestAssertResponseError:
    """Tests for assert_response_error function."""

    def test_assert_response_error_passes_when_matching(self) -> None:
        """Test that matching status code passes."""
        response = MagicMock()
        response.status_code = 404

        # Should not raise
        assert_response_error(response, 404)

    def test_assert_response_error_fails_when_not_matching(self) -> None:
        """Test that non-matching status code fails."""
        response = MagicMock()
        response.status_code = 500
        response.text = "Internal Server Error"

        with pytest.raises(AssertionError) as exc_info:
            assert_response_error(response, 404)

        assert "Expected 404" in str(exc_info.value)
        assert "500" in str(exc_info.value)


class TestUserFactory:
    """Tests for UserFactory class."""

    def test_build_returns_user_data(self) -> None:
        """Test that build returns user data dictionary."""
        UserFactory.reset()
        factory = UserFactory()
        user = factory.build()

        assert "email" in user
        assert "password" in user
        assert "username" in user

    def test_build_generates_unique_emails(self) -> None:
        """Test that each build generates unique email."""
        UserFactory.reset()
        factory = UserFactory()
        user1 = factory.build()
        user2 = factory.build()

        assert user1["email"] != user2["email"]

    def test_build_generates_unique_usernames(self) -> None:
        """Test that each build generates unique username."""
        UserFactory.reset()
        factory = UserFactory()
        user1 = factory.build()
        user2 = factory.build()

        assert user1["username"] != user2["username"]

    def test_build_allows_overrides(self) -> None:
        """Test that build allows field overrides."""
        factory = UserFactory()
        user = factory.build(email="custom@example.com", extra_field="value")

        assert user["email"] == "custom@example.com"
        assert user["extra_field"] == "value"

    def test_reset_resets_counter(self) -> None:
        """Test that reset resets the counter."""
        UserFactory.reset()
        factory = UserFactory()
        user1 = factory.build()

        UserFactory.reset()
        user2 = factory.build()

        # After reset, should generate same pattern
        assert user1["email"] == user2["email"]


class TestCreateTestDbSession:
    """Tests for create_test_db_session function."""

    @pytest.mark.asyncio
    async def test_create_test_db_session_yields_session(self) -> None:
        """Test that function yields an async session."""
        mock_engine = MagicMock()
        mock_session = AsyncMock()

        # Mock the async_sessionmaker and its context manager
        mock_context = AsyncMock()
        mock_context.__aenter__.return_value = mock_session
        mock_context.__aexit__.return_value = None

        with pytest.MonkeyPatch.context() as mp:
            # We need to patch at the module level
            from tim_lib import testing

            original_sessionmaker = testing.async_sessionmaker

            def mock_sessionmaker(*args: Any, **kwargs: Any) -> Any:
                return lambda: mock_context

            mp.setattr(testing, "async_sessionmaker", mock_sessionmaker)

            async for session in create_test_db_session(mock_engine):
                # Session should be yielded
                assert session is mock_session

    @pytest.mark.asyncio
    async def test_create_test_db_session_rolls_back_by_default(self) -> None:
        """Test that session is rolled back by default."""
        mock_engine = MagicMock()
        mock_session = AsyncMock()

        mock_context = AsyncMock()
        mock_context.__aenter__.return_value = mock_session
        mock_context.__aexit__.return_value = None

        with pytest.MonkeyPatch.context() as mp:
            from tim_lib import testing

            def mock_sessionmaker(*args: Any, **kwargs: Any) -> Any:
                return lambda: mock_context

            mp.setattr(testing, "async_sessionmaker", mock_sessionmaker)

            async for _ in create_test_db_session(mock_engine, rollback=True):
                pass

            mock_session.rollback.assert_awaited_once()

    @pytest.mark.asyncio
    async def test_create_test_db_session_commits_when_rollback_false(self) -> None:
        """Test that session is committed when rollback=False."""
        mock_engine = MagicMock()
        mock_session = AsyncMock()

        mock_context = AsyncMock()
        mock_context.__aenter__.return_value = mock_session
        mock_context.__aexit__.return_value = None

        with pytest.MonkeyPatch.context() as mp:
            from tim_lib import testing

            def mock_sessionmaker(*args: Any, **kwargs: Any) -> Any:
                return lambda: mock_context

            mp.setattr(testing, "async_sessionmaker", mock_sessionmaker)

            async for _ in create_test_db_session(mock_engine, rollback=False):
                pass

            mock_session.commit.assert_awaited_once()
