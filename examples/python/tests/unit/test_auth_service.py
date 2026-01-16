"""Tests for AuthService - test_what_when_then naming."""

import pytest

from app.config import Settings
from app.services.auth import AuthenticationError, AuthService


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


class TestHashPassword:
    """Tests for password hashing."""

    def test_hash_password_with_valid_input_returns_hash(
        self,
        auth_service: AuthService,
    ) -> None:
        """Password is hashed and not stored as plaintext."""
        password = "secure_password_123"
        hashed = auth_service.hash_password(password)

        assert hashed != password
        assert len(hashed) > 50  # bcrypt hashes are long

    def test_hash_password_with_same_input_returns_different_hashes(
        self,
        auth_service: AuthService,
    ) -> None:
        """Same password produces different hashes (salted)."""
        password = "secure_password_123"
        hash1 = auth_service.hash_password(password)
        hash2 = auth_service.hash_password(password)

        assert hash1 != hash2


class TestVerifyPassword:
    """Tests for password verification."""

    def test_verify_password_with_correct_password_returns_true(
        self,
        auth_service: AuthService,
    ) -> None:
        """Correct password verifies successfully."""
        password = "secure_password_123"
        hashed = auth_service.hash_password(password)

        assert auth_service.verify_password(password, hashed) is True

    def test_verify_password_with_incorrect_password_returns_false(
        self,
        auth_service: AuthService,
    ) -> None:
        """Incorrect password fails verification."""
        password = "secure_password_123"
        hashed = auth_service.hash_password(password)

        assert auth_service.verify_password("wrong_password", hashed) is False


class TestCreateToken:
    """Tests for JWT token creation."""

    def test_create_token_with_user_id_returns_jwt(
        self,
        auth_service: AuthService,
    ) -> None:
        """Token is created successfully."""
        user_id = "user-123"
        token = auth_service.create_token(user_id)

        assert isinstance(token, str)
        assert len(token) > 50  # JWT tokens are long


class TestVerifyToken:
    """Tests for JWT token verification."""

    def test_verify_token_with_valid_token_returns_user_id(
        self,
        auth_service: AuthService,
    ) -> None:
        """Valid token returns the user ID."""
        user_id = "user-123"
        token = auth_service.create_token(user_id)

        result = auth_service.verify_token(token)
        assert result == user_id

    def test_verify_token_with_invalid_token_raises_error(
        self,
        auth_service: AuthService,
    ) -> None:
        """Invalid token raises AuthenticationError."""
        with pytest.raises(AuthenticationError) as exc_info:
            auth_service.verify_token("invalid-token")

        assert "Token validation failed" in exc_info.value.detail

    def test_verify_token_with_tampered_token_raises_error(
        self,
        auth_service: AuthService,
    ) -> None:
        """Tampered token raises AuthenticationError."""
        token = auth_service.create_token("user-123")
        tampered = token[:-5] + "XXXXX"

        with pytest.raises(AuthenticationError):
            auth_service.verify_token(tampered)
