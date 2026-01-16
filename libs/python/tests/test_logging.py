"""Tests for tim_lib.logging module."""

import io
import json
import sys
from typing import Any
from unittest.mock import MagicMock, patch

import pytest
import structlog

from tim_lib.logging import (
    LogContextMiddleware,
    bind_context,
    clear_context,
    configure_logging,
    get_logger,
)


class TestConfigureLogging:
    """Tests for configure_logging function."""

    def test_configure_logging_with_defaults_creates_json_logger(self) -> None:
        """Test that default configuration creates JSON output."""
        # Reset structlog configuration
        structlog.reset_defaults()

        configure_logging()
        logger = get_logger()

        # Capture output
        captured = io.StringIO()
        with patch.object(sys, "stdout", captured):
            logger.info("test_event", key="value")

        output = captured.getvalue()
        # Should be valid JSON
        parsed = json.loads(output)
        assert parsed["event"] == "test_event"
        assert parsed["key"] == "value"

    def test_configure_logging_with_console_output(self) -> None:
        """Test that json_output=False creates console output."""
        structlog.reset_defaults()

        configure_logging(json_output=False)
        logger = get_logger()

        # Capture output
        captured = io.StringIO()
        with patch.object(sys, "stdout", captured):
            logger.info("test_event")

        output = captured.getvalue()
        # Should NOT be JSON
        assert "test_event" in output
        with pytest.raises(json.JSONDecodeError):
            json.loads(output)

    def test_configure_logging_with_service_name_adds_to_logs(self) -> None:
        """Test that service_name is included in all logs."""
        structlog.reset_defaults()

        configure_logging(service_name="my-service")
        logger = get_logger()

        captured = io.StringIO()
        with patch.object(sys, "stdout", captured):
            logger.info("test_event")

        parsed = json.loads(captured.getvalue())
        assert parsed["service"] == "my-service"

    def test_configure_logging_with_environment_adds_to_logs(self) -> None:
        """Test that environment is included in all logs."""
        structlog.reset_defaults()

        configure_logging(environment="production")
        logger = get_logger()

        captured = io.StringIO()
        with patch.object(sys, "stdout", captured):
            logger.info("test_event")

        parsed = json.loads(captured.getvalue())
        assert parsed["environment"] == "production"

    def test_configure_logging_with_log_level_filters_messages(self) -> None:
        """Test that log level filtering works."""
        structlog.reset_defaults()

        configure_logging(level="WARNING")
        logger = get_logger()

        captured = io.StringIO()
        with patch.object(sys, "stdout", captured):
            logger.info("should_not_appear")
            logger.warning("should_appear")

        output = captured.getvalue()
        assert "should_not_appear" not in output
        assert "should_appear" in output


class TestGetLogger:
    """Tests for get_logger function."""

    def test_get_logger_without_name_returns_root_logger(self) -> None:
        """Test that get_logger without name returns a logger."""
        structlog.reset_defaults()
        configure_logging()

        logger = get_logger()
        assert logger is not None

    def test_get_logger_with_name_returns_named_logger(self) -> None:
        """Test that get_logger with name works."""
        structlog.reset_defaults()
        configure_logging()

        logger = get_logger("my.module")
        assert logger is not None


class TestContextBinding:
    """Tests for bind_context and clear_context functions."""

    def test_bind_context_adds_to_subsequent_logs(self) -> None:
        """Test that bound context appears in logs."""
        structlog.reset_defaults()
        configure_logging()

        bind_context(user_id=123, request_id="abc")
        logger = get_logger()

        captured = io.StringIO()
        with patch.object(sys, "stdout", captured):
            logger.info("test_event")

        parsed = json.loads(captured.getvalue())
        assert parsed["user_id"] == 123
        assert parsed["request_id"] == "abc"

        # Clean up
        clear_context()

    def test_clear_context_removes_bound_values(self) -> None:
        """Test that clear_context removes bound context."""
        structlog.reset_defaults()
        configure_logging()

        bind_context(user_id=123)
        clear_context()

        logger = get_logger()
        captured = io.StringIO()
        with patch.object(sys, "stdout", captured):
            logger.info("test_event")

        parsed = json.loads(captured.getvalue())
        assert "user_id" not in parsed


