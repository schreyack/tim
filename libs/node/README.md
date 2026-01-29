# @tim/lib - TIM Shared Node.js/TypeScript Library

The TIM standards require all Node.js projects to use this shared library. It provides battle-tested implementations of common patterns—configuration, logging, security, API middleware, and testing utilities—ensuring consistent behavior and eliminating bugs in critical infrastructure code.

## Installation

```bash
# From npm registry (when published)
npm install @tim/lib

# Or from git submodule
git submodule add https://github.com/your-org/tim.git lib/tim
npm install ./lib/tim/libs/node
```

## Modules

### Config (`@tim/lib/config`)

Zod-based configuration validation with environment variable loading.

```typescript
import { createConfig, baseEnvSchema, validateProductionConfig } from "@tim/lib/config";
import { z } from "zod";

// Extend the base schema with your app's config
const appEnvSchema = baseEnvSchema.extend({
  STRIPE_API_KEY: z.string().min(1),
  FEATURE_FLAG_X: z.boolean().default(false),
});

// Create validated config
const config = createConfig(appEnvSchema);

// Validate production requirements
if (config.ENVIRONMENT === "production") {
  validateProductionConfig(config);
}
```

### Logging (`@tim/lib/logging`)

Structured JSON logging with pino.

```typescript
import { createLogger, LogContextMiddleware, withContext } from "@tim/lib/logging";

// Create logger
const logger = createLogger({
  level: "info",
  prettyPrint: process.env.NODE_ENV !== "production",
});

// Use in Express
app.use(LogContextMiddleware(logger));

// Log with context
logger.info({ userId: "123", action: "login" }, "User logged in");

// Create child logger with bound context
const userLogger = withContext(logger, { userId: "123" });
userLogger.info("Processing request");
```

### Security (`@tim/lib/security`)

Password hashing and JWT token handling.

```typescript
import {
  hashPassword,
  verifyPassword,
  createAccessToken,
  verifyToken,
  verifyTokenWithFallback,
  generateSecureToken,
  constantTimeCompare,
  TokenValidationError,
} from "@tim/lib/security";

// Password hashing (bcrypt, 12 rounds)
const hashed = await hashPassword("user_password");
const isValid = await verifyPassword("user_password", hashed);

// JWT tokens
const token = createAccessToken(
  { sub: userId, role: "admin" },
  process.env.JWT_SECRET,
  30 // expires in 30 minutes
);

try {
  const payload = verifyToken(token, process.env.JWT_SECRET);
  console.log(payload.sub); // userId
} catch (error) {
  if (error instanceof TokenValidationError) {
    console.log(error.detail); // "expired" or error message
  }
}

// Key rotation support
const payload = verifyTokenWithFallback(
  token,
  process.env.JWT_SECRET,
  process.env.JWT_SECRET_PREVIOUS // fallback during rotation
);

// Secure random tokens
const resetToken = generateSecureToken(32); // 64 hex chars

// Constant-time comparison (prevent timing attacks)
const isMatch = constantTimeCompare(providedToken, storedToken);
```

### API (`@tim/lib/api`)

Express middleware and error handlers.

```typescript
import {
  AppError,
  NotFoundError,
  ConflictError,
  ValidationError,
  UnauthorizedError,
  ForbiddenError,
  setupErrorHandlers,
  securityHeadersMiddleware,
  rateLimitMiddleware,
  createHealthRouter,
  asyncHandler,
  TypedRequest,
} from "@tim/lib/api";

const app = express();

// Security headers (CSP, X-Frame-Options, etc.)
app.use(securityHeadersMiddleware);

// Rate limiting (60 req/min default)
app.use(rateLimitMiddleware(100));

// Health endpoints
app.use(createHealthRouter());
// GET /health, /health/ready, /health/live

// Typed request handlers
interface CreateUserBody {
  email: string;
  password: string;
}

app.post(
  "/users",
  asyncHandler<CreateUserBody>(async (req, res) => {
    const { email, password } = req.body; // typed!
    // ...
  })
);

// Throw errors - they're handled automatically
app.get("/resource/:id", asyncHandler(async (req, res) => {
  const resource = await findResource(req.params.id);
  if (!resource) {
    throw new NotFoundError("Resource not found", `id=${req.params.id}`);
  }
  res.json(resource);
}));

// Setup error handlers (must be last)
setupErrorHandlers(app, logger);
```

### Testing (`@tim/lib/testing`)

Test utilities and factories.

```typescript
import {
  createTestApp,
  createMockConfig,
  UserFactory,
  TestDataFactory,
  assertResponseOk,
  assertResponseCreated,
  assertResponseError,
  assertResponseContains,
  assertPaginatedResponse,
  createMockAuthMiddleware,
  createRequestCapture,
  withRollback,
  cleanTables,
  sleep,
  waitFor,
  createMock,
  createSequenceMock,
} from "@tim/lib/testing";
import request from "supertest";

// Test app with routes
const app = createTestApp((app) => {
  app.get("/test", (req, res) => res.json({ ok: true }));
});

// Mock config for tests
const config = createMockConfig({
  STRIPE_API_KEY: "sk_test_xxx",
});

// User factory
const user = UserFactory.create({ role: "admin" });
const users = UserFactory.createMany(5);

// Custom factories
const ProductFactory = new TestDataFactory((n) => ({
  id: `prod-${n}`,
  name: `Product ${n}`,
  price: n * 100,
}));
const product = ProductFactory.create({ price: 999 });

// Response assertions
const response = await request(app).get("/users");
assertResponseOk(response);
assertResponseContains(response, ["id", "email"]);
assertPaginatedResponse(response, 10);

// Error assertions
const errorResponse = await request(app).get("/not-found");
assertResponseError(errorResponse, 404, "Not found");

// Mock auth middleware
app.use(createMockAuthMiddleware({ id: "user-1", role: "admin" }));

// Request capture for assertions
const capture = createRequestCapture();
app.use(capture.middleware);
// ... make requests ...
expect(capture.requests).toHaveLength(3);
capture.clear();

// Database transaction rollback
await withRollback(prisma, async (tx) => {
  await tx.user.create({ data: userData });
  // Transaction rolls back after test
});

// Async utilities
await sleep(100);
await waitFor(() => someCondition, { timeout: 5000 });

// Mock functions with call tracking
const mockFn = createMock((x: number) => x * 2);
mockFn(5); // 10
expect(mockFn.calls).toHaveLength(1);
expect(mockFn.calls[0].args).toEqual([5]);

// Sequence mock for retry testing
const fetchMock = createSequenceMock([
  new Error("Network error"),
  new Error("Network error"),
  { data: "success" },
]);
// First two calls throw, third succeeds
```

## TypeScript Configuration

The TIM standards require TypeScript strict mode. Ensure your `tsconfig.json` has:

```json
{
  "compilerOptions": {
    "strict": true,
    "moduleResolution": "node16",
    "module": "node16",
    "target": "ES2022"
  }
}
```

## Requirements

- Node.js 20+
- TypeScript 5.0+
- Express 4.18+ (for API module)
- Prisma 5+ (for database test utilities)

## Peer Dependencies

The following are peer dependencies - install them in your project:

```bash
npm install express zod pino bcrypt jsonwebtoken
npm install -D @types/express @types/bcrypt @types/jsonwebtoken
```

## License

Internal use only - TIM Organization.
