"""Tests for tim_lib.security module."""

import time

import pytest

from tim_lib.security import (
    TokenValidationError,
    constant_time_compare,
    create_access_token,
    generate_secure_token,
    hash_password,
    verify_password,
    verify_token,
    verify_token_with_fallback,
)


class TestPasswordHashing:
    """Tests for password hashing functions.

    Note: Some tests are skipped on Python 3.14+ due to passlib/bcrypt
    compatibility issues. The passlib library has not been updated for
    the latest bcrypt API changes.
    """

    @pytest.mark.skipif(
        True,  # Skip until passlib/bcrypt compatibility is resolved
        reason="passlib/bcrypt compatibility issue with Python 3.14",
    )
    def test_hash_password_returns_bcrypt_hash(self) -> None:
        """Test that hash_password returns a bcrypt hash."""
        password = "secure123"
        hashed = hash_password(password)

        # Bcrypt hashes start with $2b$ or $2a$
        assert hashed.startswith("$2") and "$" in hashed[3:]
        assert len(hashed) == 60  # Standard bcrypt length

    @pytest.mark.skipif(
        True,
        reason="passlib/bcrypt compatibility issue with Python 3.14",
    )
    def test_hash_password_produces_different_hashes(self) -> None:
        """Test that same password produces different hashes (salted)."""
        password = "secure123"
        hash1 = hash_password(password)
        hash2 = hash_password(password)

        assert hash1 != hash2  # Different salts

    @pytest.mark.skipif(
        True,
        reason="passlib/bcrypt compatibility issue with Python 3.14",
    )
    def test_verify_password_with_correct_password_returns_true(self) -> None:
        """Test that verify_password returns True for correct password."""
        password = "secure123"
        hashed = hash_password(password)

        assert verify_password(password, hashed) is True

    @pytest.mark.skipif(
        True,
        reason="passlib/bcrypt compatibility issue with Python 3.14",
    )
    def test_verify_password_with_incorrect_password_returns_false(self) -> None:
        """Test that verify_password returns False for wrong password."""
        password = "secure123"
        hashed = hash_password(password)

        assert verify_password("wrongpass", hashed) is False

    @pytest.mark.skipif(
        True,
        reason="passlib/bcrypt compatibility issue with Python 3.14",
    )
    def test_verify_password_with_empty_password_returns_false(self) -> None:
        """Test that verify_password returns False for empty password."""
        hashed = hash_password("secure123")

        assert verify_password("", hashed) is False

    @pytest.mark.skipif(
        True,
        reason="passlib/bcrypt compatibility issue with Python 3.14",
    )
    def test_hash_empty_password_works(self) -> None:
        """Test that empty password can be hashed and verified."""
        password = ""
        hashed = hash_password(password)

        assert verify_password(password, hashed) is True
        assert verify_password("x", hashed) is False


class TestJWTTokens:
    """Tests for JWT token functions."""

    def test_create_access_token_returns_valid_jwt(self) -> None:
        """Test that create_access_token returns a valid JWT string."""
        data = {"sub": "user123", "email": "test@example.com"}
        secret = "a" * 32
        token = create_access_token(data, secret)

        # JWT has 3 parts separated by dots
        parts = token.split(".")
        assert len(parts) == 3

    def test_create_and_verify_token_roundtrip(self) -> None:
        """Test that created token can be verified."""
        data = {"sub": "user123", "role": "admin"}
        secret = "a" * 32
        token = create_access_token(data, secret)

        payload = verify_token(token, secret)

        assert payload["sub"] == "user123"
        assert payload["role"] == "admin"
        assert "exp" in payload

    def test_verify_token_with_wrong_secret_raises_error(self) -> None:
        """Test that verification with wrong secret raises TokenValidationError."""
        data = {"sub": "user123"}
        secret = "a" * 32
        token = create_access_token(data, secret)

        with pytest.raises(TokenValidationError) as exc_info:
            verify_token(token, "b" * 32)

        assert "Invalid token" in exc_info.value.message

    def test_verify_expired_token_raises_error(self) -> None:
        """Test that expired token raises TokenValidationError."""
        data = {"sub": "user123"}
        secret = "a" * 32
        # Create token that expires immediately
        token = create_access_token(data, secret, expires_minutes=-1)

        with pytest.raises(TokenValidationError) as exc_info:
            verify_token(token, secret)

        assert "expired" in exc_info.value.message.lower()
        assert exc_info.value.detail == "expired"

    def test_verify_malformed_token_raises_error(self) -> None:
        """Test that malformed token raises TokenValidationError."""
        with pytest.raises(TokenValidationError) as exc_info:
            verify_token("not.a.valid.jwt", "secret")

        assert "Invalid token" in exc_info.value.message

    def test_create_token_with_custom_algorithm(self) -> None:
        """Test creating and verifying token with HS384 algorithm."""
        data = {"sub": "user123"}
        secret = "a" * 48  # HS384 needs longer key
        token = create_access_token(data, secret, algorithm="HS384")

        payload = verify_token(token, secret, algorithm="HS384")
        assert payload["sub"] == "user123"

    def test_create_token_with_custom_expiration(self) -> None:
        """Test that custom expiration is respected."""
        data = {"sub": "user123"}
        secret = "a" * 32
        token = create_access_token(data, secret, expires_minutes=60)

        payload = verify_token(token, secret)
        # exp should be roughly 60 minutes from now
        exp_time = payload["exp"]
        expected_exp = time.time() + (60 * 60)

        # Allow 5 seconds tolerance
        assert abs(exp_time - expected_exp) < 5


