"""Tests for tim_lib.api module."""

import time
from typing import Any
from unittest.mock import AsyncMock, MagicMock

import pytest
from fastapi import FastAPI, Request
from fastapi.testclient import TestClient

from tim_lib.api import (
    AppError,
    ConflictError,
    ForbiddenError,
    NotFoundError,
    RateLimitMiddleware,
    UnauthorizedError,
    ValidationError,
    create_health_router,
    security_headers_middleware,
    setup_exception_handlers,
)


class TestAppErrorHierarchy:
    """Tests for AppError and subclasses."""

    def test_app_error_default_status_code(self) -> None:
        """Test that AppError has default status code 500."""
        error = AppError()
        assert error.status_code == 500

    def test_app_error_default_message(self) -> None:
        """Test that AppError has default message."""
        error = AppError()
        assert error.message == "An error occurred"

    def test_app_error_with_custom_message(self) -> None:
        """Test that custom message overrides default."""
        error = AppError("Custom error message")
        assert error.message == "Custom error message"

    def test_app_error_with_detail(self) -> None:
        """Test that detail is stored."""
        error = AppError("Error", detail="Additional info")
        assert error.detail == "Additional info"

    def test_not_found_error_status_code(self) -> None:
        """Test NotFoundError has 404 status code."""
        error = NotFoundError()
        assert error.status_code == 404
        assert error.message == "Resource not found"

    def test_conflict_error_status_code(self) -> None:
        """Test ConflictError has 409 status code."""
        error = ConflictError()
        assert error.status_code == 409
        assert error.message == "Resource already exists"

    def test_validation_error_status_code(self) -> None:
        """Test ValidationError has 400 status code."""
        error = ValidationError()
        assert error.status_code == 400
        assert error.message == "Validation failed"

    def test_unauthorized_error_status_code(self) -> None:
        """Test UnauthorizedError has 401 status code."""
        error = UnauthorizedError()
        assert error.status_code == 401
        assert error.message == "Unauthorized"

    def test_forbidden_error_status_code(self) -> None:
        """Test ForbiddenError has 403 status code."""
        error = ForbiddenError()
        assert error.status_code == 403
        assert error.message == "Forbidden"

    def test_subclass_custom_message_override(self) -> None:
        """Test that subclass default message can be overridden."""
        error = NotFoundError("User 123 not found")
        assert error.message == "User 123 not found"
        assert error.status_code == 404


class TestExceptionHandlers:
    """Tests for setup_exception_handlers function."""

    @pytest.fixture
    def app_with_handlers(self) -> FastAPI:
        """Create a FastAPI app with exception handlers."""
        app = FastAPI()
        setup_exception_handlers(app)

        @app.get("/not-found")
        async def raise_not_found() -> None:
            raise NotFoundError("Item not found")

        @app.get("/conflict")
        async def raise_conflict() -> None:
            raise ConflictError("Already exists", detail="email_taken")

        @app.get("/error")
        async def raise_error() -> None:
            raise RuntimeError("Unexpected error")

        return app

    def test_handler_converts_not_found_to_404(
        self, app_with_handlers: FastAPI
    ) -> None:
        """Test that NotFoundError becomes 404 response."""
        client = TestClient(app_with_handlers)
        response = client.get("/not-found")

        assert response.status_code == 404
        data = response.json()
        assert data["error"] == "Item not found"

    def test_handler_includes_detail_in_response(
        self, app_with_handlers: FastAPI
    ) -> None:
        """Test that error detail is included in response."""
        client = TestClient(app_with_handlers)
        response = client.get("/conflict")

        assert response.status_code == 409
        data = response.json()
        assert data["error"] == "Already exists"
        assert data["detail"] == "email_taken"

    def test_handler_converts_unexpected_error_to_500(
        self, app_with_handlers: FastAPI
    ) -> None:
        """Test that unexpected errors become 500 response."""
        # Use raise_server_exceptions=False to test error handler behavior
        client = TestClient(app_with_handlers, raise_server_exceptions=False)
        response = client.get("/error")

        assert response.status_code == 500
        data = response.json()
        assert data["error"] == "Internal server error"


class TestSecurityHeadersMiddleware:
    """Tests for security_headers_middleware."""

    @pytest.fixture
    def app_with_security_headers(self) -> FastAPI:
        """Create app with security headers middleware."""
        app = FastAPI()
        app.middleware("http")(security_headers_middleware)

        @app.get("/test")
        async def test_endpoint() -> dict[str, str]:
            return {"status": "ok"}

        return app

    def test_middleware_adds_x_content_type_options(
        self, app_with_security_headers: FastAPI
    ) -> None:
        """Test X-Content-Type-Options header is added."""
        client = TestClient(app_with_security_headers)
        response = client.get("/test")

        assert response.headers["X-Content-Type-Options"] == "nosniff"

    def test_middleware_adds_x_frame_options(
        self, app_with_security_headers: FastAPI
    ) -> None:
        """Test X-Frame-Options header is added."""
        client = TestClient(app_with_security_headers)
        response = client.get("/test")

        assert response.headers["X-Frame-Options"] == "DENY"

    def test_middleware_adds_x_xss_protection(
        self, app_with_security_headers: FastAPI
    ) -> None:
        """Test X-XSS-Protection header is added."""
        client = TestClient(app_with_security_headers)
        response = client.get("/test")

        assert response.headers["X-XSS-Protection"] == "1; mode=block"

    def test_middleware_adds_referrer_policy(
        self, app_with_security_headers: FastAPI
    ) -> None:
        """Test Referrer-Policy header is added."""
        client = TestClient(app_with_security_headers)
        response = client.get("/test")

        assert response.headers["Referrer-Policy"] == "strict-origin-when-cross-origin"

    def test_middleware_adds_csp(
        self, app_with_security_headers: FastAPI
    ) -> None:
        """Test Content-Security-Policy header is added."""
        client = TestClient(app_with_security_headers)
        response = client.get("/test")

        csp = response.headers["Content-Security-Policy"]
        assert "default-src 'self'" in csp


