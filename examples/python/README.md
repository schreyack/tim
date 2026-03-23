# TIM Example: Python API

A complete reference implementation demonstrating a TIM-compliant Python/FastAPI project. This example shows how all the TIM standards requirements work together: strict type checking, coverage reporting, file size limits, and proper project structure.

## Features Demonstrated

- **FastAPI** with async SQLAlchemy
- **User Authentication** (JWT tokens)
- **Database** (PostgreSQL with Alembic migrations)
- **Strict Type Checking** (mypy --strict)
- **Security** (password hashing, input validation)
- **Testing** (pytest, coverage reported)

## Project Structure

```text
python/
├── src/
│   └── app/
│       ├── __init__.py
│       ├── main.py              # FastAPI app initialization
│       ├── config.py            # Pydantic Settings
│       ├── api/
│       │   └── v1/
│       │       ├── __init__.py
│       │       ├── auth.py      # Authentication endpoints
│       │       ├── health.py    # Health check endpoint
│       │       └── users.py     # User CRUD endpoints
│       ├── models/
│       │   ├── __init__.py
│       │   ├── base.py          # Base model with UUID, timestamps
│       │   └── user.py          # User model
│       ├── schemas/
│       │   ├── __init__.py
│       │   └── user.py          # Pydantic schemas
│       ├── services/
│       │   ├── __init__.py
│       │   ├── auth.py          # JWT and password handling
│       │   └── user.py          # User business logic
│       └── db/
│           ├── __init__.py
│           └── session.py       # Async session management
├── tests/
│   ├── conftest.py              # Shared fixtures
│   ├── unit/
│   │   ├── test_auth_service.py
│   │   └── test_user_service.py
│   └── integration/
│       ├── test_auth_api.py
│       ├── test_health_api.py
│       └── test_users_api.py
├── alembic/
│   ├── env.py
│   └── versions/
│       └── 001_create_users_table.py
├── pyproject.toml               # Poetry + tools config
├── alembic.ini                  # Alembic configuration
├── .tim-patterns.yaml           # Pattern registry
├── .env.example                 # Environment template
└── .gitignore
```

## Quick Start

```bash
# 1. Copy to your project location
cp -r examples/python /path/to/my-project

# 2. Create virtual environment
cd /path/to/my-project
poetry install

# 3. Copy environment file
cp .env.example .env
# Edit .env with your values

# 4. Start database (requires Docker)
docker run -d --name postgres -e POSTGRES_PASSWORD=postgres -p 5432:5432 postgres:15

# 5. Run migrations
poetry run alembic upgrade head

# 6. Start development server
poetry run uvicorn app.main:app --reload

# 7. Run tests
poetry run pytest

# 8. Run with coverage
poetry run pytest --cov --cov-report=term-missing
```

## Standards Demonstrated

### Code Organization
- Max 500 lines per file
- Max 50 lines per function
- Cyclomatic complexity limit of 10

### Testing
- `test_what_when_then` naming convention
- Unit tests in `tests/unit/`
- Integration tests in `tests/integration/`
- Async test support with pytest-asyncio
- Coverage reported

### Security
- JWT authentication with python-jose
- Password hashing with bcrypt
- Pydantic validation on all inputs
- No secrets in code

### Database
- Alembic migrations only (no sync)
- Every migration has upgrade AND downgrade
- UUID primary keys
- Automatic timestamps

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

# tests/integration/test_auth_api.py
async def test_register_with_valid_data_returns_user(client: AsyncClient):
    response = await client.post("/api/v1/auth/register", json={
        "email": "test@example.com",
        "password": "securepassword123",
    })
    assert response.status_code == 201
    assert response.json()["email"] == "test@example.com"
```

## API Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/v1/health` | Health check |
| POST | `/api/v1/auth/login` | User login |
| POST | `/api/v1/users` | Create user |
| GET | `/api/v1/users/{id}` | Get user by ID |
| DELETE | `/api/v1/users/{id}` | Delete user |

## Running Quality Checks

```bash
# Type checking
poetry run mypy --strict src/

# Linting
poetry run ruff check src/ tests/

# Formatting
poetry run ruff format src/ tests/

# Tests with coverage
poetry run pytest --cov=src

# All checks (what CI runs)
poetry run pre-commit run --all-files
```

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `DATABASE_URL` | PostgreSQL connection string | Required |
| `JWT_SECRET` | Secret key for JWT signing | Required |
| `JWT_EXPIRY_MINUTES` | Token expiry time | 30 |
| `ENVIRONMENT` | development/staging/production | development |
| `DEBUG` | Enable debug mode | false |

## Creating Migrations

```bash
# Auto-generate migration from model changes
alembic revision --autogenerate -m "description"

# Create empty migration
alembic revision -m "description"

# Apply migrations
alembic upgrade head

# Rollback one migration
alembic downgrade -1
```
