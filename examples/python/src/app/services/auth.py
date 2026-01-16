"""Authentication service - JWT and password handling."""

from datetime import UTC, datetime, timedelta

from jose import JWTError, jwt
from passlib.context import CryptContext

from app.config import Settings


class AuthenticationError(Exception):
    """Raised when authentication fails."""

    def __init__(self, detail: str = "Authentication failed") -> None:
        self.detail = detail
        super().__init__(detail)


class AuthService:
    """Service for authentication operations."""

    ALGORITHM = "HS256"

    def __init__(self, settings: Settings) -> None:
        self._secret = settings.jwt_secret
        self._expiry_minutes = settings.jwt_expiry_minutes
        self._pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

    def hash_password(self, password: str) -> str:
        """Hash a password using bcrypt."""
        return self._pwd_context.hash(password)

    def verify_password(self, plain: str, hashed: str) -> bool:
        """Verify a password against its hash."""
        return self._pwd_context.verify(plain, hashed)

    def create_token(self, user_id: str) -> str:
        """Create a JWT access token."""
        expire = datetime.now(UTC) + timedelta(minutes=self._expiry_minutes)
        payload = {"sub": user_id, "exp": expire}
        return jwt.encode(payload, self._secret, algorithm=self.ALGORITHM)

    def verify_token(self, token: str) -> str:
        """Verify a JWT token and return the user ID."""
        try:
            payload = jwt.decode(token, self._secret, algorithms=[self.ALGORITHM])
            user_id = payload.get("sub")
            if user_id is None:
                raise AuthenticationError("Invalid token payload")
            return str(user_id)
        except JWTError as e:
            raise AuthenticationError(f"Token validation failed: {e}") from e
