# TIM Example API (Python)

A reference implementation demonstrating TIM Design Standards for Python projects.

## Stack

- **Framework**: FastAPI
- **ORM**: SQLAlchemy 2.0 (async)
- **Migrations**: Alembic
- **Validation**: Pydantic v2
- **Testing**: pytest + httpx
- **Type Checking**: mypy (strict mode)
- **Linting/Formatting**: ruff

## Quick Start

```bash
# Install dependencies
poetry install

# Copy environment config
cp .env.example .env
# Edit .env with your database credentials

# Run migrations
alembic upgrade head

# Start development server
poetry run uvicorn app.main:app --reload

# Run tests
poetry run pytest

# Run with coverage
poetry run pytest --cov --cov-report=term-missing
```

## Project Structure

```
src/app/
├── api/v1/           # API route handlers
│   ├── auth.py       # Authentication endpoints
│   ├── health.py     # Health check endpoint
│   └── users.py      # User CRUD endpoints
├── db/               # Database configuration
│   └── session.py    # Async session management
├── models/           # SQLAlchemy models
│   ├── base.py       # Base model with UUID, timestamps
│   └── user.py       # User model
├── schemas/          # Pydantic schemas
│   └── user.py       # User request/response schemas
├── services/         # Business logic
│   ├── auth.py       # JWT and password handling
│   └── user.py       # User operations
├── config.py         # Pydantic Settings
└── main.py           # FastAPI application factory

tests/
├── conftest.py       # Shared pytest fixtures
├── unit/             # Unit tests (isolated)
│   ├── test_auth_service.py
│   └── test_user_service.py
└── integration/      # Integration tests (with DB)
    ├── test_auth_api.py
    ├── test_health_api.py
    └── test_users_api.py
```

## Standards Demonstrated

### Code Organization
- Max 400 lines per file
- Max 50 lines per function
- Cyclomatic complexity limit of 10

### Testing
- `test_what_when_then` naming convention
- Unit tests in `tests/unit/`
- Integration tests in `tests/integration/`
- Async test support with pytest-asyncio
- 90% coverage minimum

### Security
- JWT authentication with python-jose
- Password hashing with bcrypt
- Pydantic validation on all inputs
- Security headers middleware
- No secrets in code

### Database
- Alembic migrations only (no sync)
- Every migration has upgrade AND downgrade
- UUID primary keys
- Automatic timestamps

## API Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/v1/health` | Health check |
| POST | `/api/v1/auth/login` | User login |
| POST | `/api/v1/users` | Create user |
| GET | `/api/v1/users/{id}` | Get user by ID |
| DELETE | `/api/v1/users/{id}` | Delete user |

## Development

### Pre-commit Checks
```bash
# Type checking
poetry run mypy src

# Linting
poetry run ruff check src tests

# Formatting
poetry run ruff format src tests
```

### Creating Migrations
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

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `DATABASE_URL` | PostgreSQL connection string | Required |
| `JWT_SECRET` | Secret key for JWT signing | Required |
| `JWT_EXPIRY_MINUTES` | Token expiry time | 30 |
| `ENVIRONMENT` | development/staging/production | development |
| `DEBUG` | Enable debug mode | false |
