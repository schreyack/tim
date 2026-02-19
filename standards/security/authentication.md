# Authentication Standard

This document defines authentication requirements for all TIM projects.

## Overview

All TIM applications must implement secure authentication. This standard specifies JWT-based authentication as the primary mechanism.

## Token Strategy

### JWT (JSON Web Tokens)

All TIM applications use JWT for stateless authentication.

**Required Claims:**

| Claim | Description | Example |
|-------|-------------|---------|
| `sub` | Subject (user identifier) | `user-123` or UUID |
| `iat` | Issued at timestamp | Unix timestamp |
| `exp` | Expiration timestamp | Unix timestamp |

**Optional Claims:**

| Claim | Description |
|-------|-------------|
| `aud` | Audience (API identifier) |
| `iss` | Issuer (service name) |
| `roles` | User roles array |

### Token Lifetimes

| Token Type | Default Lifetime | Maximum |
|------------|-----------------|---------|
| Access Token | 30 minutes | 1 hour |
| Refresh Token | 7 days | 30 days |

Access tokens MUST be short-lived. Refresh tokens provide session continuity.

## Secret Management

### JWT Secret Requirements

- **Minimum length**: 32 characters
- **Entropy**: Cryptographically random
- **Storage**: Environment variables only
- **Rotation**: Quarterly or on suspected compromise

```bash
# Generate secure JWT secret
openssl rand -base64 32
```

### Configuration

**Python (Pydantic Settings):**

```python
class Settings(BaseSettings):
    jwt_secret: str = Field(..., min_length=32)
    jwt_expiry_minutes: int = Field(default=30, ge=5, le=60)
```

**Node.js (Zod):**

```typescript
const configSchema = z.object({
  jwtSecret: z.string().min(32),
  jwtExpiryMinutes: z.number().int().min(5).max(60).default(30),
});
```

## Password Requirements

### Hashing

- **Algorithm**: bcrypt (preferred) or Argon2
- **Cost factor**: 12 rounds minimum
- **Never**: MD5, SHA1, or plain SHA256

**Python:**

```python
import bcrypt

SALT_ROUNDS = 12

def hash_password(password: str) -> str:
    return bcrypt.hashpw(
        password.encode(),
        bcrypt.gensalt(rounds=SALT_ROUNDS)
    ).decode()

def verify_password(password: str, hashed: str) -> bool:
    return bcrypt.checkpw(password.encode(), hashed.encode())
```

**Node.js:**

```typescript
import bcrypt from "bcrypt";

const SALT_ROUNDS = 12;

async function hashPassword(password: string): Promise<string> {
  return bcrypt.hash(password, SALT_ROUNDS);
}

async function verifyPassword(password: string, hash: string): Promise<boolean> {
  return bcrypt.compare(password, hash);
}
```

### Password Policy

| Requirement | Minimum |
|-------------|---------|
| Length | 8 characters |
| Complexity | Not required (length > complexity) |
| Breached check | Recommended (HaveIBeenPwned API) |

## Token Verification

### Required Checks

1. **Signature verification** - Token not tampered
2. **Expiration check** - Token not expired
3. **Issuer validation** - If `iss` claim used

### Error Handling

Return consistent error responses for authentication failures.

**Python:**

```python
class AuthenticationError(Exception):
    def __init__(self, detail: str = "Authentication failed"):
        self.detail = detail
        super().__init__(detail)

def verify_token(token: str) -> str:
    try:
        payload = jwt.decode(token, settings.jwt_secret, algorithms=["HS256"])
        return payload["sub"]
    except jwt.ExpiredSignatureError:
        raise AuthenticationError("Token has expired")
    except jwt.InvalidTokenError:
        raise AuthenticationError("Invalid token")
```

**Node.js:**

```typescript
class AuthenticationError extends Error {
  constructor(message = "Authentication failed") {
    super(message);
    this.name = "AuthenticationError";
  }
}

function verifyToken(token: string): string {
  try {
    const payload = jwt.verify(token, config.jwtSecret) as TokenPayload;
    return payload.sub;
  } catch (error) {
    if (error instanceof jwt.TokenExpiredError) {
      throw new AuthenticationError("Token has expired");
    }
    throw new AuthenticationError("Invalid token");
  }
}
```

## API Response Format

### Success Response

```json
{
  "access_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "token_type": "bearer"
}
```

### Error Response

```json
{
  "detail": "Invalid email or password"
}
```

**Never reveal** whether email exists. Use generic "Invalid credentials" message.

## HTTP Security

### Token Transmission

- **Header**: `Authorization: Bearer <token>`
- **Never**: Query parameters, cookies without proper flags

### Response Headers

Authentication endpoints MUST include:

- `X-Content-Type-Options: nosniff`
- `Cache-Control: no-store`

## Rate Limiting

Protect authentication endpoints from brute force attacks.

| Endpoint | Limit | Window |
|----------|-------|--------|
| Login | 5 attempts | 15 minutes |
| Password reset | 3 attempts | 1 hour |

## Session Management

### Logout

Clients discard tokens locally. For server-side invalidation:

- Token blacklist (Redis)
- Short token lifetime + refresh rotation

### Token Refresh

1. Client sends refresh token
2. Server validates refresh token
3. Server issues new access token
4. Optionally rotate refresh token

## Testing Requirements

Authentication must be tested at unit and integration levels.

**Required Test Cases:**

- Valid credentials return token
- Invalid credentials return 401
- Expired token returns 401
- Tampered token returns 401
- Missing token returns 401
- Rate limiting enforced

## Dependencies

### Python

```toml
[project.dependencies]
bcrypt = "^4.1"
PyJWT = "^2.8"
```

### Node.js

```json
{
  "dependencies": {
    "bcrypt": "^5.1",
    "jsonwebtoken": "^9.0"
  }
}
```

## See Also

- [Security Headers](headers.md)
- [Secrets Management](secrets.md)
- [OWASP Checklist](owasp-checklist.md)
