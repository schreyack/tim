# OWASP Top 10 Checklist

Every TIM project must address all OWASP Top 10 vulnerabilities. This checklist defines requirements and enforcement mechanisms.

## A01:2021 - Broken Access Control

**Risk**: Users acting outside their intended permissions.

### Requirements

- [ ] Authorization checks on every endpoint
- [ ] Deny by default - explicit grants required
- [ ] CORS configured with allowlist (no wildcards in production)
- [ ] Rate limiting on sensitive endpoints
- [ ] JWT tokens validated on every request
- [ ] Resource ownership verified before access

### Implementation

**Python (FastAPI)**:

```python
from fastapi import Depends, HTTPException, status

async def verify_resource_ownership(
    resource_id: int,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> Resource:
    resource = await db.get(Resource, resource_id)
    if not resource:
        raise HTTPException(status_code=404)
    if resource.owner_id != current_user.id:
        raise HTTPException(status_code=403)
    return resource
```

**TypeScript (Express)**:

```typescript
async function verifyOwnership(
  req: Request,
  res: Response,
  next: NextFunction
): Promise<void> {
  const resource = await prisma.resource.findUnique({
    where: { id: parseInt(req.params.id) },
  });
  if (!resource || resource.ownerId !== req.user.id) {
    res.status(403).json({ error: "Forbidden" });
    return;
  }
  req.resource = resource;
  next();
}
```

### Enforcement

- Unit tests required for every authorization check
- Integration tests for cross-user access attempts

---

## A02:2021 - Cryptographic Failures

**Risk**: Exposure of sensitive data due to weak cryptography.

### Requirements

- [ ] TLS 1.2+ for all connections
- [ ] Passwords hashed with bcrypt (cost factor 12+)
- [ ] Sensitive data encrypted at rest
- [ ] No sensitive data in URLs or logs
- [ ] Secure random number generation only

### Implementation

**Password Hashing**:

```python
# Python
from passlib.context import CryptContext

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

def hash_password(password: str) -> str:
    return pwd_context.hash(password)

def verify_password(plain: str, hashed: str) -> bool:
    return pwd_context.verify(plain, hashed)
```

```typescript
// TypeScript
import bcrypt from "bcrypt";

const SALT_ROUNDS = 12;

export async function hashPassword(password: string): Promise<string> {
  return bcrypt.hash(password, SALT_ROUNDS);
}

export async function verifyPassword(plain: string, hashed: string): Promise<boolean> {
  return bcrypt.compare(plain, hashed);
}
```

### Enforcement

- Security scanner detects weak algorithms
- Pre-commit blocks hardcoded secrets

---

## A03:2021 - Injection

**Risk**: Untrusted data sent to an interpreter.

### Requirements

- [ ] Parameterized queries only (ORM required)
- [ ] Input validation on all external data
- [ ] Output encoding for HTML contexts
- [ ] Command injection prevention

### Implementation

**SQL (Always use ORM)**:

```python
# BLOCKED: Raw SQL
db.execute(f"SELECT * FROM users WHERE id = {user_id}")

# REQUIRED: ORM queries
user = await db.get(User, user_id)
```

```typescript
// BLOCKED: Raw queries
await prisma.$queryRaw`SELECT * FROM users WHERE id = ${userId}`;

// REQUIRED: Prisma client
await prisma.user.findUnique({ where: { id: userId } });
```

### Enforcement

- Linter rules block raw SQL patterns
- Code review flag on `$queryRaw`, `execute()`, `exec()`

---

## A04:2021 - Insecure Design

**Risk**: Missing security controls in architecture.

### Requirements

- [ ] Threat modeling for new features
- [ ] Security review for architectural changes
- [ ] Principle of least privilege
- [ ] Defense in depth (multiple layers)

### Enforcement

- ADR required for security-relevant changes
- Security team review on architecture PRs

---

## A05:2021 - Security Misconfiguration

**Risk**: Insecure default configurations.

### Requirements

- [ ] No default credentials
- [ ] Debug mode disabled in production
- [ ] Error messages don't leak stack traces
- [ ] Unnecessary features disabled
- [ ] Security headers configured

### Implementation

```python
# Python - Production config
class Settings(BaseSettings):
    debug: bool = False  # Never default to True
    secret_key: str  # No default - fails if missing
    database_url: str  # No default - fails if missing

settings = Settings()  # Fails loudly if env vars missing
```

```typescript
// TypeScript - Environment validation
import { z } from "zod";

const EnvSchema = z.object({
  NODE_ENV: z.enum(["development", "production", "test"]),
  DATABASE_URL: z.string().url(),
  JWT_SECRET: z.string().min(32),
});

export const env = EnvSchema.parse(process.env);
```

