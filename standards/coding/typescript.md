# TypeScript Coding Standards

All TIM Node.js projects must use TypeScript with strict mode. No vanilla JavaScript. Violations block commits and merges.

## Stack Requirements

- **Node.js**: 20+
- **Language**: TypeScript 5+ (strict mode)
- **Backend Framework**: Express.js or NestJS
- **ORM**: Prisma (recommended) or Sequelize with migrations
- **Frontend**: React 18+ with TypeScript
- **Validation**: Zod
- **Testing**: Jest or Vitest

## TypeScript Configuration

**Requirement**: Strict mode enabled. `tsc --noEmit` must pass with zero errors.

### Configuration

```json
// tsconfig.json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "NodeNext",
    "moduleResolution": "NodeNext",
    "lib": ["ES2022"],
    "outDir": "./dist",
    "rootDir": "./src",
    "strict": true,
    "noImplicitAny": true,
    "strictNullChecks": true,
    "strictFunctionTypes": true,
    "strictBindCallApply": true,
    "strictPropertyInitialization": true,
    "noImplicitThis": true,
    "useUnknownInCatchVariables": true,
    "alwaysStrict": true,
    "noUnusedLocals": true,
    "noUnusedParameters": true,
    "exactOptionalPropertyTypes": true,
    "noImplicitReturns": true,
    "noFallthroughCasesInSwitch": true,
    "noUncheckedIndexedAccess": true,
    "noImplicitOverride": true,
    "noPropertyAccessFromIndexSignature": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "forceConsistentCasingInFileNames": true,
    "declaration": true,
    "declarationMap": true,
    "sourceMap": true
  },
  "include": ["src/**/*"],
  "exclude": ["node_modules", "dist"]
}
```

### Banned Patterns

```typescript
// BLOCKED: any type
function process(data: any): any {  // Error: no-explicit-any
  return data;
}

// BLOCKED: type assertions without validation
const user = data as User;  // Dangerous - use type guards

// BLOCKED: non-null assertions without checks
const name = user!.name;  // Error: prefer explicit null checks

// ALLOWED: proper type narrowing
function getUser(data: unknown): User {
  if (!isUser(data)) {
    throw new Error("Invalid user data");
  }
  return data;
}

// Type guard
function isUser(data: unknown): data is User {
  return (
    typeof data === "object" &&
    data !== null &&
    "id" in data &&
    "email" in data
  );
}
```

## ESLint Configuration

**Requirement**: `eslint --max-warnings 0` must pass.

### Configuration

```javascript
// eslint.config.js (flat config)
import eslint from "@eslint/js";
import tseslint from "typescript-eslint";
import security from "eslint-plugin-security";

export default tseslint.config(
  eslint.configs.recommended,
  ...tseslint.configs.strictTypeChecked,
  ...tseslint.configs.stylisticTypeChecked,
  {
    plugins: {
      security,
    },
    languageOptions: {
      parserOptions: {
        project: true,
        tsconfigRootDir: import.meta.dirname,
      },
    },
    rules: {
      // Type safety
      "@typescript-eslint/no-explicit-any": "error",
      "@typescript-eslint/no-unsafe-assignment": "error",
      "@typescript-eslint/no-unsafe-call": "error",
      "@typescript-eslint/no-unsafe-member-access": "error",
      "@typescript-eslint/no-unsafe-return": "error",
      "@typescript-eslint/explicit-function-return-type": "error",
      "@typescript-eslint/explicit-module-boundary-types": "error",

      // Security
      "security/detect-object-injection": "error",
      "security/detect-non-literal-regexp": "error",
      "security/detect-non-literal-fs-filename": "error",
      "security/detect-eval-with-expression": "error",
      "security/detect-child-process": "warn",

      // Code quality
      "no-console": "error",
      "@typescript-eslint/no-unused-vars": ["error", { "argsIgnorePattern": "^_" }],
      "@typescript-eslint/prefer-nullish-coalescing": "error",
      "@typescript-eslint/prefer-optional-chain": "error",
    },
  },
  {
    files: ["**/*.test.ts", "**/*.spec.ts"],
    rules: {
      "@typescript-eslint/no-unsafe-assignment": "off",
    },
  }
);
```

## Prettier Configuration

**Requirement**: `prettier --check .` must pass.

```json
// .prettierrc
{
  "semi": true,
  "trailingComma": "es5",
  "singleQuote": false,
  "printWidth": 100,
  "tabWidth": 2,
  "useTabs": false
}
```

## Input Validation with Zod

All external input must be validated with Zod schemas in strict mode:

```typescript
import { z } from "zod";

// Request schemas
export const CreateUserSchema = z
  .object({
    email: z.string().email(),
    username: z
      .string()
      .min(3)
      .max(50)
      .regex(/^[a-zA-Z0-9_]+$/),
    password: z.string().min(12),
  })
  .strict(); // Reject unknown fields

export type CreateUserInput = z.infer<typeof CreateUserSchema>;

// Validation middleware (Express)
import { Request, Response, NextFunction } from "express";

export function validate<T>(schema: z.ZodSchema<T>) {
  return (req: Request, res: Response, next: NextFunction): void => {
    const result = schema.safeParse(req.body);
    if (!result.success) {
      res.status(400).json({
        error: "Validation failed",
        details: result.error.issues,
      });
      return;
    }
    req.body = result.data;
    next();
  };
}

// Usage
app.post("/users", validate(CreateUserSchema), createUserHandler);
```

## Express Patterns

### Route Handler Types

