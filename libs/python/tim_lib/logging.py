"""TIM Shared Logging Module.

Provides structured JSON logging using structlog for all TIM projects.
Logs are formatted for easy parsing by log aggregation tools.

Example:
    from tim_lib import configure_logging, get_logger

    configure_logging(level="INFO", json_output=True)
    logger = get_logger()

    logger.info("user_created", user_id=123, email="test@example.com")
    # Output: {"event": "user_created", "user_id": 123, ...}
"""

import logging
import sys
from typing import Any, cast

import structlog
from structlog.stdlib import BoundLogger
from structlog.types import Processor


def configure_logging(
    level: str = "INFO",
    json_output: bool = True,
    service_name: str | None = None,
    environment: str | None = None,
) -> None:
    """Configure structured logging for the application.

    Args:
        level: Log level (DEBUG, INFO, WARNING, ERROR, CRITICAL)
        json_output: If True, output JSON logs. If False, output human-readable.
        service_name: Service name to include in all logs
        environment: Environment name to include in all logs
    """
    # Determine output format
    if json_output:
        renderer: Processor = structlog.processors.JSONRenderer()
    else:
        renderer = structlog.dev.ConsoleRenderer(colors=True)

    # Build processor chain
    processors: list[Processor] = [
        structlog.contextvars.merge_contextvars,
        structlog.processors.add_log_level,
        structlog.processors.TimeStamper(fmt="iso"),
        structlog.processors.StackInfoRenderer(),
        structlog.processors.format_exc_info,
    ]

    # Add service context if provided
    if service_name or environment:

        def add_service_context(
            logger: Any, method_name: str, event_dict: dict[str, Any]
        ) -> dict[str, Any]:
            if service_name:
                event_dict["service"] = service_name
            if environment:
                event_dict["environment"] = environment
            return event_dict

        processors.append(cast(Processor, add_service_context))

    # Add renderer
    processors.append(renderer)

    # Configure structlog
    structlog.configure(
        processors=processors,
        wrapper_class=structlog.make_filtering_bound_logger(
            getattr(logging, level.upper())
        ),
        context_class=dict,
        logger_factory=structlog.PrintLoggerFactory(file=sys.stdout),
        cache_logger_on_first_use=True,
    )

    # Also configure standard library logging to use structlog
    logging.basicConfig(
        format="%(message)s",
        stream=sys.stdout,
        level=getattr(logging, level.upper()),
    )


def get_logger(name: str | None = None) -> BoundLogger:
    """Get a configured logger instance.

    Args:
        name: Optional logger name. If not provided, returns the root logger.

    Returns:
        A configured structlog logger.

    Example:
        logger = get_logger(__name__)
        logger.info("processing_request", request_id="abc123")
    """
    return cast(BoundLogger, structlog.get_logger(name))


def bind_context(**kwargs: Any) -> None:
    """Bind context variables that will be included in all subsequent log messages.

    Useful for adding request-specific context like correlation IDs.

    Example:
        bind_context(correlation_id="abc123", user_id=456)
        logger.info("processing")  # Will include correlation_id and user_id
    """
    structlog.contextvars.bind_contextvars(**kwargs)


def clear_context() -> None:
    """Clear all bound context variables.

    Call this at the end of request processing to prevent context leaking.
    """
    structlog.contextvars.clear_contextvars()


class LogContextMiddleware:
    """Middleware to add correlation ID and clear context after requests.

    For FastAPI:
        from tim_lib.logging import LogContextMiddleware
        app.add_middleware(LogContextMiddleware)
    """

    def __init__(self, app: Any) -> None:
        self.app = app

    async def __call__(self, scope: Any, receive: Any, send: Any) -> None:
        import uuid

        if scope["type"] == "http":
            # Get or generate correlation ID
            headers = dict(scope.get("headers", []))
            correlation_id = headers.get(
                b"x-correlation-id", str(uuid.uuid4()).encode()
            ).decode()

            # Bind to logging context
            bind_context(correlation_id=correlation_id)

            # Add correlation ID to response headers
            async def send_wrapper(message: Any) -> None:
                if message["type"] == "http.response.start":
                    headers = list(message.get("headers", []))
                    headers.append((b"x-correlation-id", correlation_id.encode()))
                    message["headers"] = headers
                await send(message)

            try:
                await self.app(scope, receive, send_wrapper)
            finally:
                clear_context()
        else:
            await self.app(scope, receive, send)
