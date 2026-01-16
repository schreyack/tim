"""Authentication endpoints."""

from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import Settings, get_settings
from app.db import get_db
from app.schemas.user import TokenResponse, UserLogin
from app.services.auth import AuthService
from app.services.user import UserNotFoundError, UserService

router = APIRouter()


def get_auth_service(
    settings: Annotated[Settings, Depends(get_settings)],
) -> AuthService:
    """Get auth service instance."""
    return AuthService(settings)


def get_user_service(
    db: Annotated[AsyncSession, Depends(get_db)],
    auth: Annotated[AuthService, Depends(get_auth_service)],
) -> UserService:
    """Get user service instance."""
    return UserService(db, auth)


@router.post("/auth/login", response_model=TokenResponse)
async def login(
    data: UserLogin,
    auth: Annotated[AuthService, Depends(get_auth_service)],
    users: Annotated[UserService, Depends(get_user_service)],
) -> TokenResponse:
    """Authenticate user and return access token."""
    try:
        user = await users.authenticate(data.email, data.password)
    except UserNotFoundError as e:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid credentials",
        ) from e

    token = auth.create_token(user.id)
    return TokenResponse(access_token=token)
