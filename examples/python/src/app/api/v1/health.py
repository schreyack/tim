"""Health check endpoints."""

from typing import Annotated

from fastapi import APIRouter, Depends
from pydantic import BaseModel
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from app.db import get_db

router = APIRouter()


class HealthResponse(BaseModel):
    """Health check response."""

    status: str
    database: str


@router.get("/health", response_model=HealthResponse)
async def health_check(
    db: Annotated[AsyncSession, Depends(get_db)],
) -> HealthResponse:
    """Check application and database health."""
    try:
        await db.execute(text("SELECT 1"))
        db_status = "healthy"
    except Exception:
        db_status = "unhealthy"

    return HealthResponse(
        status="healthy" if db_status == "healthy" else "degraded",
        database=db_status,
    )
