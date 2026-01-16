"""User service - business logic for user operations."""

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import User
from app.schemas import UserCreate, UserUpdate
from app.services.auth import AuthService


class UserNotFoundError(Exception):
    """Raised when a user is not found."""

    pass


class UserExistsError(Exception):
    """Raised when attempting to create a user that already exists."""

    pass


class UserService:
    """Service for user operations."""

    def __init__(self, session: AsyncSession, auth: AuthService) -> None:
        self._session = session
        self._auth = auth

    async def get_by_id(self, user_id: str) -> User:
        """Get a user by ID."""
        result = await self._session.execute(
            select(User).where(User.id == user_id)
        )
        user = result.scalar_one_or_none()
        if user is None:
            raise UserNotFoundError(f"User not found: {user_id}")
        return user

    async def get_by_email(self, email: str) -> User | None:
        """Get a user by email (returns None if not found)."""
        result = await self._session.execute(
            select(User).where(User.email == email)
        )
        return result.scalar_one_or_none()

    async def create(self, data: UserCreate) -> User:
        """Create a new user."""
        existing = await self.get_by_email(data.email)
        if existing is not None:
            raise UserExistsError(f"User already exists: {data.email}")

        user = User(
            email=data.email,
            name=data.name,
            hashed_password=self._auth.hash_password(data.password),
        )
        self._session.add(user)
        await self._session.flush()
        await self._session.refresh(user)
        return user

    async def update(self, user_id: str, data: UserUpdate) -> User:
        """Update an existing user."""
        user = await self.get_by_id(user_id)

        if data.name is not None:
            user.name = data.name
        if data.password is not None:
            user.hashed_password = self._auth.hash_password(data.password)

        await self._session.flush()
        await self._session.refresh(user)
        return user

    async def authenticate(self, email: str, password: str) -> User:
        """Authenticate a user by email and password."""
        user = await self.get_by_email(email)
        if user is None:
            raise UserNotFoundError("Invalid credentials")

        if not self._auth.verify_password(password, user.hashed_password):
            raise UserNotFoundError("Invalid credentials")

        return user
