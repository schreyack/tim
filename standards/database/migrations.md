# Database Migration Standards

All schema changes must go through the migration system. Direct schema modifications are forbidden.

## Core Principles

1. **Migrations only** - No `sync()`, no `create_all()`, no manual DDL
2. **Immutable** - Never modify an applied migration
3. **Reversible** - Every migration must have a working rollback
4. **Reviewed** - Schema changes require PR review
5. **Tested** - Migrations tested in CI before production

## Banned Operations

These are **hard blocks** in CI:

### Python (SQLAlchemy)

```python
# BLOCKED - CI will fail
Base.metadata.create_all(engine)
Base.metadata.drop_all(engine)
connection.execute(text("ALTER TABLE ..."))  # Raw DDL
```

### Node.js (Sequelize)

```typescript
// BLOCKED - CI will fail
sequelize.sync()
sequelize.sync({ force: true })
sequelize.sync({ alter: true })
queryInterface.sequelize.query("ALTER TABLE ...")  // Raw DDL
```

### Node.js (Prisma)

```bash
# BLOCKED in production
prisma db push  # Only for prototyping
```

## Python Migration Workflow (Alembic)

### Setup

```bash
# Initialize Alembic (one-time)
alembic init alembic
```

### Configuration

```python
# alembic/env.py
from app.models import Base
from app.config import settings

target_metadata = Base.metadata

def get_url():
    return settings.database_url
```

### Creating Migrations

```bash
# Auto-generate from model changes
alembic revision --autogenerate -m "add_users_table"

# Create empty migration for custom changes
alembic revision -m "add_custom_index"
```

### Migration Structure

```python
# alembic/versions/xxxx_add_users_table.py
"""add users table

Revision ID: abc123
Revises: def456
Create Date: 2025-01-15 10:00:00.000000
"""
from alembic import op
import sqlalchemy as sa

revision = "abc123"
down_revision = "def456"
branch_labels = None
depends_on = None

def upgrade() -> None:
    op.create_table(
        "users",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("email", sa.String(255), nullable=False),
        sa.Column("created_at", sa.DateTime(), server_default=sa.func.now()),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("email"),
    )
    op.create_index("ix_users_email", "users", ["email"])

def downgrade() -> None:
    op.drop_index("ix_users_email", "users")
    op.drop_table("users")
```

### Running Migrations

```bash
# Apply all pending migrations
alembic upgrade head

# Apply specific migration
alembic upgrade abc123

# Rollback one migration
alembic downgrade -1

# Rollback to specific revision
alembic downgrade def456

# Show current revision
alembic current

# Show migration history
alembic history
```

## Node.js Migration Workflow (Prisma)

### Setup

```bash
# Initialize Prisma (one-time)
npx prisma init
```

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
  createdAt DateTime @default(now()) @map("created_at")

  @@map("users")
  @@index([email])
}
```

### Creating Migrations

```bash
# Create migration from schema changes
npx prisma migrate dev --name add_users_table