```typescript
import { Request, Response, NextFunction } from "express";

// Typed request body
interface TypedRequest<T> extends Request {
  body: T;
}

// Handler with proper types
export async function createUser(
  req: TypedRequest<CreateUserInput>,
  res: Response,
  next: NextFunction
): Promise<void> {
  try {
    const user = await userService.create(req.body);
    res.status(201).json(user);
  } catch (error) {
    next(error);
  }
}
```

### Error Handling Middleware

```typescript
import { Request, Response, NextFunction } from "express";
import { logger } from "./logger";

export class AppError extends Error {
  constructor(
    public statusCode: number,
    message: string,
    public isOperational = true
  ) {
    super(message);
    Object.setPrototypeOf(this, AppError.prototype);
  }
}

export function errorHandler(
  err: Error,
  req: Request,
  res: Response,
  _next: NextFunction
): void {
  if (err instanceof AppError && err.isOperational) {
    res.status(err.statusCode).json({ error: err.message });
    return;
  }

  logger.error("Unhandled error", {
    error: err.message,
    stack: err.stack,
    path: req.path,
    method: req.method,
  });

  res.status(500).json({ error: "Internal server error" });
}
```

## Prisma Patterns

### Schema Definition

```prisma
// prisma/schema.prisma
generator client {
  provider = "prisma-client-js"
}

datasource db {
  provider = "postgresql"
  url      = env("DATABASE_URL")
}

model User {
  id        Int      @id @default(autoincrement())
  email     String   @unique
  username  String   @unique
  password  String
  createdAt DateTime @default(now()) @map("created_at")
  updatedAt DateTime @updatedAt @map("updated_at")
  posts     Post[]

  @@map("users")
  @@index([email])
  @@index([username])
}
```

### Type-Safe Queries

```typescript
import { PrismaClient, User, Prisma } from "@prisma/client";

const prisma = new PrismaClient();

export async function getUserByEmail(email: string): Promise<User | null> {
  return prisma.user.findUnique({
    where: { email },
  });
}

export async function createUser(
  data: Prisma.UserCreateInput
): Promise<User> {
  return prisma.user.create({ data });
}

export async function getUsersWithPosts(): Promise<
  Array<User & { posts: Post[] }>
> {
  return prisma.user.findMany({
    include: { posts: true },
  });
}
```

### Migrations

```bash
# Create migration
npx prisma migrate dev --name add_users_table

# Apply to production
npx prisma migrate deploy

# Generate client after schema changes
npx prisma generate
```

## Logging

Use structured logging. Never use `console.log()`.

```typescript
import pino from "pino";

export const logger = pino({
  level: process.env.LOG_LEVEL ?? "info",
  formatters: {
    level: (label) => ({ level: label }),
  },
  redact: ["password", "token", "authorization"],
});

// Usage
logger.info({ userId: 123 }, "User created");
logger.error({ error: err.message, stack: err.stack }, "Request failed");
```

## Testing

See [testing/requirements.md](../testing/requirements.md) for full testing standards.

### Naming Convention

```typescript
// Format: describe what, it should when then

describe("UserService", () => {
  describe("create", () => {
    it("should return user when valid data provided", async () => {});
    it("should throw ConflictError when email exists", async () => {});
  });
});

// Or function-based:
// test_<what>_<when>_<then>
test("createUser returns user when valid data provided", async () => {});
test("createUser throws ConflictError when email exists", async () => {});
```

## Project Structure

```
project/
├── src/
│   ├── index.ts              # Entry point
│   ├── app.ts                # Express app setup
│   ├── config.ts             # Environment configuration
│   ├── routes/
│   │   ├── index.ts          # Route aggregation
│   │   ├── users.ts          # User routes
│   │   └── items.ts          # Item routes
│   ├── controllers/
│   │   ├── users.ts          # User handlers
│   │   └── items.ts          # Item handlers
│   ├── services/
│   │   ├── users.ts          # User business logic
│   │   └── items.ts          # Item business logic
│   ├── schemas/
│   │   ├── users.ts          # Zod schemas
│   │   └── items.ts
│   ├── middleware/
│   │   ├── auth.ts           # Authentication
│   │   ├── validate.ts       # Request validation
│   │   └── error.ts          # Error handling
│   └── utils/
│       ├── logger.ts         # Structured logging
│       └── errors.ts         # Custom error classes
├── prisma/
│   ├── schema.prisma
│   └── migrations/
├── tests/
│   ├── setup.ts
│   ├── unit/
│   └── integration/
├── package.json
├── tsconfig.json
├── eslint.config.js
├── .prettierrc
└── Dockerfile
```

## React Frontend Standards

### Component Types

```typescript
// Props with explicit types
interface UserCardProps {
  user: User;
  onEdit: (userId: number) => void;
  className?: string;
}

export function UserCard({ user, onEdit, className }: UserCardProps): JSX.Element {
  return (
    <div className={className}>
      <h2>{user.name}</h2>
      <button onClick={() => onEdit(user.id)}>Edit</button>
    </div>
  );
}
```

### Hooks with Types

```typescript
import { useState, useCallback } from "react";

interface UseToggleReturn {
  value: boolean;
  toggle: () => void;
  setTrue: () => void;
  setFalse: () => void;
}

export function useToggle(initial = false): UseToggleReturn {
  const [value, setValue] = useState(initial);

  const toggle = useCallback(() => setValue((v) => !v), []);
  const setTrue = useCallback(() => setValue(true), []);
  const setFalse = useCallback(() => setValue(false), []);

  return { value, toggle, setTrue, setFalse };
}
```
