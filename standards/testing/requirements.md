# Testing Requirements

All TIM projects must meet these testing standards. Violations block merge.

## Coverage Thresholds (Hard Gates)

| Metric | Threshold | Enforcement |
|--------|-----------|-------------|
| Line coverage | >= 90% | CI blocks merge |
| Branch coverage | >= 90% | CI blocks merge |
| Function coverage | >= 90% | CI blocks merge |
| New code coverage | >= 95% | CI blocks merge |

**Note**: All coverage metrics unified at 90% for consistency. For AI development, consistent thresholds are easier to follow than varied ones.

These are **minimum** thresholds. Projects may set higher targets.

## Test Types Required

### Unit Tests

Test individual functions and classes in isolation.

**Requirements**:
- Every public function must have unit tests
- Mock external dependencies
- Fast execution (< 1 second per test)
- Run on every commit (pre-commit hook optional, CI required)

### Integration Tests

Test interactions between components.

**Requirements**:
- API endpoint tests with real database
- Service layer tests with real dependencies
- Run in CI on every PR

### End-to-End Tests

Test critical user journeys.

**Requirements**:
- Happy path for core features
- Critical error scenarios
- Run before production deployment

**Timeout Budget**:
| Environment | Max Duration | Enforcement |
|-------------|--------------|-------------|
| Local | 5 minutes | Warning |
| CI (PR) | 10 minutes | Hard block |
| Pre-deploy | 15 minutes | Hard block |

E2E suites exceeding timeout budgets must be:
1. Parallelized across workers
2. Split into critical vs. extended suites
3. Optimized for faster execution

Long E2E suites slow AI iteration cycles. Keep them fast.

## Test Naming Convention

**Format**: `test_<what>_<when>_<then>`

This format answers:
- **What** is being tested (function/feature)
- **When** (conditions/inputs)
- **Then** (expected outcome)

### Python Examples

```python
# Good - Clear what, when, then
def test_create_user_with_valid_data_returns_user():
    pass

def test_create_user_with_duplicate_email_raises_conflict_error():
    pass

def test_login_with_expired_token_returns_401():
    pass

def test_delete_project_when_user_is_not_owner_raises_forbidden():
    pass

# Bad - Vague or incomplete
def test_create_user():  # Missing when and then
    pass

def test_it_works():  # Meaningless
    pass

def test_user_1():  # What does this test?
    pass
```

### TypeScript Examples

```typescript
// Jest/Vitest style with describe blocks
describe("UserService", () => {
  describe("create", () => {
    it("should return user when valid data provided", async () => {});
    it("should throw ConflictError when email already exists", async () => {});
    it("should hash password before storing", async () => {});
  });

  describe("authenticate", () => {
    it("should return token when credentials are valid", async () => {});
    it("should throw UnauthorizedError when password is wrong", async () => {});
    it("should throw UnauthorizedError when user not found", async () => {});
  });
});

// Function style (alternative)
test("createUser returns user when valid data provided", async () => {});
test("createUser throws ConflictError when email exists", async () => {});
```

## TDD Workflow (Required for New Features)

```
1. Write failing test
   ↓
2. Run test → EXPECT RED
   → If GREEN: Test is wrong, fix test, goto 2
   → If RED: Proceed
   ↓
3. Write minimal code to pass
   ↓
4. Run test
   → If RED: Debug, fix code, goto 4
   → If GREEN: Proceed
   ↓
5. Refactor (tests stay green)
   ↓
6. Commit with message referencing test
```

## Test Organization

### Python Project Structure

```
tests/
├── conftest.py              # Shared fixtures
├── unit/
│   ├── test_user_service.py
│   ├── test_auth_service.py
│   └── test_utils.py
├── integration/
│   ├── conftest.py          # Integration-specific fixtures
│   ├── test_user_api.py
│   └── test_auth_api.py
└── e2e/
    ├── conftest.py          # E2E fixtures (browser, etc.)
    └── test_user_flows.py
```

### TypeScript Project Structure

```
tests/
├── setup.ts                 # Global test setup
├── helpers/
│   ├── factories.ts         # Test data factories
│   └── mocks.ts             # Common mocks
├── unit/
│   ├── services/
│   │   ├── user.test.ts
│   │   └── auth.test.ts
│   └── utils/
│       └── validation.test.ts
├── integration/
│   ├── api/
│   │   ├── users.test.ts
│   │   └── auth.test.ts
│   └── setup.ts             # Integration test setup
└── e2e/
    ├── flows/
    │   └── user-journey.test.ts
    └── setup.ts             # E2E setup (playwright, etc.)
```

## Fixtures and Factories

### Python Fixtures (pytest)