class TestRateLimitMiddleware:
    """Tests for RateLimitMiddleware."""

    @pytest.fixture
    def mock_app(self) -> Any:
        """Create mock ASGI app."""

        async def app(scope: Any, receive: Any, send: Any) -> None:
            await send(
                {"type": "http.response.start", "status": 200, "headers": []}
            )
            await send({"type": "http.response.body", "body": b"OK"})

        return app

    @pytest.mark.asyncio
    async def test_middleware_allows_requests_under_limit(
        self, mock_app: Any, mock_asgi_scope: dict[str, Any]
    ) -> None:
        """Test that requests under limit are allowed."""
        middleware = RateLimitMiddleware(mock_app, requests_per_minute=10)
        responses: list[dict[str, Any]] = []

        async def mock_receive() -> dict[str, Any]:
            return {"type": "http.request", "body": b""}

        async def mock_send(message: dict[str, Any]) -> None:
            responses.append(message)

        await middleware(mock_asgi_scope, mock_receive, mock_send)

        assert responses[0]["status"] == 200

    @pytest.mark.asyncio
    async def test_middleware_blocks_requests_over_limit(
        self, mock_app: Any, mock_asgi_scope: dict[str, Any]
    ) -> None:
        """Test that requests over limit are blocked with 429."""
        middleware = RateLimitMiddleware(mock_app, requests_per_minute=2)
        responses: list[dict[str, Any]] = []

        async def mock_receive() -> dict[str, Any]:
            return {"type": "http.request", "body": b""}

        async def mock_send(message: dict[str, Any]) -> None:
            responses.append(message)

        # Make 3 requests (limit is 2)
        for _ in range(3):
            responses.clear()
            await middleware(mock_asgi_scope, mock_receive, mock_send)

        # Third request should be rate limited
        assert responses[0]["status"] == 429

    @pytest.mark.asyncio
    async def test_middleware_passes_non_http_requests(
        self, mock_app: Any
    ) -> None:
        """Test that non-HTTP requests are passed through."""
        middleware = RateLimitMiddleware(mock_app, requests_per_minute=1)
        scope = {"type": "websocket"}

        async def mock_receive() -> dict[str, Any]:
            return {}

        async def mock_send(message: dict[str, Any]) -> None:
            pass

        # Should not raise or rate limit
        await middleware(scope, mock_receive, mock_send)

    def test_get_client_ip_from_direct_client(self) -> None:
        """Test extracting IP from direct client connection."""
        middleware = RateLimitMiddleware(lambda: None, requests_per_minute=10)
        scope = {"client": ("192.168.1.100", 8000), "headers": []}

        ip = middleware._get_client_ip(scope)
        assert ip == "192.168.1.100"

    def test_get_client_ip_from_forwarded_header(self) -> None:
        """Test extracting IP from X-Forwarded-For header."""
        middleware = RateLimitMiddleware(lambda: None, requests_per_minute=10)
        scope = {
            "client": ("127.0.0.1", 8000),
            "headers": [(b"x-forwarded-for", b"203.0.113.50, 70.41.3.18")],
        }

        ip = middleware._get_client_ip(scope)
        assert ip == "203.0.113.50"

    def test_get_client_ip_returns_unknown_when_missing(self) -> None:
        """Test that unknown is returned when client info is missing."""
        middleware = RateLimitMiddleware(lambda: None, requests_per_minute=10)
        scope = {"headers": []}

        ip = middleware._get_client_ip(scope)
        assert ip == "unknown"


class TestHealthRouter:
    """Tests for create_health_router function."""

    @pytest.fixture
    def app_with_health(self) -> FastAPI:
        """Create app with health router."""
        app = FastAPI()
        health_router = create_health_router()
        app.include_router(health_router)
        return app

    def test_health_endpoint_returns_healthy(
        self, app_with_health: FastAPI
    ) -> None:
        """Test /health endpoint returns healthy status."""
        client = TestClient(app_with_health)
        response = client.get("/health")

        assert response.status_code == 200
        assert response.json() == {"status": "healthy"}

    def test_ready_endpoint_returns_ready(
        self, app_with_health: FastAPI
    ) -> None:
        """Test /health/ready endpoint returns ready status."""
        client = TestClient(app_with_health)
        response = client.get("/health/ready")

        assert response.status_code == 200
        assert response.json() == {"status": "ready"}

    def test_live_endpoint_returns_detailed_status(
        self, app_with_health: FastAPI
    ) -> None:
        """Test /health/live endpoint returns detailed status."""
        client = TestClient(app_with_health)
        response = client.get("/health/live")

        assert response.status_code == 200
        data = response.json()
        assert data["status"] == "healthy"
        assert "python_version" in data
        assert "timestamp" in data
