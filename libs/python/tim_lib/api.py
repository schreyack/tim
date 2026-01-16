"""TIM Shared API Module.

Provides FastAPI middleware, error handlers, and common utilities.

Example:
    from tim_lib.api import (
        setup_exception_handlers,
        RateLimitMiddleware,
        security_headers_middleware,
    )

    app = FastAPI()
    setup_exception_handlers(app)
    app.add_middleware(RateLimitMiddleware, requests_per_minute=60)
    app.middleware("http")(security_headers_middleware)
"""

import time
from collections.abc import Awaitable, Callable
from typing import Any

from fastapi import FastAPI, HTTPException, Request, Response
from fastapi.responses import JSONResponse


class AppError(Exception):
    """Base exception for application errors.

    Subclass this for specific error types.

    Attributes:
        status_code: HTTP status code to return.
        message: User-facing error message.
        detail: Additional detail (optional).
    """

    status_code: int = 500
    message: str = "An error occurred"

    def __init__(
        self, message: str | None = None, detail: str | None = None
    ) -> None:
        self.message = message or self.__class__.message
        self.detail = detail
        super().__init__(self.message)


class NotFoundError(AppError):
    """Resource not found error (404)."""

    status_code = 404
    message = "Resource not found"


class ConflictError(AppError):
    """Resource conflict error (409)."""

    status_code = 409
    message = "Resource already exists"


class ValidationError(AppError):
    """Validation error (400)."""

    status_code = 400
    message = "Validation failed"


class UnauthorizedError(AppError):
    """Unauthorized error (401)."""

    status_code = 401
    message = "Unauthorized"


class ForbiddenError(AppError):
    """Forbidden error (403)."""

    status_code = 403
    message = "Forbidden"


def setup_exception_handlers(app: FastAPI) -> None:
    """Setup exception handlers for common errors.

    Converts AppError subclasses to appropriate HTTP responses.
    Also catches unexpected errors and returns 500.

    Args:
        app: FastAPI application instance.

    Example:
        app = FastAPI()
        setup_exception_handlers(app)

        @app.get("/users/{user_id}")
        async def get_user(user_id: int):
            user = await user_service.get(user_id)
            if not user:
                raise NotFoundError(f"User {user_id} not found")
            return user
    """
    from tim_lib.logging import get_logger

    logger = get_logger(__name__)

    @app.exception_handler(AppError)
    async def app_error_handler(request: Request, exc: AppError) -> JSONResponse:
        return JSONResponse(
            status_code=exc.status_code,
            content={
                "error": exc.message,
                "detail": exc.detail,
            },
        )

    @app.exception_handler(HTTPException)
    async def http_exception_handler(
        request: Request, exc: HTTPException
    ) -> JSONResponse:
        return JSONResponse(
            status_code=exc.status_code,
            content={
                "error": exc.detail,
            },
        )

    @app.exception_handler(Exception)
    async def general_exception_handler(
        request: Request, exc: Exception
    ) -> JSONResponse:
        logger.exception("unhandled_exception", error=str(exc))
        return JSONResponse(
            status_code=500,
            content={
                "error": "Internal server error",
            },
        )


async def security_headers_middleware(
    request: Request,
    call_next: Callable[[Request], Awaitable[Response]],
) -> Response:
    """Add security headers to all responses.

    Headers added:
    - X-Content-Type-Options: nosniff
    - X-Frame-Options: DENY
    - X-XSS-Protection: 1; mode=block
    - Referrer-Policy: strict-origin-when-cross-origin
    - Content-Security-Policy: default-src 'self'

    Note: CSP may need customization for your frontend needs.

    Example:
        app.middleware("http")(security_headers_middleware)
    """
    response = await call_next(request)
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["X-Frame-Options"] = "DENY"
    response.headers["X-XSS-Protection"] = "1; mode=block"
    response.headers["Referrer-Policy"] = "strict-origin-when-cross-origin"
    # Customize CSP as needed for your frontend
    response.headers["Content-Security-Policy"] = (
        "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'"
    )
    return response


class RateLimitMiddleware:
    """Simple in-memory rate limiting middleware.

    For production, use Redis-based rate limiting instead.

    Args:
        app: ASGI application.
        requests_per_minute: Max requests per client per minute.

    Example:
        app.add_middleware(RateLimitMiddleware, requests_per_minute=60)
    """

    def __init__(self, app: Any, requests_per_minute: int = 60) -> None:
        self.app = app
        self.requests_per_minute = requests_per_minute
        self.clients: dict[str, list[float]] = {}

    async def __call__(self, scope: Any, receive: Any, send: Any) -> None:
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return

        # Get client IP
        client_ip = self._get_client_ip(scope)
        now = time.time()

        # Clean old entries and check rate
        if client_ip in self.clients:
            # Keep only requests from the last minute
            self.clients[client_ip] = [
                t for t in self.clients[client_ip] if now - t < 60
            ]
        else:
            self.clients[client_ip] = []

        if len(self.clients[client_ip]) >= self.requests_per_minute:
            # Rate limited
            response = JSONResponse(
                status_code=429,
                content={"error": "Too many requests"},
                headers={"Retry-After": "60"},
            )
            await response(scope, receive, send)
            return

        # Record request
        self.clients[client_ip].append(now)

        await self.app(scope, receive, send)

    def _get_client_ip(self, scope: Any) -> str:
        """Extract client IP from scope."""
        # Check X-Forwarded-For first (behind proxy)
        headers = dict(scope.get("headers", []))
        forwarded = headers.get(b"x-forwarded-for")
        if forwarded:
            return forwarded.decode().split(",")[0].strip()

        # Fall back to direct client
        client = scope.get("client")
        if client:
            return client[0]

        return "unknown"


def create_health_router() -> Any:
    """Create a router with standard health check endpoints.

    Endpoints:
    - GET /health - Liveness probe
    - GET /health/ready - Readiness probe (override for dependencies)
    - GET /health/live - Detailed health with service info

    Example:
        from tim_lib.api import create_health_router

        health_router = create_health_router()
        app.include_router(health_router)
    """
    from fastapi import APIRouter

    router = APIRouter(tags=["Health"])

    @router.get("/health")
    async def health() -> dict[str, str]:
        """Liveness probe - is the process running?"""
        return {"status": "healthy"}

    @router.get("/health/ready")
    async def ready() -> dict[str, str]:
        """Readiness probe - can accept traffic?

        Override this in your app to check dependencies.
        """
        return {"status": "ready"}

    @router.get("/health/live")
    async def live() -> dict[str, Any]:
        """Detailed health status."""
        import sys

        return {
            "status": "healthy",
            "python_version": sys.version,
            "timestamp": time.time(),
        }

    return router
