# TIM Example API (Node.js)

A reference implementation demonstrating TIM Design Standards for Node.js projects.

## Stack

- **Framework**: Express.js
- **Language**: TypeScript (strict mode)
- **ORM**: Prisma
- **Validation**: Zod
- **Testing**: Vitest + Supertest
- **Linting**: ESLint
- **Formatting**: Prettier

## Quick Start

```bash
# Install dependencies
npm install

# Copy environment config
cp .env.example .env
# Edit .env with your database credentials

# Generate Prisma client
npm run db:generate

# Run migrations
npm run db:migrate:prod

# Start development server
npm run dev

# Run tests
npm test

# Run with coverage
npm run test:coverage
```

## Project Structure

```
src/
├── api/              # Route handlers
│   ├── auth.ts       # Authentication endpoints
│   ├── health.ts     # Health check endpoint
│   └── users.ts      # User CRUD endpoints
├── db/               # Database configuration
│   └── client.ts     # Prisma client singleton
├── middleware/       # Express middleware
│   ├── error.ts      # Global error handler
│   └── validation.ts # Zod validation middleware
├── schemas/          # Zod validation schemas
│   └── user.ts       # User request/response schemas
├── services/         # Business logic
│   ├── auth.ts       # JWT and password handling
│   ├── errors.ts     # Custom error classes
│   └── user.ts       # User operations
├── app.ts            # Express application factory
├── config.ts         # Environment configuration
└── index.ts          # Application entry point

tests/
├── unit/             # Unit tests (isolated)
│   ├── auth.test.ts
│   └── schemas.test.ts
└── integration/      # Integration tests (with app)
    └── health.test.ts

prisma/
└── schema.prisma     # Database schema
```

## Standards Demonstrated

### Code Organization
- Max 400 lines per file
- Max 50 lines per function
- Cyclomatic complexity limit of 10

### TypeScript
- `strict: true` in tsconfig
- Explicit return types required
- No `any` types allowed
- Type imports for interfaces

### Testing
- `should_what_when_then` naming convention
- Unit tests in `tests/unit/`
- Integration tests in `tests/integration/`
- 90% coverage minimum

### Security
- JWT authentication with jsonwebtoken
- Password hashing with bcrypt
- Zod validation on all inputs
- Helmet security headers
- No secrets in code

### Database
- Prisma migrations only
- UUID primary keys
- Automatic timestamps

## API Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/v1/health` | Health check |
| POST | `/api/v1/auth/login` | User login |
| POST | `/api/v1/users` | Create user |
| GET | `/api/v1/users/:id` | Get user by ID |
| DELETE | `/api/v1/users/:id` | Delete user |

## Development

### Quality Checks
```bash
# Type checking
npm run typecheck

# Linting
npm run lint

# Formatting
npm run format:check

# All checks
npm run check
```

### Creating Migrations
```bash
# Create migration from schema changes
npm run db:migrate

# Apply migrations (production)
npm run db:migrate:prod

# Push schema without migration (dev only)
npm run db:push
```

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `DATABASE_URL` | PostgreSQL connection string | Required |
| `JWT_SECRET` | Secret key for JWT signing | Required |
| `JWT_EXPIRY_MINUTES` | Token expiry time | 30 |
| `NODE_ENV` | development/staging/production | development |
| `PORT` | Server port | 3000 |
