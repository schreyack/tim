"""TIM Token Revocation Module.

Redis-backed token/auth_id revocation store. Separated from oidc.py
to keep OIDC verification free of Redis dependencies.

Install with: pip install tim-lib[redis]

Example:
    from tim_lib.revocation import RedisRevocationStore

    store = RedisRevocationStore(redis_url="redis://localhost:6379/0")
    await store.revoke("user_auth_id", ttl_seconds=7200)
    is_revoked = await store.is_revoked("user_auth_id")
    await store.close()
"""

from __future__ import annotations

import logging
from typing import Protocol, runtime_checkable

try:
    import redis.asyncio as aioredis
except ImportError:
    aioredis = None  # type: ignore[assignment]


logger = logging.getLogger(__name__)


@runtime_checkable
class RevocationStore(Protocol):
    """Protocol for token revocation backends.

    Apps can provide custom implementations (e.g. database-backed).
    """

    async def is_revoked(self, auth_id: str) -> bool:
        """Check if an auth_id has been revoked."""
        ...

    async def revoke(self, auth_id: str, ttl_seconds: int) -> None:
        """Revoke an auth_id with a TTL (auto-expires after token lifetime)."""
        ...


class RedisRevocationStore:
    """Redis-backed revocation store using SETEX with auto-expiry.

    Creates an internal connection pool. Call close() on app shutdown.

    Fail-open design: if Redis is unreachable, is_revoked() returns False
    with a warning log. Revocation is a best-effort safety net; JWT expiry
    is the hard security boundary.

    Args:
        redis_url: Redis connection URL (e.g. "redis://localhost:6379/0").
        key_prefix: Key prefix for revocation entries. Must match across
            all components that check revocation.
    """

    def __init__(
        self,
        redis_url: str,
        key_prefix: str = "auth:revoked:",
    ) -> None:
        if aioredis is None:
            msg = (
                "redis package not installed. "
                "Install with: pip install tim-lib[redis]"
            )
            raise ImportError(msg)
        self._pool = aioredis.ConnectionPool.from_url(redis_url)
        self._key_prefix = key_prefix

    async def is_revoked(self, auth_id: str) -> bool:
        """Check if an auth_id has been revoked.

        Fail-open: returns False on Redis errors (logs warning).
        """
        try:
            client = aioredis.Redis(connection_pool=self._pool)
            result: int = await client.exists(f"{self._key_prefix}{auth_id}")
            return result > 0
        except Exception:
            logger.warning(
                "revocation_check_failed",
                extra={"auth_id": auth_id},
                exc_info=True,
            )
            return False

    async def revoke(self, auth_id: str, ttl_seconds: int) -> None:
        """Revoke an auth_id. Key auto-expires after ttl_seconds.

        Args:
            auth_id: The OIDC subject identifier to revoke.
            ttl_seconds: Time-to-live in seconds. Must exceed the access
                token lifetime to close the revocation window.
        """
        client = aioredis.Redis(connection_pool=self._pool)
        await client.setex(f"{self._key_prefix}{auth_id}", ttl_seconds, 1)

    async def close(self) -> None:
        """Shut down the connection pool. Call on app shutdown."""
        await self._pool.aclose()
