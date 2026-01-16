"""TIM Shared Database Module.

Provides SQLAlchemy async session management and health check utilities.

Example:
    from tim_lib.db import create_async_engine_with_pool, get_session_factory

    engine = create_async_engine_with_pool(settings.database_url)
    async_session = get_session_factory(engine)

    async with async_session() as session:
        result = await session.execute(select(User))
"""

from collections.abc import AsyncGenerator
from contextlib import asynccontextmanager
from typing import Any

from sqlalchemy import text
from sqlalchemy.ext.asyncio import (
    AsyncEngine,
    AsyncSession,
    async_sessionmaker,
    create_async_engine,
)
from sqlalchemy.orm import DeclarativeBase


class Base(DeclarativeBase):
    """Base class for SQLAlchemy models.

    All models should inherit from this class.

    Example:
        from tim_lib.db import Base
        from sqlalchemy.orm import Mapped, mapped_column

        class User(Base):
            __tablename__ = "users"

            id: Mapped[int] = mapped_column(primary_key=True)
            email: Mapped[str] = mapped_column(unique=True)
    """

    pass


def create_async_engine_with_pool(
    database_url: str,
    pool_size: int = 5,
    max_overflow: int = 10,
    pool_pre_ping: bool = True,
    echo: bool = False,
) -> AsyncEngine:
    """Create an async SQLAlchemy engine with connection pooling.

    Args:
        database_url: PostgreSQL connection string (must use postgresql+asyncpg://)
        pool_size: Number of connections to keep in the pool.
        max_overflow: Max connections beyond pool_size during peak.
        pool_pre_ping: Verify connections before use (recommended).
        echo: Log SQL statements (debug only).

    Returns:
        Configured AsyncEngine.

    Example:
        engine = create_async_engine_with_pool(
            settings.database_url,
            pool_size=10,
            echo=settings.debug,
        )
    """
    # Ensure URL uses asyncpg driver
    if database_url.startswith("postgresql://"):
        database_url = database_url.replace("postgresql://", "postgresql+asyncpg://", 1)

    return create_async_engine(
        database_url,
        pool_size=pool_size,
        max_overflow=max_overflow,
        pool_pre_ping=pool_pre_ping,
        echo=echo,
    )


def get_session_factory(engine: AsyncEngine) -> async_sessionmaker[AsyncSession]:
    """Create a session factory for the engine.

    Args:
        engine: AsyncEngine to use.

    Returns:
        Session factory for creating sessions.

    Example:
        async_session = get_session_factory(engine)
        async with async_session() as session:
            # Use session
    """
    return async_sessionmaker(
        engine,
        class_=AsyncSession,
        expire_on_commit=False,
        autocommit=False,
        autoflush=False,
    )


@asynccontextmanager
async def get_db_session(
    session_factory: async_sessionmaker[AsyncSession],
) -> AsyncGenerator[AsyncSession, None]:
    """Context manager for database sessions with automatic cleanup.

    Commits on success, rolls back on exception.

    Args:
        session_factory: Session factory to create session from.

    Yields:
        AsyncSession for database operations.

    Example:
        async with get_db_session(async_session) as db:
            user = await db.get(User, user_id)
    """
    session = session_factory()
    try:
        yield session
        await session.commit()
    except Exception:
        await session.rollback()
        raise
    finally:
        await session.close()


class DatabaseHealthCheck:
    """Health check utility for database connectivity.

    Example:
        health_check = DatabaseHealthCheck(engine)

        # In health endpoint
        @app.get("/health/ready")
        async def readiness():
            db_healthy = await health_check.is_healthy()
            return {"database": "healthy" if db_healthy else "unhealthy"}
    """

    def __init__(self, engine: AsyncEngine) -> None:
        self.engine = engine

    async def is_healthy(self) -> bool:
        """Check if database is reachable and responding."""
        try:
            async with self.engine.connect() as conn:
                await conn.execute(text("SELECT 1"))
            return True
        except Exception:
            return False

    async def get_pool_status(self) -> dict[str, Any]:
        """Get connection pool statistics."""
        pool = self.engine.pool
        return {
            "pool_size": pool.size(),
            "checked_in": pool.checkedin(),
            "checked_out": pool.checkedout(),
            "overflow": pool.overflow(),
        }

    async def detailed_check(self) -> dict[str, Any]:
        """Perform detailed health check with timing."""
        import time

        start = time.time()
        is_healthy = await self.is_healthy()
        latency_ms = (time.time() - start) * 1000

        return {
            "healthy": is_healthy,
            "latency_ms": round(latency_ms, 2),
            "pool": await self.get_pool_status() if is_healthy else None,
        }


def dependency_get_db(
    session_factory: async_sessionmaker[AsyncSession],
) -> Any:
    """Create a FastAPI dependency for database sessions.

    Args:
        session_factory: Session factory to use.

    Returns:
        FastAPI dependency function.

    Example:
        async_session = get_session_factory(engine)
        get_db = dependency_get_db(async_session)

        @app.get("/users/{user_id}")
        async def get_user(user_id: int, db: AsyncSession = Depends(get_db)):
            user = await db.get(User, user_id)
    """

    async def get_db() -> AsyncGenerator[AsyncSession, None]:
        async with session_factory() as session:
            try:
                yield session
                await session.commit()
            except Exception:
                await session.rollback()
                raise

    return get_db