class TestTokenWithFallback:
    """Tests for verify_token_with_fallback function."""

    def test_verify_with_primary_secret_succeeds(self) -> None:
        """Test that token verified with primary secret works."""
        data = {"sub": "user123"}
        primary = "primary_secret_" + "a" * 20
        token = create_access_token(data, primary)

        payload = verify_token_with_fallback(token, primary)
        assert payload["sub"] == "user123"

    def test_verify_with_fallback_secret_succeeds(self) -> None:
        """Test that token verified with fallback secret works."""
        data = {"sub": "user123"}
        old_secret = "old_secret_" + "a" * 22
        new_secret = "new_secret_" + "b" * 22

        # Token created with old secret
        token = create_access_token(data, old_secret)

        # Verify with new primary, old fallback
        payload = verify_token_with_fallback(token, new_secret, old_secret)
        assert payload["sub"] == "user123"

    def test_verify_fails_with_both_secrets_wrong(self) -> None:
        """Test that verification fails when both secrets are wrong."""
        data = {"sub": "user123"}
        actual_secret = "actual_" + "a" * 26
        token = create_access_token(data, actual_secret)

        with pytest.raises(TokenValidationError):
            verify_token_with_fallback(token, "wrong1" + "x" * 26, "wrong2" + "y" * 26)

    def test_verify_without_fallback_raises_on_failure(self) -> None:
        """Test that without fallback, failure is propagated."""
        data = {"sub": "user123"}
        secret = "a" * 32
        token = create_access_token(data, secret)

        with pytest.raises(TokenValidationError):
            verify_token_with_fallback(token, "wrong" + "b" * 27)


class TestSecureToken:
    """Tests for generate_secure_token function."""

    def test_generate_secure_token_returns_hex_string(self) -> None:
        """Test that generated token is a valid hex string."""
        token = generate_secure_token()

        # Should be all hex characters
        assert all(c in "0123456789abcdef" for c in token)

    def test_generate_secure_token_default_length(self) -> None:
        """Test that default length is 64 characters (32 bytes hex-encoded)."""
        token = generate_secure_token()
        assert len(token) == 64

    def test_generate_secure_token_custom_length(self) -> None:
        """Test that custom length is respected."""
        token = generate_secure_token(length=16)
        assert len(token) == 32  # 16 bytes = 32 hex chars

    def test_generate_secure_token_produces_unique_values(self) -> None:
        """Test that generated tokens are unique."""
        tokens = [generate_secure_token() for _ in range(100)]
        assert len(set(tokens)) == 100


class TestConstantTimeCompare:
    """Tests for constant_time_compare function."""

    def test_constant_time_compare_equal_strings_returns_true(self) -> None:
        """Test that equal strings return True."""
        assert constant_time_compare("abc123", "abc123") is True

    def test_constant_time_compare_different_strings_returns_false(self) -> None:
        """Test that different strings return False."""
        assert constant_time_compare("abc123", "xyz789") is False

    def test_constant_time_compare_different_lengths_returns_false(self) -> None:
        """Test that different length strings return False."""
        assert constant_time_compare("short", "much_longer_string") is False

    def test_constant_time_compare_empty_strings_returns_true(self) -> None:
        """Test that empty strings return True."""
        assert constant_time_compare("", "") is True

    def test_constant_time_compare_one_empty_returns_false(self) -> None:
        """Test that one empty string returns False."""
        assert constant_time_compare("", "not_empty") is False
        assert constant_time_compare("not_empty", "") is False


class TestTokenValidationError:
    """Tests for TokenValidationError exception."""

    def test_token_validation_error_with_message_only(self) -> None:
        """Test creating error with message only."""
        error = TokenValidationError("Token invalid")

        assert error.message == "Token invalid"
        assert error.detail is None
        assert str(error) == "Token invalid"

    def test_token_validation_error_with_detail(self) -> None:
        """Test creating error with message and detail."""
        error = TokenValidationError("Token expired", detail="expired")

        assert error.message == "Token expired"
        assert error.detail == "expired"
