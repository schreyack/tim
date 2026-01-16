"""Tests for tim_lib.db module."""

from typing import Any
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from sqlalchemy.ext.asyncio import AsyncEngine, AsyncSession

from tim_lib.db import (
    Base,
    DatabaseHealthCheck,
    create_async_engine_with_pool,
    dependency_get_db,
    get_db_session,
    get_session_factory,
)


class TestBase:
    """Tests for Base declarative class."""

    def test_base_is_declarative_base(self) -> None:
        """Test that Base is a valid SQLAlchemy declarative base."""
        # Base should be usable as a base class for models
        assert hasattr(Base, "metadata")
        assert hasattr(Base, "registry")


class TestCreateAsyncEngineWithPool:
    """Tests for create_async_engine_with_pool function."""

    def test_postgresql_url_converted_to_asyncpg(self) -> None:
        """Test that postgresql:// is converted to postgresql+asyncpg://."""
        url = "postgresql://user:pass@localhost:5432/testdb"

        with patch("tim_lib.db.create_async_engine") as mock_create:
            mock_create.return_value = MagicMock()
            create_async_engine_with_pool(url)

            called_url = mock_create.call_args[0][0]
            assert called_url.startswith("postgresql+asyncpg://")

    def test_asyncpg_url_unchanged(self) -> None:
        """Test that postgresql+asyncpg:// URL is not modified."""
        url = "postgresql+asyncpg://user:pass@localhost:5432/testdb"

        with patch("tim_lib.db.create_async_engine") as mock_create:
            mock_create.return_value = MagicMock()
            create_async_engine_with_pool(url)

            called_url = mock_create.call_args[0][0]
            assert called_url == url

    def test_engine_created_with_pool_settings(self) -> None:
        """Test that pool settings are passed to engine."""
        url = "postgresql://user:pass@localhost:5432/testdb"

        with patch("tim_lib.db.create_async_engine") as mock_create:
            mock_create.return_value = MagicMock()
            create_async_engine_with_pool(
                url,
                pool_size=20,
                max_overflow=5,
                pool_pre_ping=False,
                echo=True,
            )

            mock_create.assert_called_once()
            kwargs = mock_create.call_args[1]
            assert kwargs["pool_size"] == 20
            assert kwargs["max_overflow"] == 5
            assert kwargs["pool_pre_ping"] is False
            assert kwargs["echo"] is True

    def test_default_pool_settings(self) -> None:
        """Test default pool settings are applied."""
        url = "postgresql://user:pass@localhost:5432/testdb"

        with patch("tim_lib.db.create_async_engine") as mock_create:
            mock_create.return_value = MagicMock()
            create_async_engine_with_pool(url)

            kwargs = mock_create.call_args[1]
            assert kwargs["pool_size"] == 5
            assert kwargs["max_overflow"] == 10
            assert kwargs["pool_pre_ping"] is True
            assert kwargs["echo"] is False


class TestGetSessionFactory:
    """Tests for get_session_factory function."""

    def test_returns_session_maker(self) -> None:
        """Test that function returns an async session maker."""
        mock_engine = MagicMock(spec=AsyncEngine)
        factory = get_session_factory(mock_engine)

        # Should be callable (session factory)
        assert callable(factory)


class TestGetDbSession:
    """Tests for get_db_session context manager."""

    @pytest.mark.asyncio
    async def test_session_commits_on_success(self) -> None:
        """Test that session is committed on successful exit."""
        mock_session = AsyncMock(spec=AsyncSession)
        mock_factory = MagicMock()
        mock_factory.return_value = mock_session

        async with get_db_session(mock_factory):
            pass

        mock_session.commit.assert_awaited_once()
        mock_session.close.assert_awaited_once()

    @pytest.mark.asyncio
    async def test_session_rolls_back_on_exception(self) -> None:
        """Test that session is rolled back on exception."""
        mock_session = AsyncMock(spec=AsyncSession)
        mock_factory = MagicMock()
        mock_factory.return_value = mock_session

        with pytest.raises(ValueError):
            async with get_db_session(mock_factory):
                raise ValueError("Test error")

        mock_session.rollback.assert_awaited_once()
        mock_session.commit.assert_not_awaited()
        mock_session.close.assert_awaited_once()

    @pytest.mark.asyncio
    async def test_session_closed_even_on_exception(self) -> None:
        """Test that session is always closed."""
        mock_session = AsyncMock(spec=AsyncSession)
        mock_factory = MagicMock()
        mock_factory.return_value = mock_session

        try:
            async with get_db_session(mock_factory):
                raise RuntimeError("Unexpected")
        except RuntimeError:
            pass

        mock_session.close.assert_awaited_once()