# Create empty migration for custom SQL
npx prisma migrate dev --create-only --name custom_index
```

### Migration Structure

```sql
-- prisma/migrations/20250115_add_users_table/migration.sql
CREATE TABLE "users" (
    "id" SERIAL NOT NULL,
    "email" VARCHAR(255) NOT NULL,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "users_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "users_email_key" ON "users"("email");
CREATE INDEX "ix_users_email" ON "users"("email");
```

### Running Migrations

```bash
# Development - creates and applies migration
npx prisma migrate dev

# Production - applies pending migrations
npx prisma migrate deploy

# Reset database (development only!)
npx prisma migrate reset

# Check migration status
npx prisma migrate status
```

## Node.js Migration Workflow (Sequelize CLI)

For projects using Sequelize instead of Prisma.

### Setup

```bash
# Initialize (one-time)
npx sequelize-cli init
```

### Creating Migrations

```bash
# Generate migration
npx sequelize-cli migration:generate --name add-users-table
```

### Migration Structure

```javascript
// migrations/20250115-add-users-table.js
"use strict";

module.exports = {
  async up(queryInterface, Sequelize) {
    await queryInterface.createTable("users", {
      id: {
        type: Sequelize.INTEGER,
        primaryKey: true,
        autoIncrement: true,
      },
      email: {
        type: Sequelize.STRING(255),
        allowNull: false,
        unique: true,
      },
      created_at: {
        type: Sequelize.DATE,
        defaultValue: Sequelize.literal("CURRENT_TIMESTAMP"),
      },
    });

    await queryInterface.addIndex("users", ["email"]);
  },

  async down(queryInterface) {
    await queryInterface.dropTable("users");
  },
};
```

### Running Migrations

```bash
# Apply all pending
npx sequelize-cli db:migrate

# Rollback last migration
npx sequelize-cli db:migrate:undo

# Rollback all migrations
npx sequelize-cli db:migrate:undo:all

# Check status
npx sequelize-cli db:migrate:status
```

## Migration Best Practices

### 1. Small, Focused Migrations

```python
# GOOD - One focused change
def upgrade():
    op.add_column("users", sa.Column("phone", sa.String(20)))

def downgrade():
    op.drop_column("users", "phone")
```

```python
# BAD - Multiple unrelated changes
def upgrade():
    op.add_column("users", sa.Column("phone", sa.String(20)))
    op.create_table("orders", ...)
    op.add_index(...)
```

### 2. Zero-Downtime Migrations

For production with high availability:

**Adding a column**:

```python
# Step 1: Add nullable column
op.add_column("users", sa.Column("phone", sa.String(20), nullable=True))

# Step 2: (Separate migration) Add default and make non-null
op.execute("UPDATE users SET phone = '' WHERE phone IS NULL")
op.alter_column("users", "phone", nullable=False)
```

**Renaming a column**:

```python
# Step 1: Add new column
op.add_column("users", sa.Column("full_name", sa.String(255)))

# Step 2: Copy data (application handles both columns)
op.execute("UPDATE users SET full_name = name")

# Step 3: (After code deployment) Drop old column
op.drop_column("users", "name")
```

### 3. Always Test Rollback

```bash
# Test migration cycle
alembic upgrade head
alembic downgrade -1
alembic upgrade head
```

### 4. Data Migrations

Separate schema changes from data changes:

```python
# Migration 1: Schema change
def upgrade():
    op.add_column("users", sa.Column("status", sa.String(20)))

# Migration 2: Data backfill
def upgrade():
    op.execute("UPDATE users SET status = 'active' WHERE status IS NULL")
```

## CI Integration

### Pre-merge Checks

```yaml
# .github/workflows/ci.yml
migration-check:
  runs-on: ubuntu-latest
  services:
    postgres:
      image: postgres:16
      env:
        POSTGRES_PASSWORD: test
  steps:
    - uses: actions/checkout@v4
    - name: Run migrations up
      run: alembic upgrade head
    - name: Run migrations down
      run: alembic downgrade base
    - name: Run migrations up again
      run: alembic upgrade head
    - name: Verify no pending migrations
      run: |
        CURRENT=$(alembic current 2>&1)
        HEAD=$(alembic heads 2>&1)
        if [[ "$CURRENT" != *"$HEAD"* ]]; then
          echo "Pending migrations detected"
          exit 1
        fi
```

### Pre-deploy Check

```bash
# Dry-run migration before deployment
alembic upgrade head --sql > /tmp/migration.sql
# Review SQL output
```

## Schema Review Checklist

Before approving a migration PR:

- [ ] Migration has corresponding downgrade
- [ ] Downgrade tested locally
- [ ] Indexes added for foreign keys
- [ ] Indexes added for frequently queried columns
- [ ] NOT NULL constraints have defaults or data migration
- [ ] No breaking changes to existing columns
- [ ] Large table migrations use batching
- [ ] Migration is idempotent (can run multiple times safely)
- [ ] Performance impact assessed for large tables
