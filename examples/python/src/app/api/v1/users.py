"""User management endpoints."""

from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.v1.auth import get_auth_service, get_user_service
from app.schemas import UserCreate, UserResponse, UserUpdate
from app.services.auth import AuthService
from app.services.user import UserExistsError, UserNotFoundError, UserService

router = APIRouter()


@router.post(
    "/users",
    response_model=UserResponse,
    status_code=status.HTTP_201_CREATED,
)
async def create_user(
    data: UserCreate,
    users: Annotated[UserService, Depends(get_user_service)],
) -> UserResponse:
    """Create a new user."""
    try:
        user = await users.create(data)
    except UserExistsError as e:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="User already exists",
        ) from e

    return UserResponse.model_validate(user)


@router.get("/users/{user_id}", response_model=UserResponse)
async def get_user(
    user_id: str,
    users: Annotated[UserService, Depends(get_user_service)],
) -> UserResponse:
    """Get a user by ID."""
    try:
        user = await users.get_by_id(user_id)
    except UserNotFoundError as e:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User not found",
        ) from e

    return UserResponse.model_validate(user)


@router.patch("/users/{user_id}", response_model=UserResponse)
async def update_user(
    user_id: str,
    data: UserUpdate,
    users: Annotated[UserService, Depends(get_user_service)],
) -> UserResponse:
    """Update a user."""
    try:
        user = await users.update(user_id, data)
    except UserNotFoundError as e:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User not found",
        ) from e

    return UserResponse.model_validate(user)
