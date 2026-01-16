# TIM Example: Python API

A reference implementation demonstrating TIM Design Standards for a Python/FastAPI project.

## Features Demonstrated

- **FastAPI** with async SQLAlchemy
- **User Authentication** (JWT tokens)
- **Database** (PostgreSQL with Alembic migrations)
- **Strict Type Checking** (mypy --strict)
- **Security** (password hashing, input validation, rate limiting)
- **Testing** (pytest, 90%+ coverage)
- **Logging** (structured JSON with structlog)

## Project Structure

```
python-api/
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
│       │       ├── auth.py      # Authentication endpoints
│       │       └── users.py     # User CRUD endpoints
│       ├── models/
│       │   ├── __init__.py
│       │   └── user.py          # SQLAlchemy models
│       ├── schemas/
│       │   ├── __init__.py
│       │   ├── user.py          # Pydantic schemas
│       │   └── auth.py          # Auth-related schemas
│       ├── services/
│       │   ├── __init__.py
│       │   ├── user.py          # User business logic
│       │   └── auth.py          # Auth business logic
│       └── db/
│           ├── __init__.py
│           ├── base.py          # SQLAlchemy Base
│           └── session.py       # Session factory
├── tests/
│   ├── conftest.py              # Shared fixtures
│   ├── unit/
│   │   └── test_auth_service.py
│   └── integration/
│       └── test_auth_endpoints.py
├── alembic/
│   ├── env.py
│   └── versions/
├── pyproject.toml               # Poetry + tools config
├── .pre-commit-config.yaml      # Pre-commit hooks
├── .env.example                 # Environment template
├── Dockerfile
└── docker-compose.yml
```

## Quick Start

```bash
# 1. Copy to your project location
cp -r examples/python-api /path/to/my-project

# 2. Create virtual environment
cd /path/to/my-project
poetry install

# 3. Copy environment file
cp .env.example .env
# Edit .env with your values

# 4. Start database
docker-compose up -d postgres

# 5. Run migrations
poetry run alembic upgrade head

# 6. Start development server
poetry run uvicorn app.main:app --reload

# 7. Run tests
poetry run pytest

# 8. Install pre-commit hooks
poetry run pre-commit install
```

## Key Patterns

### Configuration (Pydantic Settings)

```python
# src/app/config.py
from pydantic_settings import BaseSettings

class Settings(BaseSettings):
    # Required - no defaults for secrets
    database_url: str
    jwt_secret: str

    # Optional with sensible defaults
    jwt_algorithm: str = "HS256"
    access_token_expire_minutes: int = 30

    class Config:
        env_file = ".env"

settings = Settings()
```

### Dependency Injection

```python
# src/app/deps.py
async def get_db() -> AsyncGenerator[AsyncSession, None]:
    async with async_session() as session:
        yield session

async def get_current_user(
    token: str = Depends(oauth2_scheme),
    db: AsyncSession = Depends(get_db),
) -> User:
    # Verify token, return user
    ...
```

### Type-Safe Models

```python
# src/app/models/user.py
from sqlalchemy.orm import Mapped, mapped_column

class User(Base):
    __tablename__ = "users"

    id: Mapped[int] = mapped_column(primary_key=True)
    email: Mapped[str] = mapped_column(unique=True, index=True)
    hashed_password: Mapped[str]
    is_active: Mapped[bool] = mapped_column(default=True)
```

### Input Validation

```python
# src/app/schemas/user.py
from pydantic import BaseModel, EmailStr, Field, ConfigDict

class UserCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    email: EmailStr
    password: str = Field(min_length=12)
```

### Error Handling

```python
# Custom exceptions with context
class UserNotFoundError(Exception):
    def __init__(self, user_id: int) -> None:
        self.user_id = user_id
        super().__init__(f"User {user_id} not found")

# HTTP error mapping in endpoints
@router.get("/users/{user_id}")
async def get_user(user_id: int, db: AsyncSession = Depends(get_db)):
    try:
        return await user_service.get(db, user_id)
    except UserNotFoundError:
        raise HTTPException(status_code=404, detail="User not found")
```

### Structured Logging

```python
import structlog

logger = structlog.get_logger()

async def create_user(db: AsyncSession, user_in: UserCreate) -> User:
    logger.info("creating_user", email=user_in.email)
    # ...
    logger.info("user_created", user_id=user.id)
    return user
```

### Test Patterns

```python
# tests/conftest.py
@pytest.fixture
async def db_session():
    async with test_session() as session:
        yield session
        await session.rollback()

@pytest.fixture
async def client(db_session):
    app.dependency_overrides[get_db] = lambda: db_session
    async with AsyncClient(app=app, base_url="http://test") as c:
        yield c
    app.dependency_overrides.clear()

# tests/integration/test_auth_endpoints.py
async def test_register_with_valid_data_returns_user(client: AsyncClient):
    response = await client.post("/api/v1/auth/register", json={
        "email": "test@example.com",
        "password": "securepassword123",
    })
    assert response.status_code == 201
    assert response.json()["email"] == "test@example.com"

async def test_register_with_duplicate_email_returns_409(
    client: AsyncClient,
    existing_user: User,
):
    response = await client.post("/api/v1/auth/register", json={
        "email": existing_user.email,
        "password": "securepassword123",
    })
    assert response.status_code == 409
```

## Running Quality Checks

```bash
# Type checking
poetry run mypy --strict src/

# Linting
poetry run ruff check src/ tests/

# Formatting
poetry run ruff format src/ tests/

# Tests with coverage
poetry run pytest --cov=src --cov-fail-under=90

# All checks (what CI runs)
poetry run pre-commit run --all-files
```

## Deployment

```bash
# Build Docker image
docker build -t my-api .

# Deploy with ops.sh
./ops.sh deploy --environment production --confirm
```