class TestLogContextMiddleware:
    """Tests for LogContextMiddleware."""

    @pytest.fixture
    def mock_app(self) -> MagicMock:
        """Create a mock ASGI app."""

        async def app(scope: Any, receive: Any, send: Any) -> None:
            # Simulate sending response
            await send(
                {
                    "type": "http.response.start",
                    "status": 200,
                    "headers": [],
                }
            )
            await send(
                {
                    "type": "http.response.body",
                    "body": b"OK",
                }
            )

        return app

    @pytest.mark.asyncio
    async def test_middleware_adds_correlation_id_to_response(
        self, mock_app: Any, mock_asgi_scope: dict[str, Any]
    ) -> None:
        """Test that middleware adds correlation ID to response."""
        middleware = LogContextMiddleware(mock_app)
        sent_messages: list[dict[str, Any]] = []

        async def mock_receive() -> dict[str, Any]:
            return {"type": "http.request", "body": b""}

        async def mock_send(message: dict[str, Any]) -> None:
            sent_messages.append(message)

        await middleware(mock_asgi_scope, mock_receive, mock_send)

        # Check that correlation ID was added
        start_message = sent_messages[0]
        headers = dict(start_message["headers"])
        assert b"x-correlation-id" in headers

    @pytest.mark.asyncio
    async def test_middleware_uses_provided_correlation_id(self, mock_app: Any) -> None:
        """Test that middleware uses existing correlation ID if provided."""
        middleware = LogContextMiddleware(mock_app)
        sent_messages: list[dict[str, Any]] = []

        scope = {
            "type": "http",
            "headers": [(b"x-correlation-id", b"existing-id-123")],
            "client": ("127.0.0.1", 8000),
        }

        async def mock_receive() -> dict[str, Any]:
            return {"type": "http.request", "body": b""}

        async def mock_send(message: dict[str, Any]) -> None:
            sent_messages.append(message)

        await middleware(scope, mock_receive, mock_send)

        # Check that provided correlation ID was used
        start_message = sent_messages[0]
        headers = dict(start_message["headers"])
        assert headers[b"x-correlation-id"] == b"existing-id-123"

    @pytest.mark.asyncio
    async def test_middleware_passes_non_http_requests(self, mock_app: Any) -> None:
        """Test that non-HTTP requests are passed through unchanged."""
        middleware = LogContextMiddleware(mock_app)

        scope = {"type": "websocket"}
        called = False

        async def tracking_app(scope: Any, receive: Any, send: Any) -> None:
            nonlocal called
            called = True

        middleware = LogContextMiddleware(tracking_app)

        async def mock_receive() -> dict[str, Any]:
            return {}

        async def mock_send(message: dict[str, Any]) -> None:
            pass

        await middleware(scope, mock_receive, mock_send)
        assert called

    @pytest.mark.asyncio
    async def test_middleware_clears_context_after_request(
        self, mock_asgi_scope: dict[str, Any]
    ) -> None:
        """Test that context is cleared after request processing."""
        structlog.reset_defaults()
        configure_logging()

        async def app(scope: Any, receive: Any, send: Any) -> None:
            # Check context is bound during request
            bind_context(test_key="test_value")
            await send({"type": "http.response.start", "status": 200, "headers": []})
            await send({"type": "http.response.body", "body": b""})

        middleware = LogContextMiddleware(app)

        async def mock_receive() -> dict[str, Any]:
            return {"type": "http.request", "body": b""}

        async def mock_send(message: dict[str, Any]) -> None:
            pass

        await middleware(mock_asgi_scope, mock_receive, mock_send)

        # After request, context should be cleared
        logger = get_logger()
        captured = io.StringIO()
        with patch.object(sys, "stdout", captured):
            logger.info("after_request")

        parsed = json.loads(captured.getvalue())
        assert "test_key" not in parsed
