"""Integration tests for health API - test_what_when_then naming."""

import pytest
from httpx import AsyncClient


class TestHealthCheck:
    """Tests for health check endpoint."""

    @pytest.mark.asyncio
    async def test_health_check_returns_healthy_status(
        self,
        client: AsyncClient,
    ) -> None:
        """Health endpoint returns healthy status."""
        response = await client.get("/api/v1/health")

        assert response.status_code == 200
        data = response.json()
        assert data["status"] == "healthy"
        assert "version" in data

    @pytest.mark.asyncio
    async def test_health_check_includes_security_headers(
        self,
        client: AsyncClient,
    ) -> None:
        """Health endpoint includes required security headers."""
        response = await client.get("/api/v1/health")

        assert response.headers.get("X-Content-Type-Options") == "nosniff"
        assert response.headers.get("X-Frame-Options") == "DENY"
        assert response.headers.get("X-XSS-Protection") == "1; mode=block"