```python
# tests/conftest.py
import pytest
from sqlalchemy.ext.asyncio import AsyncSession
from httpx import AsyncClient

@pytest.fixture
async def db_session() -> AsyncGenerator[AsyncSession, None]:
    """Provides a database session that rolls back after each test."""
    async with test_session() as session:
        yield session
        await session.rollback()

@pytest.fixture
async def client(db_session: AsyncSession) -> AsyncGenerator[AsyncClient, None]:
    """Provides an HTTP client with database override."""
    app.dependency_overrides[get_db] = lambda: db_session
    async with AsyncClient(app=app, base_url="http://test") as client:
        yield client
    app.dependency_overrides.clear()

@pytest.fixture
def user_factory(db_session: AsyncSession):
    """Factory for creating test users."""
    async def create(**overrides) -> User:
        defaults = {
            "email": f"user_{uuid4()}@example.com",
            "username": f"user_{uuid4().hex[:8]}",
            "hashed_password": hash_password("TestPassword123"),
        }
        user = User(**{**defaults, **overrides})
        db_session.add(user)
        await db_session.commit()
        return user
    return create
```

### TypeScript Factories

```typescript
// tests/helpers/factories.ts
import { faker } from "@faker-js/faker";
import { prisma } from "@/db";
import { hashPassword } from "@/utils/auth";

export async function createUser(overrides: Partial<UserCreateInput> = {}) {
  const defaults = {
    email: faker.internet.email(),
    username: faker.internet.userName(),
    password: await hashPassword("TestPassword123"),
  };

  return prisma.user.create({
    data: { ...defaults, ...overrides },
  });
}

export async function createAuthenticatedUser() {
  const user = await createUser();
  const token = generateToken(user);
  return { user, token };
}
```

## Mocking Guidelines

### What to Mock
- External APIs (Stripe, SendGrid, etc.)
- Time-dependent operations
- Random number generation
- File system operations (when not testing them)
- Network requests

### What NOT to Mock
- Your own code under test
- Database operations (use test database)
- Business logic

### Python Mocking

```python
from unittest.mock import AsyncMock, patch

@pytest.fixture
def mock_stripe():
    with patch("app.services.payment.stripe") as mock:
        mock.PaymentIntent.create = AsyncMock(return_value={
            "id": "pi_test_123",
            "status": "succeeded",
        })
        yield mock

async def test_process_payment_creates_stripe_intent(mock_stripe, client):
    response = await client.post("/payments", json={"amount": 1000})
    assert response.status_code == 200
    mock_stripe.PaymentIntent.create.assert_called_once()
```

### TypeScript Mocking

```typescript
import { vi, Mock } from "vitest";
import * as stripeModule from "@/services/stripe";

vi.mock("@/services/stripe");

describe("PaymentService", () => {
  const mockCreatePaymentIntent = stripeModule.createPaymentIntent as Mock;

  beforeEach(() => {
    mockCreatePaymentIntent.mockResolvedValue({
      id: "pi_test_123",
      status: "succeeded",
    });
  });

  it("should create Stripe payment intent", async () => {
    await paymentService.process({ amount: 1000 });
    expect(mockCreatePaymentIntent).toHaveBeenCalledWith({ amount: 1000 });
  });
});
```

## Configuration

### Python (pytest.ini or pyproject.toml)

```toml
[tool.pytest.ini_options]
testpaths = ["tests"]
asyncio_mode = "auto"
addopts = [
    "-v",
    "--tb=short",
    "--strict-markers",
    "--cov=src",
    "--cov-report=term-missing",
    "--cov-fail-under=90",
    "--cov-branch",
]
markers = [
    "slow: marks tests as slow",
    "integration: marks integration tests",
    "e2e: marks end-to-end tests",
]
```

### TypeScript (vitest.config.ts)

```typescript
import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    globals: true,
    environment: "node",
    include: ["tests/**/*.test.ts"],
    coverage: {
      provider: "v8",
      reporter: ["text", "lcov", "html"],
      exclude: ["node_modules", "tests", "dist"],
      thresholds: {
        lines: 90,
        branches: 90,
        functions: 90,
        statements: 90,
      },
    },
    setupFiles: ["tests/setup.ts"],
  },
});
```

## CI Pipeline Integration

```yaml
# .github/workflows/ci.yml
test:
  runs-on: ubuntu-latest
  services:
    postgres:
      image: postgres:16
      env:
        POSTGRES_PASSWORD: test
      ports:
        - 5432:5432
  steps:
    - uses: actions/checkout@v4
    - name: Setup
      # ... setup steps
    - name: Run tests with coverage
      run: npm test  # or pytest
    - name: Upload coverage
      uses: codecov/codecov-action@v4
      with:
        fail_ci_if_error: true
```

## Test Data Management

### Principles
1. Tests create their own data
2. Tests clean up after themselves
3. Tests don't depend on shared state
4. Test data is clearly marked (e.g., `test_` prefix)

### Database Isolation

```python
# Python - Transaction rollback per test
@pytest.fixture
async def db_session():
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)

    async with async_session() as session:
        yield session
        await session.rollback()  # Rolls back all changes
```

```typescript
// TypeScript - Transaction rollback per test
beforeEach(async () => {
  await prisma.$executeRaw`BEGIN`;
});

afterEach(async () => {
  await prisma.$executeRaw`ROLLBACK`;
});
```
