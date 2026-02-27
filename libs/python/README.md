# TIM Shared Python Library (tim-lib)

The TIM standards require all Python projects to use this shared library. It provides battle-tested implementations of common patterns—configuration, logging, security, database access, and testing utilities—so projects don't reinvent the wheel or introduce bugs in critical infrastructure code.

## Installation

### Option 1: Git Submodule (Recommended)

```bash
# Add tim as submodule
git submodule add https://github.com/schreyack/tim lib/tim

# Install the library
pip install -e lib/tim/libs/python

# Or with Poetry
poetry add ./lib/tim/libs/python
```

### Option 2: Direct Install

```bash
pip install git+https://github.com/schreyack/tim#subdirectory=libs/python
```

## Modules

### `tim_lib.config` - Configuration

Pydantic base settings with TIM-specific validation.

```python
from tim_lib import BaseAppSettings

class Settings(BaseAppSettings):
    # Add your project-specific settings
    stripe_api_key: str
    feature_x_enabled: bool = False

settings = Settings()  # Loads from .env and environment
```

Features:

- Required secrets validation (no empty JWT_SECRET)
- Production safety checks (no localhost DB in prod)
- Masked secrets for logging

### `tim_lib.logging` - Structured Logging

JSON logging with structlog.

```python
from tim_lib import configure_logging, get_logger

configure_logging(
    level="INFO",
    json_output=True,
    service_name="my-api",
)

logger = get_logger(__name__)
logger.info("user_created", user_id=123, email="user@example.com")
# Output: {"event": "user_created", "user_id": 123, "email": "user@example.com", ...}
```

### `tim_lib.security` - Security Helpers

Password hashing and JWT tokens.

```python
from tim_lib import hash_password, verify_password, create_access_token, verify_token

# Password handling
hashed = hash_password("user_password")
is_valid = verify_password("user_password", hashed)

# JWT tokens
token = create_access_token(
    data={"sub": str(user.id)},
    secret=settings.jwt_secret,
    expires_minutes=30,
)

payload = verify_token(token, settings.jwt_secret)
```

### `tim_lib.db` - Database Utilities

SQLAlchemy async session management.

```python
from tim_lib.db import (
    Base,
    create_async_engine_with_pool,
    get_session_factory,
    dependency_get_db,
    DatabaseHealthCheck,
)

# Setup
engine = create_async_engine_with_pool(settings.database_url)
async_session = get_session_factory(engine)
get_db = dependency_get_db(async_session)

# Health checks
health = DatabaseHealthCheck(engine)
is_healthy = await health.is_healthy()
```

### `tim_lib.api` - FastAPI Helpers

Middleware, error handlers, and utilities.

```python
from tim_lib.api import (
    setup_exception_handlers,
    security_headers_middleware,
    RateLimitMiddleware,
    create_health_router,
    NotFoundError,
    ConflictError,
)

app = FastAPI()

# Error handling
setup_exception_handlers(app)

# Security headers
app.middleware("http")(security_headers_middleware)

# Rate limiting
app.add_middleware(RateLimitMiddleware, requests_per_minute=60)

# Health endpoints
app.include_router(create_health_router())

# Use custom exceptions
@app.get("/users/{user_id}")
async def get_user(user_id: int):
    user = await user_service.get(user_id)
    if not user:
        raise NotFoundError(f"User {user_id} not found")
    return user
```

### `tim_lib.testing` - Test Utilities

Fixtures and helpers for pytest.

```python
from tim_lib.testing import (
    create_test_db_session,
    AsyncTestClient,
    create_mock_settings,
    UserFactory,
    assert_response_ok,
)

@pytest.fixture
async def db_session():
    async for session in create_test_db_session(test_engine):
        yield session

@pytest.fixture
async def client(db_session):
    async for c in AsyncTestClient(app, db_override=db_session):
        yield c

async def test_create_user(client):
    user_data = UserFactory().build()
    response = await client.post("/users", json=user_data)
    assert_response_ok(response)
```

## Updating

```bash
# Update submodule to latest
cd lib/tim
git pull origin main
cd ../..
git add lib/tim
git commit -m "chore: update tim-lib"
```

## Development

```bash
cd libs/python

# Install dev dependencies
poetry install

# Run tests
poetry run pytest

# Type check
poetry run mypy --strict tim_lib/

# Lint
poetry run ruff check tim_lib/
```
