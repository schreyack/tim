"""Tests for UserService - test_what_when_then naming."""

import pytest
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import Settings
from app.models.user import User
from app.services.auth import AuthService
from app.services.user import UserExistsError, UserNotFoundError, UserService


@pytest.fixture
def settings() -> Settings:
    """Create test settings."""
    return Settings(
        database_url="sqlite+aiosqlite:///:memory:",
        jwt_secret="test-secret-key-minimum-32-characters",
        jwt_expiry_minutes=30,
    )


@pytest.fixture
def auth_service(settings: Settings) -> AuthService:
    """Create auth service instance."""
    return AuthService(settings)


@pytest.fixture
def user_service(auth_service: AuthService) -> UserService:
    """Create user service instance."""
    return UserService(auth_service)


class TestCreateUser:
    """Tests for user creation."""

    @pytest.mark.asyncio
    async def test_create_user_with_valid_data_returns_user(
        self,
        user_service: UserService,
        test_session: AsyncSession,
    ) -> None:
        """Valid user data creates a new user."""
        user = await user_service.create_user(
            db=test_session,
            email="test@example.com",
            password="secure_password_123",
        )

        assert user.email == "test@example.com"
        assert user.id is not None
        assert user.hashed_password != "secure_password_123"

    @pytest.mark.asyncio
    async def test_create_user_with_duplicate_email_raises_error(
        self,
        user_service: UserService,
        test_session: AsyncSession,
    ) -> None:
        """Duplicate email raises UserExistsError."""
        await user_service.create_user(
            db=test_session,
            email="test@example.com",
            password="secure_password_123",
        )

        with pytest.raises(UserExistsError) as exc_info:
            await user_service.create_user(
                db=test_session,
                email="test@example.com",
                password="different_password",
            )

        assert "test@example.com" in str(exc_info.value)


class TestGetUserById:
    """Tests for getting user by ID."""

    @pytest.mark.asyncio
    async def test_get_user_by_id_with_existing_user_returns_user(
        self,
        user_service: UserService,
        test_session: AsyncSession,
    ) -> None:
        """Existing user ID returns the user."""
        created = await user_service.create_user(
            db=test_session,
            email="test@example.com",
            password="secure_password_123",
        )

        user = await user_service.get_user_by_id(test_session, str(created.id))

        assert user is not None
        assert user.email == "test@example.com"

    @pytest.mark.asyncio
    async def test_get_user_by_id_with_nonexistent_id_returns_none(
        self,
        user_service: UserService,
        test_session: AsyncSession,
    ) -> None:
        """Nonexistent user ID returns None."""
        user = await user_service.get_user_by_id(
            test_session,
            "00000000-0000-0000-0000-000000000000",
        )

        assert user is None


class TestGetUserByEmail:
    """Tests for getting user by email."""

    @pytest.mark.asyncio
    async def test_get_user_by_email_with_existing_email_returns_user(
        self,
        user_service: UserService,
        test_session: AsyncSession,
    ) -> None:
        """Existing email returns the user."""
        await user_service.create_user(
            db=test_session,
            email="test@example.com",
            password="secure_password_123",
        )

        user = await user_service.get_user_by_email(test_session, "test@example.com")

        assert user is not None
        assert user.email == "test@example.com"

    @pytest.mark.asyncio
    async def test_get_user_by_email_with_nonexistent_email_returns_none(
        self,
        user_service: UserService,
        test_session: AsyncSession,
    ) -> None:
        """Nonexistent email returns None."""
        user = await user_service.get_user_by_email(
            test_session,
            "nonexistent@example.com",
        )

        assert user is None


class TestAuthenticate:
    """Tests for user authentication."""

    @pytest.mark.asyncio
    async def test_authenticate_with_valid_credentials_returns_user(
        self,
        user_service: UserService,
        test_session: AsyncSession,
    ) -> None:
        """Valid credentials return the authenticated user."""
        await user_service.create_user(
            db=test_session,
            email="test@example.com",
            password="secure_password_123",
        )

        user = await user_service.authenticate(
            db=test_session,
            email="test@example.com",
            password="secure_password_123",
        )

        assert user is not None
        assert user.email == "test@example.com"

    @pytest.mark.asyncio
    async def test_authenticate_with_wrong_password_returns_none(
        self,
        user_service: UserService,
        test_session: AsyncSession,
    ) -> None:
        """Wrong password returns None."""
        await user_service.create_user(
            db=test_session,
            email="test@example.com",
            password="secure_password_123",
        )

        user = await user_service.authenticate(
            db=test_session,
            email="test@example.com",
            password="wrong_password",
        )

        assert user is None

    @pytest.mark.asyncio
    async def test_authenticate_with_nonexistent_email_returns_none(
        self,
        user_service: UserService,
        test_session: AsyncSession,
    ) -> None:
        """Nonexistent email returns None."""
        user = await user_service.authenticate(
            db=test_session,
            email="nonexistent@example.com",
            password="any_password",
        )

        assert user is None


class TestDeleteUser:
    """Tests for user deletion."""

    @pytest.mark.asyncio
    async def test_delete_user_with_existing_user_removes_user(
        self,
        user_service: UserService,
        test_session: AsyncSession,
    ) -> None:
        """Existing user is deleted successfully."""
        created = await user_service.create_user(
            db=test_session,
            email="test@example.com",
            password="secure_password_123",
        )

        await user_service.delete_user(test_session, str(created.id))

        user = await user_service.get_user_by_id(test_session, str(created.id))
        assert user is None

    @pytest.mark.asyncio
    async def test_delete_user_with_nonexistent_id_raises_error(
        self,
        user_service: UserService,
        test_session: AsyncSession,
    ) -> None:
        """Nonexistent user ID raises UserNotFoundError."""
        with pytest.raises(UserNotFoundError):
            await user_service.delete_user(
                test_session,
                "00000000-0000-0000-0000-000000000000",
            )
