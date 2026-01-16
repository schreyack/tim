"""Integration tests for users API - test_what_when_then naming."""

import pytest
from httpx import AsyncClient


class TestCreateUser:
    """Tests for user creation endpoint."""

    @pytest.mark.asyncio
    async def test_create_user_with_valid_data_returns_201(
        self,
        client: AsyncClient,
    ) -> None:
        """Valid user data creates user and returns 201."""
        response = await client.post(
            "/api/v1/users",
            json={
                "email": "newuser@example.com",
                "password": "secure_password_123",
            },
        )

        assert response.status_code == 201
        data = response.json()
        assert data["email"] == "newuser@example.com"
        assert "id" in data
        assert "password" not in data
        assert "hashed_password" not in data

    @pytest.mark.asyncio
    async def test_create_user_with_duplicate_email_returns_409(
        self,
        client: AsyncClient,
    ) -> None:
        """Duplicate email returns 409 Conflict."""
        # Create first user
        await client.post(
            "/api/v1/users",
            json={
                "email": "duplicate@example.com",
                "password": "secure_password_123",
            },
        )

        # Try to create duplicate
        response = await client.post(
            "/api/v1/users",
            json={
                "email": "duplicate@example.com",
                "password": "different_password",
            },
        )

        assert response.status_code == 409

    @pytest.mark.asyncio
    async def test_create_user_with_invalid_email_returns_422(
        self,
        client: AsyncClient,
    ) -> None:
        """Invalid email format returns 422 Unprocessable Entity."""
        response = await client.post(
            "/api/v1/users",
            json={
                "email": "not-an-email",
                "password": "secure_password_123",
            },
        )

        assert response.status_code == 422

    @pytest.mark.asyncio
    async def test_create_user_with_short_password_returns_422(
        self,
        client: AsyncClient,
    ) -> None:
        """Password too short returns 422 Unprocessable Entity."""
        response = await client.post(
            "/api/v1/users",
            json={
                "email": "test@example.com",
                "password": "short",
            },
        )

        assert response.status_code == 422


class TestGetUser:
    """Tests for get user endpoint."""

    @pytest.mark.asyncio
    async def test_get_user_with_existing_id_returns_user(
        self,
        client: AsyncClient,
    ) -> None:
        """Existing user ID returns user data."""
        # Create user
        create_response = await client.post(
            "/api/v1/users",
            json={
                "email": "getuser@example.com",
                "password": "secure_password_123",
            },
        )
        user_id = create_response.json()["id"]

        # Get user
        response = await client.get(f"/api/v1/users/{user_id}")

        assert response.status_code == 200
        data = response.json()
        assert data["email"] == "getuser@example.com"
        assert data["id"] == user_id

    @pytest.mark.asyncio
    async def test_get_user_with_nonexistent_id_returns_404(
        self,
        client: AsyncClient,
    ) -> None:
        """Nonexistent user ID returns 404 Not Found."""
        response = await client.get(
            "/api/v1/users/00000000-0000-0000-0000-000000000000"
        )

        assert response.status_code == 404


class TestDeleteUser:
    """Tests for delete user endpoint."""

    @pytest.mark.asyncio
    async def test_delete_user_with_existing_id_returns_204(
        self,
        client: AsyncClient,
    ) -> None:
        """Existing user ID deletes user and returns 204."""
        # Create user
        create_response = await client.post(
            "/api/v1/users",
            json={
                "email": "deleteuser@example.com",
                "password": "secure_password_123",
            },
        )
        user_id = create_response.json()["id"]

        # Delete user
        response = await client.delete(f"/api/v1/users/{user_id}")

        assert response.status_code == 204

        # Verify user is gone
        get_response = await client.get(f"/api/v1/users/{user_id}")
        assert get_response.status_code == 404

    @pytest.mark.asyncio
    async def test_delete_user_with_nonexistent_id_returns_404(
        self,
        client: AsyncClient,
    ) -> None:
        """Nonexistent user ID returns 404 Not Found."""
        response = await client.delete(
            "/api/v1/users/00000000-0000-0000-0000-000000000000"
        )

        assert response.status_code == 404