class TestDatabaseHealthCheck:
    """Tests for DatabaseHealthCheck class."""

    @pytest.fixture
    def mock_engine(self) -> AsyncMock:
        """Create a mock async engine."""
        return AsyncMock(spec=AsyncEngine)

    @pytest.mark.asyncio
    async def test_is_healthy_returns_true_on_success(
        self, mock_engine: AsyncMock
    ) -> None:
        """Test that is_healthy returns True when query succeeds."""
        mock_conn = AsyncMock()
        mock_engine.connect.return_value.__aenter__.return_value = mock_conn

        health_check = DatabaseHealthCheck(mock_engine)
        result = await health_check.is_healthy()

        assert result is True
        mock_conn.execute.assert_awaited_once()

    @pytest.mark.asyncio
    async def test_is_healthy_returns_false_on_failure(
        self, mock_engine: AsyncMock
    ) -> None:
        """Test that is_healthy returns False when query fails."""
        mock_engine.connect.side_effect = Exception("Connection failed")

        health_check = DatabaseHealthCheck(mock_engine)
        result = await health_check.is_healthy()

        assert result is False

    @pytest.mark.asyncio
    async def test_get_pool_status_returns_pool_info(
        self, mock_engine: AsyncMock
    ) -> None:
        """Test that get_pool_status returns pool statistics."""
        mock_pool = MagicMock()
        mock_pool.size.return_value = 5
        mock_pool.checkedin.return_value = 3
        mock_pool.checkedout.return_value = 2
        mock_pool.overflow.return_value = 0
        mock_engine.pool = mock_pool

        health_check = DatabaseHealthCheck(mock_engine)
        status = await health_check.get_pool_status()

        assert status == {
            "pool_size": 5,
            "checked_in": 3,
            "checked_out": 2,
            "overflow": 0,
        }

    @pytest.mark.asyncio
    async def test_detailed_check_includes_latency(
        self, mock_engine: AsyncMock
    ) -> None:
        """Test that detailed_check includes latency measurement."""
        mock_conn = AsyncMock()
        mock_engine.connect.return_value.__aenter__.return_value = mock_conn

        mock_pool = MagicMock()
        mock_pool.size.return_value = 5
        mock_pool.checkedin.return_value = 3
        mock_pool.checkedout.return_value = 2
        mock_pool.overflow.return_value = 0
        mock_engine.pool = mock_pool

        health_check = DatabaseHealthCheck(mock_engine)
        result = await health_check.detailed_check()

        assert result["healthy"] is True
        assert "latency_ms" in result
        assert isinstance(result["latency_ms"], float)
        assert "pool" in result

    @pytest.mark.asyncio
    async def test_detailed_check_returns_none_pool_on_failure(
        self, mock_engine: AsyncMock
    ) -> None:
        """Test that detailed_check returns None pool when unhealthy."""
        mock_engine.connect.side_effect = Exception("Connection failed")

        health_check = DatabaseHealthCheck(mock_engine)
        result = await health_check.detailed_check()

        assert result["healthy"] is False
        assert result["pool"] is None


class TestDependencyGetDb:
    """Tests for dependency_get_db function."""

    def test_creates_callable_dependency(self) -> None:
        """Test that function creates a callable dependency."""
        mock_factory = MagicMock()
        get_db = dependency_get_db(mock_factory)

        # Should be a callable
        assert callable(get_db)

    @pytest.mark.asyncio
    async def test_dependency_uses_session_factory(self) -> None:
        """Test that dependency uses the provided session factory."""
        mock_session = AsyncMock(spec=AsyncSession)
        mock_context = AsyncMock()
        mock_context.__aenter__.return_value = mock_session
        mock_context.__aexit__.return_value = None
        mock_factory = MagicMock(return_value=mock_context)

        get_db = dependency_get_db(mock_factory)

        # The dependency is an async generator
        gen = get_db()
        session = await gen.__anext__()

        # Verify factory was called
        mock_factory.assert_called_once()
