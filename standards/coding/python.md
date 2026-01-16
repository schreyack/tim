# Python Coding Standards

All TIM Python projects must follow these standards. Violations block commits and merges.

## Stack Requirements

- **Python**: 3.11+
- **Framework**: FastAPI
- **ORM**: SQLAlchemy 2.0 (async mode)
- **Migrations**: Alembic
- **Queue**: Celery + Redis
- **Validation**: Pydantic v2

## Type Annotations

**Requirement**: 100% type coverage. `mypy --strict` must pass.

### Configuration

```toml
# pyproject.toml
[tool.mypy]
python_version = "3.11"
strict = true
warn_return_any = true
warn_unused_ignores = true
disallow_untyped_defs = true
disallow_incomplete_defs = true
check_untyped_defs = true
disallow_untyped_decorators = true
no_implicit_optional = true
warn_redundant_casts = true
plugins = ["pydantic.mypy", "sqlalchemy.ext.mypy.plugin"]

[tool.mypy.plugins.pydantic]
init_forbid_extra = true
init_typed = true
warn_required_dynamic_aliases = true
```

### Examples

```python
# BLOCKED: Missing type annotations
def get_user(user_id):
    return db.query(User).get(user_id)

# BLOCKED: Using Any
def process_data(data: Any) -> Any:
    return data

# ALLOWED: Full annotations
def get_user(user_id: int) -> User | None:
    return db.query(User).get(user_id)

# ALLOWED: Generic types
def get_items(ids: list[int]) -> list[Item]:
    return [get_item(id) for id in ids]
```

## Linting and Formatting

**Requirement**: `ruff check` and `ruff format` must pass with zero issues.

### Configuration

```toml
# pyproject.toml
[tool.ruff]
target-version = "py311"
line-length = 88
src = ["src", "tests"]

[tool.ruff.lint]
select = [
    "E",      # pycodestyle errors
    "W",      # pycodestyle warnings
    "F",      # pyflakes
    "I",      # isort
    "B",      # flake8-bugbear
    "C4",     # flake8-comprehensions
    "UP",     # pyupgrade
    "S",      # flake8-bandit (security)
    "T20",    # flake8-print (no print statements)
    "SIM",    # flake8-simplify
    "ARG",    # flake8-unused-arguments
    "PTH",    # flake8-use-pathlib
    "ERA",    # eradicate (commented-out code)
    "PL",     # pylint
    "RUF",    # ruff-specific rules
]

[tool.ruff.lint.per-file-ignores]
"tests/*" = ["S101"]  # Allow assert in tests
"migrations/*" = ["ERA001"]  # Allow comments in migrations
```

### Banned Patterns

```python
# BLOCKED: print() statements (use logging)
print("Debug info")  # S101

# BLOCKED: bare except
try:
    something()
except:  # E722
    pass

# BLOCKED: mutable default arguments
def func(items: list = []):  # B006
    pass

# BLOCKED: commented-out code
# old_function()  # ERA001
```

## FastAPI Patterns

### Request/Response Models

Always use Pydantic models with strict validation:

```python
from pydantic import BaseModel, Field, EmailStr, ConfigDict

class UserCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")  # Reject unknown fields

    email: EmailStr
    username: str = Field(min_length=3, max_length=50, pattern=r"^[a-zA-Z0-9_]+$")
    password: str = Field(min_length=12)

class UserResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    email: str
    username: str
    created_at: datetime
```

### Dependency Injection

Use FastAPI's `Depends()` for all shared resources:

```python
from fastapi import Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

async def get_db() -> AsyncGenerator[AsyncSession, None]:
    async with async_session() as session:
        yield session

async def get_current_user(
    token: str = Depends(oauth2_scheme),
    db: AsyncSession = Depends(get_db),
) -> User:
    user = await verify_token(token, db)
    if not user:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid authentication credentials",
        )
    return user

@router.get("/me")
async def get_me(current_user: User = Depends(get_current_user)) -> UserResponse:
    return current_user
```

### Error Handling

Use specific exceptions with context:

```python
from fastapi import HTTPException, status

class UserNotFoundError(Exception):
    def __init__(self, user_id: int) -> None:
        self.user_id = user_id
        super().__init__(f"User {user_id} not found")

async def get_user(user_id: int, db: AsyncSession) -> User:
    user = await db.get(User, user_id)
    if not user:
        raise UserNotFoundError(user_id)
    return user

# In route handler, convert to HTTP error
@router.get("/users/{user_id}")
async def get_user_endpoint(
    user_id: int,
    db: AsyncSession = Depends(get_db),
) -> UserResponse:
    try:
        user = await get_user(user_id, db)
    except UserNotFoundError:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"User {user_id} not found",
        )
    return user
```

## SQLAlchemy Patterns

### Model Definition

```python
from sqlalchemy import String, ForeignKey
from sqlalchemy.orm import Mapped, mapped_column, relationship
from app.db.base import Base

class User(Base):
    __tablename__ = "users"

    id: Mapped[int] = mapped_column(primary_key=True)
    email: Mapped[str] = mapped_column(String(255), unique=True, index=True)
    username: Mapped[str] = mapped_column(String(50), unique=True, index=True)
    hashed_password: Mapped[str] = mapped_column(String(255))
    created_at: Mapped[datetime] = mapped_column(default=func.now())

    # Relationships
    posts: Mapped[list["Post"]] = relationship(back_populates="author")
```

### Async Queries

```python
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

async def get_user_by_email(db: AsyncSession, email: str) -> User | None:
    result = await db.execute(select(User).where(User.email == email))
    return result.scalar_one_or_none()

async def get_users_paginated(
    db: AsyncSession,
    skip: int = 0,
    limit: int = 100,
) -> list[User]:
    result = await db.execute(select(User).offset(skip).limit(limit))
    return list(result.scalars().all())
```

## Logging

Use `structlog` for structured logging. Never use `print()`.

```python
import structlog

logger = structlog.get_logger()

async def process_order(order_id: int) -> None:
    logger.info("processing_order", order_id=order_id)
    try:
        await do_processing(order_id)
        logger.info("order_processed", order_id=order_id)
    except ProcessingError as e:
        logger.error("order_processing_failed", order_id=order_id, error=str(e))
        raise
```

## Testing

See [testing/requirements.md](../testing/requirements.md) for full testing standards.

### Naming Convention

```python
# Format: test_<what>_<when>_<then>

def test_create_user_with_valid_data_returns_user():
    pass

def test_create_user_with_duplicate_email_raises_conflict():
    pass

def test_login_with_invalid_password_returns_401():
    pass
```

### Fixtures

```python
import pytest
from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession

@pytest.fixture
async def db_session() -> AsyncGenerator[AsyncSession, None]:
    async with test_session() as session:
        yield session
        await session.rollback()

@pytest.fixture
async def client(db_session: AsyncSession) -> AsyncGenerator[AsyncClient, None]:
    app.dependency_overrides[get_db] = lambda: db_session
    async with AsyncClient(app=app, base_url="http://test") as client:
        yield client
    app.dependency_overrides.clear()

@pytest.fixture
async def test_user(db_session: AsyncSession) -> User:
    user = User(email="test@example.com", username="testuser")
    db_session.add(user)
    await db_session.commit()
    return user
```

## Project Structure

```
project/
├── src/
│   └── app/
│       ├── __init__.py
│       ├── main.py              # FastAPI app initialization
│       ├── config.py            # Pydantic Settings
│       ├── deps.py              # Shared dependencies
│       ├── api/
│       │   └── v1/
│       │       ├── __init__.py
│       │       ├── router.py    # API router aggregation
│       │       ├── users.py     # User endpoints
│       │       └── items.py     # Item endpoints
│       ├── models/
│       │   ├── __init__.py
│       │   ├── user.py
│       │   └── item.py
│       ├── schemas/
│       │   ├── __init__.py
│       │   ├── user.py          # Pydantic schemas
│       │   └── item.py
│       ├── services/
│       │   ├── __init__.py
│       │   ├── user_service.py
│       │   └── item_service.py
│       └── db/
│           ├── __init__.py
│           ├── base.py          # SQLAlchemy Base
│           └── session.py       # Session factory
├── tests/
│   ├── conftest.py
│   ├── unit/
│   └── integration/
├── alembic/
│   ├── versions/
│   └── env.py
├── pyproject.toml
├── alembic.ini
└── Dockerfile
```
