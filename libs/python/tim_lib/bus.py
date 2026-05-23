"""TIM Event Bus Module.

Redis Pub/Sub backed event bus for cross-pod messaging. Apps with
multiple replicas use this to broadcast events (e.g. WebSocket
notifications) to all pods.

Install with: pip install tim-lib[redis]

Example:
    from tim_lib.bus import EventBus

    bus = EventBus(redis_url="rediss://...", prefix="myapp")
    bus.subscribe("queue_update", handle_queue_update)
    await bus.connect()

    await bus.publish("queue_update", {"id": 1, "action": "join"})

    await bus.disconnect()
"""

from __future__ import annotations

import asyncio
import contextlib
import json
import logging
from typing import Any, Awaitable, Callable

try:
    import redis.asyncio as aioredis
except ImportError:
    aioredis = None  # type: ignore[assignment]


logger = logging.getLogger(__name__)

Handler = Callable[[dict[str, Any]], Awaitable[None]]


class EventBus:
    """Redis Pub/Sub event bus for cross-pod broadcasting.

    Creates two Redis connections: a pooled publisher and a dedicated
    subscriber. The subscriber runs a background task that dispatches
    messages to registered handlers.

    Fail-open design: publish and subscribe errors are logged but never
    raised. If Redis is unreachable, the app continues without cross-pod
    messaging (local-only). This matches the revocation module pattern.

    Args:
        redis_url: Redis connection URL (e.g. "rediss://:pw@host:6379/3").
        prefix: Channel prefix to namespace messages per app.
    """

    def __init__(self, redis_url: str, prefix: str) -> None:
        if aioredis is None:
            msg = (
                "redis package not installed. "
                "Install with: pip install tim-lib[redis]"
            )
            raise ImportError(msg)
        self._redis_url = redis_url
        self._prefix = prefix
        self._handlers: dict[str, list[Handler]] = {}
        self._pub_pool: aioredis.ConnectionPool | None = None
        self._sub_redis: aioredis.Redis | None = None  # type: ignore[type-arg]
        self._pubsub: aioredis.client.PubSub | None = None
        self._listener_task: asyncio.Task[None] | None = None
        self._connected = False

    def subscribe(self, channel: str, handler: Handler) -> None:
        """Register a handler for a channel. Call before connect().

        Multiple handlers per channel are supported. Handlers receive
        the deserialized JSON payload as a dict.

        Raises:
            RuntimeError: If called after connect().
        """
        if self._connected:
            msg = "Cannot subscribe after connect() — register handlers first"
            raise RuntimeError(msg)
        self._handlers.setdefault(channel, []).append(handler)

    async def connect(self) -> None:
        """Start the publisher pool and subscriber listener task."""
        try:
            self._pub_pool = aioredis.ConnectionPool.from_url(self._redis_url)
            self._sub_redis = aioredis.Redis.from_url(self._redis_url)
            self._pubsub = self._sub_redis.pubsub()
            channels = {
                f"{self._prefix}:{ch}": self._dispatch
                for ch in self._handlers
            }
            if channels:
                await self._pubsub.subscribe(**channels)
            self._listener_task = asyncio.create_task(self._listen())
            self._connected = True
            logger.info(
                "event_bus_connected",
                extra={
                    "prefix": self._prefix,
                    "channels": list(self._handlers.keys()),
                },
            )
        except Exception:
            logger.warning("event_bus_connect_failed", exc_info=True)

    async def publish(self, channel: str, payload: dict[str, Any]) -> None:
        """Publish an event to all pods subscribed to this channel.

        Fail-open: logs and returns on error.
        """
        if not self._connected or self._pub_pool is None:
            logger.warning(
                "event_bus_publish_skipped",
                extra={"channel": channel, "reason": "not connected"},
            )
            return
        try:
            client = aioredis.Redis(connection_pool=self._pub_pool)
            data = json.dumps(payload)
            await client.publish(f"{self._prefix}:{channel}", data)
        except Exception:
            logger.warning(
                "event_bus_publish_failed",
                extra={"channel": channel},
                exc_info=True,
            )

    async def disconnect(self) -> None:
        """Stop the listener task and close all connections."""
        self._connected = False
        if self._listener_task is not None:
            self._listener_task.cancel()
            with contextlib.suppress(asyncio.CancelledError):
                await self._listener_task
            self._listener_task = None
        if self._pubsub is not None:
            try:
                await self._pubsub.unsubscribe()
                await self._pubsub.close()
            except Exception:
                logger.warning("event_bus_pubsub_close_failed", exc_info=True)
            self._pubsub = None
        if self._sub_redis is not None:
            try:
                await self._sub_redis.aclose()
            except Exception:
                logger.warning("event_bus_sub_close_failed", exc_info=True)
            self._sub_redis = None
        if self._pub_pool is not None:
            try:
                await self._pub_pool.aclose()
            except Exception:
                logger.warning("event_bus_pool_close_failed", exc_info=True)
            self._pub_pool = None
        logger.info("event_bus_disconnected", extra={"prefix": self._prefix})

    async def _dispatch(self, message: dict[str, Any]) -> None:
        """Route a received Pub/Sub message to registered handlers."""
        if message.get("type") != "message":
            return
        raw_channel: bytes | str = message.get("channel", b"")
        if isinstance(raw_channel, bytes):
            raw_channel = raw_channel.decode()
        bare = raw_channel.split(":", 1)[1] if ":" in raw_channel else raw_channel
        handlers = self._handlers.get(bare, [])
        if not handlers:
            return
        try:
            raw_data: bytes | str = message.get("data", b"{}")
            if isinstance(raw_data, bytes):
                raw_data = raw_data.decode()
            payload: dict[str, Any] = json.loads(raw_data)
        except (json.JSONDecodeError, UnicodeDecodeError):
            logger.warning(
                "event_bus_decode_failed",
                extra={"channel": bare},
                exc_info=True,
            )
            return
        for handler in handlers:
            try:
                await handler(payload)
            except Exception:
                logger.warning(
                    "event_bus_handler_error",
                    extra={"channel": bare, "handler": handler.__name__},
                    exc_info=True,
                )

    async def _listen(self) -> None:
        """Background task: read from Pub/Sub, dispatch to handlers."""
        delay = 1.0
        max_delay = 30.0
        while True:
            try:
                if self._pubsub is None:
                    return
                async for message in self._pubsub.listen():
                    await self._dispatch(message)
                    delay = 1.0
            except asyncio.CancelledError:
                return
            except Exception:
                logger.warning(
                    "event_bus_listener_error",
                    extra={"reconnect_delay": delay},
                    exc_info=True,
                )
                await asyncio.sleep(delay)
                delay = min(delay * 2, max_delay)
                if self._pubsub is not None:
                    try:
                        channels = {
                            f"{self._prefix}:{ch}": self._dispatch
                            for ch in self._handlers
                        }
                        if channels:
                            await self._pubsub.subscribe(**channels)
                    except Exception:
                        logger.warning(
                            "event_bus_resubscribe_failed",
                            exc_info=True,
                        )