### Enforcement

- CI validates no default secrets
- Container scan checks for exposed ports

---

## A06:2021 - Vulnerable and Outdated Components

**Risk**: Known vulnerabilities in dependencies.

### Requirements

- [ ] Dependency scanning in CI
- [ ] HIGH/CRITICAL vulnerabilities block merge
- [ ] Regular dependency updates (monthly minimum)
- [ ] No abandoned packages

### Tools

| Stack | Dependency Scan | Container Scan |
|-------|----------------|----------------|
| Python | safety, pip-audit | trivy |
| Node.js | npm audit, Snyk | trivy |

### Enforcement

- CI blocks on HIGH/CRITICAL
- Weekly automated vulnerability reports

---

## A07:2021 - Identification and Authentication Failures

**Risk**: Weak authentication mechanisms.

### Requirements

- [ ] Strong password policy (12+ chars)
- [ ] Account lockout after failed attempts
- [ ] Session timeout (15 min idle, 24h max)
- [ ] Secure session management
- [ ] MFA for admin accounts

### Implementation

```python
# Password validation
from pydantic import BaseModel, Field, field_validator

class PasswordPolicy(BaseModel):
    password: str = Field(min_length=12)

    @field_validator("password")
    @classmethod
    def validate_password(cls, v: str) -> str:
        if not any(c.isupper() for c in v):
            raise ValueError("Must contain uppercase")
        if not any(c.islower() for c in v):
            raise ValueError("Must contain lowercase")
        if not any(c.isdigit() for c in v):
            raise ValueError("Must contain digit")
        return v
```

### Enforcement

- Unit tests for password policy
- Integration tests for session management

---

## A08:2021 - Software and Data Integrity Failures

**Risk**: Code and infrastructure without integrity verification.

### Requirements

- [ ] CI/CD pipeline security
- [ ] Signed commits (recommended)
- [ ] Dependency lock files committed
- [ ] Integrity checks on deployments

### Enforcement

- Branch protection requires CI pass
- Deployment checksums verified

---

## A09:2021 - Security Logging and Monitoring Failures

**Risk**: Insufficient logging for security events.

### Requirements

- [ ] Authentication events logged
- [ ] Authorization failures logged
- [ ] Input validation failures logged
- [ ] No sensitive data in logs
- [ ] Log retention (90 days minimum)

### Implementation

```python
import structlog

logger = structlog.get_logger()

# Log security events
logger.info("auth_success", user_id=user.id, ip=request.client.host)
logger.warning("auth_failure", email=email, ip=request.client.host, reason="invalid_password")
logger.warning("authz_failure", user_id=user.id, resource_id=resource_id, action="delete")
```

### PII Filtering

```python
# Configure log redaction
structlog.configure(
    processors=[
        structlog.processors.add_log_level,
        # Redact sensitive fields
        structlog.processors.EventRenamer("event"),
    ]
)
```

### Enforcement

- Code review checks for security event logging
- Monitoring alerts on auth failure spikes

---

## A10:2021 - Server-Side Request Forgery (SSRF)

**Risk**: Server makes requests to unintended destinations.

### Requirements

- [ ] URL validation for user-supplied URLs
- [ ] Allowlist for external service calls
- [ ] No internal network access from user input

### Implementation

```python
from urllib.parse import urlparse

ALLOWED_HOSTS = {"api.stripe.com", "api.sendgrid.com"}

def validate_url(url: str) -> bool:
    parsed = urlparse(url)
    if parsed.scheme not in ("https",):
        return False
    if parsed.hostname not in ALLOWED_HOSTS:
        return False
    return True
```

### Enforcement

- Linter flags URL construction from user input
- Network policies restrict outbound connections

---

## Compliance Matrix

| Vulnerability | Gate 1 (Pre-commit) | Gate 2 (CI) | Gate 3 (Deploy) |
|---------------|---------------------|-------------|-----------------|
| A01 Access Control | - | Unit tests | Integration tests |
| A02 Crypto Failures | Secrets scan | Security scan | - |
| A03 Injection | Linter rules | Security scan | - |
| A04 Insecure Design | - | ADR review | - |
| A05 Misconfig | Secrets scan | Config validation | Header check |
| A06 Vulnerable Deps | - | Dependency scan | Container scan |
| A07 Auth Failures | - | Unit tests | - |
| A08 Integrity | Lock files | Branch protection | Checksum verify |
| A09 Logging | - | Code review | Log verification |
| A10 SSRF | Linter flags | - | Network policies |
