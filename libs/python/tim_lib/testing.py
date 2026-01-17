"""TIM Shared Testing Module.

Provides test fixtures and utilities for all TIM Python projects.

Example:
    from tim_lib.testing import AsyncTestClient, create_test_db_session

    @pytest.fixture
    async def db():
        async for session in create_test_db_session(engine):
            yield session

    @pytest.fixture
    async def client(db):
        async for c in AsyncTestClient(app, db_override=db):
            yield c
"""

from collections.abc import AsyncGenerator
from typing import Any
from unittest.mock import MagicMock

from sqlalchemy.ext.asyncio import AsyncEngine, AsyncSession, async_sessionmaker


async def create_test_db_session(
    engine: AsyncEngine,
    rollback: bool = True,
) -> AsyncGenerator[AsyncSession, None]:
    """Create a test database session with optional rollback.

    Each test gets an isolated session that can be rolled back
    to prevent test pollution.

    Args:
        engine: AsyncEngine connected to test database.
        rollback: If True, rollback after test (default). If False, commit.

    Yields:
        AsyncSession for test use.

    Example:
        @pytest.fixture
        async def db_session():
            async for session in create_test_db_session(test_engine):
                yield session
    """
    async_session = async_sessionmaker(
        engine,
        class_=AsyncSession,
        expire_on_commit=False,
    )

    async with async_session() as session:
        try:
            yield session
        finally:
            if rollback:
                await session.rollback()
            else:
                await session.commit()


class AsyncTestClient:
    """Test client wrapper for FastAPI applications.

    Provides async context manager that sets up app with test dependencies.

    Example:
        @pytest.fixture
        async def client(db_session):
            async for c in AsyncTestClient(app, db_override=db_session):
                yield c

        async def test_get_users(client):
            response = await client.get("/users")
            assert response.status_code == 200
    """

    def __init__(
        self,
        app: Any,
        db_override: AsyncSession | None = None,
        base_url: str = "http://test",
    ) -> None:
        self.app = app
        self.db_override = db_override
        self.base_url = base_url
        self._client: Any = None

    async def __aiter__(self) -> AsyncGenerator[Any, None]:
        from httpx import AsyncClient

        # Store original overrides
        original_overrides = self.app.dependency_overrides.copy()

        # Set db override if provided
        if self.db_override:
            # Find the get_db dependency and override it

            async def override_get_db() -> AsyncGenerator[AsyncSession, None]:
                yield self.db_override  # type: ignore

            # This assumes the app uses a function named get_db
            # You may need to adjust based on your app structure
            for key in list(self.app.dependency_overrides.keys()):
                if "get_db" in str(key):
                    self.app.dependency_overrides[key] = override_get_db

        try:
            from httpx import ASGITransport

            transport = ASGITransport(app=self.app)
            async with AsyncClient(
                transport=transport, base_url=self.base_url
            ) as client:
                yield client
        finally:
            # Restore original overrides
            self.app.dependency_overrides = original_overrides


def create_mock_settings(**overrides: Any) -> Any:
    """Create mock settings for testing.

    Provides sensible test defaults that can be overridden.

    Args:
        **overrides: Settings to override from defaults.

    Returns:
        Mock settings object.

    Example:
        settings = create_mock_settings(
            jwt_secret="test-secret-at-least-32-characters",
            debug=True,
        )
    """
    defaults = {
        "database_url": "postgresql://test:test@localhost:5432/test_db",
        "jwt_secret": "test-jwt-secret-must-be-32-chars-long",
        "jwt_algorithm": "HS256",
        "access_token_expire_minutes": 30,
        "log_level": "DEBUG",
        "debug": True,
        "environment": "test",
    }
    defaults.update(overrides)

    mock = MagicMock()
    for key, value in defaults.items():
        setattr(mock, key, value)
    return mock


def assert_response_ok(response: Any) -> None:
    """Assert response has 2xx status code.

    Args:
        response: httpx Response object.

    Raises:
        AssertionError: If status code is not 2xx.
    """
    assert (
        200 <= response.status_code < 300
    ), f"Expected 2xx, got {response.status_code}: {response.text}"


def assert_response_created(response: Any) -> None:
    """Assert response has 201 status code.

    Args:
        response: httpx Response object.

    Raises:
        AssertionError: If status code is not 201.
    """
    assert (
        response.status_code == 201
    ), f"Expected 201, got {response.status_code}: {response.text}"


def assert_response_error(response: Any, status_code: int) -> None:
    """Assert response has specific error status code.

    Args:
        response: httpx Response object.
        status_code: Expected status code.

    Raises:
        AssertionError: If status code doesn't match.
    """
    assert (
        response.status_code == status_code
    ), f"Expected {status_code}, got {response.status_code}: {response.text}"


class UserFactory:
    """Factory for creating test user data.

    Example:
        factory = UserFactory()
        user_data = factory.build()  # Returns dict
        user_data = factory.build(email="custom@example.com")  # Override fields
    """

    _counter: int = 0

    def build(self, **overrides: Any) -> dict[str, Any]:
        """Build user data dictionary.

        Args:
            **overrides: Fields to override from defaults.

        Returns:
            User data dictionary.
        """
        UserFactory._counter += 1
        defaults = {
            "email": f"user{UserFactory._counter}@example.com",
            "password": "secure_password_123",
            "username": f"user{UserFactory._counter}",
        }
        defaults.update(overrides)
        return defaults

    @classmethod
    def reset(cls) -> None:
        """Reset counter (call in test cleanup)."""
        cls._counter = 0
