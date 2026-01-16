"""Integration tests for auth API - test_what_when_then naming."""

import pytest
from httpx import AsyncClient


class TestLogin:
    """Tests for login endpoint."""

    @pytest.mark.asyncio
    async def test_login_with_valid_credentials_returns_token(
        self,
        client: AsyncClient,
    ) -> None:
        """Valid credentials return an access token."""
        # First create a user
        await client.post(
            "/api/v1/users",
            json={
                "email": "test@example.com",
                "password": "secure_password_123",
            },
        )

        # Then login
        response = await client.post(
            "/api/v1/auth/login",
            json={
                "email": "test@example.com",
                "password": "secure_password_123",
            },
        )

        assert response.status_code == 200
        data = response.json()
        assert "access_token" in data
        assert data["token_type"] == "bearer"

    @pytest.mark.asyncio
    async def test_login_with_invalid_credentials_returns_401(
        self,
        client: AsyncClient,
    ) -> None:
        """Invalid credentials return 401 Unauthorized."""
        response = await client.post(
            "/api/v1/auth/login",
            json={
                "email": "nonexistent@example.com",
                "password": "wrong_password",
            },
        )

        assert response.status_code == 401
        data = response.json()
        assert "detail" in data

    @pytest.mark.asyncio
    async def test_login_with_wrong_password_returns_401(
        self,
        client: AsyncClient,
    ) -> None:
        """Wrong password returns 401 Unauthorized."""
        # First create a user
        await client.post(
            "/api/v1/users",
            json={
                "email": "test@example.com",
                "password": "secure_password_123",
            },
        )

        # Then try to login with wrong password
        response = await client.post(
            "/api/v1/auth/login",
            json={
                "email": "test@example.com",
                "password": "wrong_password",
            },
        )

        assert response.status_code == 401

    @pytest.mark.asyncio
    async def test_login_with_invalid_email_format_returns_422(
        self,
        client: AsyncClient,
    ) -> None:
        """Invalid email format returns 422 Unprocessable Entity."""
        response = await client.post(
            "/api/v1/auth/login",
            json={
                "email": "not-an-email",
                "password": "any_password",
            },
        )

        assert response.status_code == 422
