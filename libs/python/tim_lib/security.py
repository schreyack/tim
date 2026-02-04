"""TIM Shared Security Module.

Provides secure password hashing and JWT token handling.
Uses bcrypt for passwords and PyJWT for JWTs.

NEVER roll your own crypto. Use these helpers.

Example:
    from tim_lib import hash_password, verify_password, create_access_token

    # Password handling
    hashed = hash_password("user_password")
    is_valid = verify_password("user_password", hashed)

    # JWT handling
    token = create_access_token(
        data={"sub": "user_id"},
        secret="your-secret",
        expires_minutes=30
    )
"""

from datetime import UTC, datetime, timedelta
from typing import Any, cast

import jwt
from jwt import ExpiredSignatureError, InvalidTokenError
from passlib.context import CryptContext  # type: ignore[import-untyped]

# Password hashing context (bcrypt with secure defaults)
_pwd_context = CryptContext(
    schemes=["bcrypt"],
    deprecated="auto",
    bcrypt__rounds=12,  # Secure default
)


def hash_password(password: str) -> str:
    """Hash a password using bcrypt.

    Args:
        password: Plain text password to hash.

    Returns:
        Hashed password string (includes salt).

    Example:
        hashed = hash_password("my_secure_password")
        # Store hashed in database
    """
    return cast(str, _pwd_context.hash(password))


def verify_password(plain_password: str, hashed_password: str) -> bool:
    """Verify a password against a hash.

    Uses constant-time comparison to prevent timing attacks.

    Args:
        plain_password: Plain text password to verify.
        hashed_password: Previously hashed password.

    Returns:
        True if password matches, False otherwise.

    Example:
        if verify_password(user_input, stored_hash):
            # Password correct
    """
    return cast(bool, _pwd_context.verify(plain_password, hashed_password))


def create_access_token(
    data: dict[str, Any],
    secret: str,
    expires_minutes: int = 30,
    algorithm: str = "HS256",
) -> str:
    """Create a JWT access token.

    Args:
        data: Payload data to encode in the token.
        secret: Secret key for signing (min 32 chars recommended).
        expires_minutes: Token expiration time in minutes.
        algorithm: JWT algorithm to use (default: HS256).

    Returns:
        Encoded JWT token string.

    Example:
        token = create_access_token(
            data={"sub": str(user.id), "email": user.email},
            secret=settings.jwt_secret,
            expires_minutes=settings.access_token_expire_minutes,
        )
    """
    to_encode = data.copy()
    expire = datetime.now(UTC) + timedelta(minutes=expires_minutes)
    to_encode.update({"exp": expire})
    token = jwt.encode(to_encode, secret, algorithm=algorithm)
    return token if isinstance(token, str) else token.decode("utf-8")


class TokenValidationError(Exception):
    """Raised when JWT token validation fails."""

    def __init__(self, message: str, detail: str | None = None) -> None:
        self.message = message
        self.detail = detail
        super().__init__(message)


def verify_token(
    token: str,
    secret: str,
    algorithm: str = "HS256",
) -> dict[str, Any]:
    """Verify and decode a JWT token.

    Args:
        token: JWT token string to verify.
        secret: Secret key used for signing.
        algorithm: JWT algorithm used.

    Returns:
        Decoded token payload.

    Raises:
        TokenValidationError: If token is invalid, expired, or malformed.

    Example:
        try:
            payload = verify_token(token, settings.jwt_secret)
            user_id = payload["sub"]
        except TokenValidationError:
            raise HTTPException(status_code=401)
    """
    try:
        payload: dict[str, Any] = jwt.decode(token, secret, algorithms=[algorithm])
        return payload
    except ExpiredSignatureError:
        raise TokenValidationError("Token has expired", detail="expired") from None
    except InvalidTokenError as e:
        raise TokenValidationError("Invalid token", detail=str(e)) from e


def verify_token_with_fallback(
    token: str,
    primary_secret: str,
    fallback_secret: str | None = None,
    algorithm: str = "HS256",
) -> dict[str, Any]:
    """Verify token with fallback to previous secret (for key rotation).

    Useful during secret rotation periods when tokens signed with
    the old secret may still be valid.

    Args:
        token: JWT token string to verify.
        primary_secret: Current secret key.
        fallback_secret: Previous secret key (during rotation).
        algorithm: JWT algorithm used.

    Returns:
        Decoded token payload.

    Raises:
        TokenValidationError: If token is invalid with both secrets.

    Example:
        payload = verify_token_with_fallback(
            token,
            primary_secret=settings.jwt_secret,
            fallback_secret=settings.jwt_secret_previous,
        )
    """
    try:
        return verify_token(token, primary_secret, algorithm)
    except TokenValidationError:
        if fallback_secret:
            return verify_token(token, fallback_secret, algorithm)
        raise


def generate_secure_token(length: int = 32) -> str:
    """Generate a cryptographically secure random token.

    Useful for password reset tokens, email verification, etc.

    Args:
        length: Number of random bytes (output will be 2x this in hex).

    Returns:
        Hex-encoded random token string.

    Example:
        reset_token = generate_secure_token(32)
        # Returns 64-character hex string
    """
    import secrets

    return secrets.token_hex(length)


def constant_time_compare(a: str, b: str) -> bool:
    """Compare two strings in constant time.

    Prevents timing attacks when comparing sensitive values.

    Args:
        a: First string.
        b: Second string.

    Returns:
        True if strings are equal, False otherwise.
    """
    import hmac

    return hmac.compare_digest(a, b)
