# Secrets Management Standard

Secrets are the keys to your kingdom. A leaked API key, database password, or JWT secret can lead to complete system compromise. This standard defines how TIM projects must handle secrets.

**Philosophy**: Secrets should never exist in code. Ever. Not even "just for testing."

## What Counts as a Secret

| Type | Examples | Risk Level |
|------|----------|------------|
| API keys | Stripe, SendGrid, AWS | CRITICAL |
| Database credentials | PostgreSQL password, connection strings | CRITICAL |
| JWT/Session secrets | Signing keys, encryption keys | CRITICAL |
| OAuth credentials | Client ID/secret pairs | HIGH |
| Service accounts | GCP service account JSON | CRITICAL |
| SSH keys | Deploy keys, server access | CRITICAL |
| Encryption keys | Data-at-rest encryption | CRITICAL |
| Internal API tokens | Service-to-service auth | HIGH |

## Hard Rules (No Exceptions)

### 1. Never in Code

```python
# BLOCKED: Hardcoded secrets
API_KEY = "sk_live_abc123"  # Pre-commit will catch this

# BLOCKED: Default values that look like secrets
API_KEY = os.getenv("API_KEY", "sk_test_default")  # No default secrets

# ALLOWED: Fail if not set
API_KEY = os.environ["API_KEY"]  # Raises KeyError if missing

# ALLOWED: Pydantic Settings (recommended)
class Settings(BaseSettings):
    api_key: str  # Required, no default

settings = Settings()  # Fails if API_KEY env var missing
```

### 2. Never in Git History

Once a secret enters git history, consider it compromised. Even if you remove it in a later commit, it's in the history forever.

```bash
# If you accidentally commit a secret:
1. Rotate the secret IMMEDIATELY (get a new one)
2. Revoke the old secret
3. Only then worry about cleaning git history
```

### 3. Never in Logs

```python
# BLOCKED: Logging secrets
logger.info(f"Connecting with password: {password}")
logger.debug(f"Request headers: {request.headers}")  # May contain auth

# ALLOWED: Structured logging with redaction
logger = structlog.get_logger()
logger.info("connecting_to_db", host=host, user=user)  # No password
```

### 4. Never in Error Messages

```python
# BLOCKED: Secrets in exceptions
raise ValueError(f"Invalid API key: {api_key}")

# ALLOWED: Masked values
raise ValueError(f"Invalid API key: {api_key[:4]}...{api_key[-4:]}")
# Or just:
raise ValueError("Invalid API key")
```

## Environment Variables

The foundation of secrets management. All secrets come from environment variables.

### Configuration Pattern (Python)

```python
# config.py
from pydantic_settings import BaseSettings

class Settings(BaseSettings):
    # Required secrets (no defaults)
    database_url: str
    jwt_secret: str
    stripe_secret_key: str

    # Optional secrets (for features that may not be enabled)
    sendgrid_api_key: str | None = None
    slack_webhook_url: str | None = None

    class Config:
        env_file = ".env"
        env_file_encoding = "utf-8"
        case_sensitive = False

settings = Settings()
```

### Configuration Pattern (TypeScript)

```typescript
// config.ts
import { z } from "zod";

const envSchema = z.object({
  DATABASE_URL: z.string().min(1),
  JWT_SECRET: z.string().min(32),
  STRIPE_SECRET_KEY: z.string().startsWith("sk_"),

  // Optional
  SENDGRID_API_KEY: z.string().optional(),
  SLACK_WEBHOOK_URL: z.string().url().optional(),
});

const parsed = envSchema.safeParse(process.env);

if (!parsed.success) {
  console.error("Invalid environment variables:", parsed.error.format());
  process.exit(1);
}

export const config = parsed.data;
```

## .env File Management

### Local Development

```bash
# .env (local development only)
DATABASE_URL=postgresql://user:password@localhost:5432/myapp_dev
JWT_SECRET=local-development-secret-min-32-chars
STRIPE_SECRET_KEY=sk_test_...

# Generate strong secrets for local dev:
openssl rand -base64 32
```

### .env.example (Commit This)

```bash
# .env.example - Template showing required variables
# Copy to .env and fill in real values

# Required
DATABASE_URL=postgresql://user:password@host:5432/database
JWT_SECRET=generate-with-openssl-rand-base64-32
STRIPE_SECRET_KEY=sk_test_your_stripe_key

# Optional
SENDGRID_API_KEY=
SLACK_WEBHOOK_URL=
```

### .gitignore (Mandatory)

```gitignore
# Environment files with secrets
.env
.env.local
.env.*.local
.env.production
.env.staging

# Exception: example file is safe
!.env.example
```

## Server-Side Secrets

### Docker Compose

```yaml
# docker-compose.yml
services:
  app:
    environment:
      - DATABASE_URL=${DATABASE_URL}
      - JWT_SECRET=${JWT_SECRET}
    env_file:
      - .env  # Load from .env on host
```

### Production Servers

For self-hosted production:

```bash
# /home/deploy/apps/myapp/.env
# Permissions: 600 (owner read/write only)
# Owner: deploy user

DATABASE_URL=postgresql://prod_user:strong_password@db:5432/prod_db
JWT_SECRET=production-secret-rotated-quarterly
STRIPE_SECRET_KEY=sk_live_...
```

**Security requirements:**
- File permissions: `chmod 600 .env`
- Owned by deploy user, not root
- Made immutable after setup: `sudo chattr +i .env`
- Backed up separately from code

## Secret Rotation

### Rotation Schedule

| Secret Type | Rotation Frequency | Process |
|-------------|-------------------|---------|
| JWT secrets | Quarterly | Dual-key rollover |
| API keys | Annually or on compromise | Regenerate + update |
| Database passwords | Quarterly | Coordinated update |
| Service accounts | Annually | Regenerate credentials |

### Dual-Key Rollover (Zero Downtime)

For secrets that can't be rotated instantly (like JWT secrets):

```python
# config.py
class Settings(BaseSettings):
    # Primary secret (current)
    jwt_secret: str
    # Previous secret (for validation during rollover)
    jwt_secret_previous: str | None = None

# auth.py
def verify_token(token: str) -> dict:
    # Try current secret first
    try:
        return jwt.decode(token, settings.jwt_secret, algorithms=["HS256"])
    except jwt.InvalidSignatureError:
        # If current fails, try previous (during rollover period)
        if settings.jwt_secret_previous:
            return jwt.decode(token, settings.jwt_secret_previous, algorithms=["HS256"])
        raise
```

**Rollover process:**
1. Generate new secret
2. Add current secret as `jwt_secret_previous`
3. Set new secret as `jwt_secret`
4. Deploy
5. Wait for all old tokens to expire (or force re-login)
6. Remove `jwt_secret_previous`

## Emergency Procedures

### When a Secret is Compromised

**Immediate actions (within 15 minutes):**

1. **Revoke the compromised secret**
   - API keys: Regenerate in provider dashboard
   - Database: Change password immediately
   - JWT: Rotate to new secret

2. **Deploy new secret**
   ```bash
   # Update .env on production server
   ssh deploy@prod "cd /app && vim .env"
   # Restart services
   ./ops.sh restart --confirm
   ```

3. **Invalidate sessions (for auth secrets)**
   - Force logout all users
   - Clear session store

4. **Assess impact**
   - Check logs for unauthorized access
   - Review what data could have been accessed

**Post-incident (within 24 hours):**

1. **Root cause analysis**
   - How was the secret exposed?
   - Git history? Logs? Phishing?

2. **Documentation**
   - Timeline of events
   - Actions taken
   - Prevention measures

3. **Prevention**
   - Add detection if missing
   - Update processes

### Secret Compromise Checklist

```markdown
## Secret Compromise Response

Date: _______________
Secret Type: _______________
How Discovered: _______________

### Immediate (15 min)
- [ ] Secret revoked/rotated
- [ ] New secret deployed
- [ ] Sessions invalidated (if auth-related)
- [ ] Team notified

### Assessment (1 hour)
- [ ] Logs reviewed for unauthorized access
- [ ] Scope of potential exposure determined
- [ ] Customers notified (if data breach)

### Post-Incident (24 hours)
- [ ] Root cause identified
- [ ] Prevention measures implemented
- [ ] Incident documented
```

## Pre-commit Detection

### Python Projects

```yaml
# .pre-commit-config.yaml
repos:
  - repo: https://github.com/Yelp/detect-secrets
    rev: v1.5.0
    hooks:
      - id: detect-secrets
        args: [--baseline, .secrets.baseline]
        exclude: package-lock\.json|poetry\.lock
```

Setup baseline:
```bash
# Initial baseline (marks existing non-secrets)
detect-secrets scan > .secrets.baseline

# Update baseline after adding intentional patterns
detect-secrets scan --baseline .secrets.baseline
```

### Node.js Projects

```yaml
# .pre-commit-config.yaml
repos:
  - repo: https://github.com/gitleaks/gitleaks
    rev: v8.21.2
    hooks:
      - id: gitleaks
```

### Custom Patterns

```yaml
# .gitleaks.toml
[[rules]]
description = "TIM Internal API Token"
regex = '''tim_api_[a-zA-Z0-9]{32}'''
tags = ["api", "tim"]

[[rules]]
description = "Internal JWT Secret"
regex = '''TIM_JWT_SECRET=.+'''
tags = ["jwt", "tim"]
```

## CI/CD Integration

```yaml
# .github/workflows/security.yml
name: Security Scan

on: [push, pull_request]

jobs:
  secrets-scan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0  # Full history for deep scan

      - name: Scan for secrets
        uses: gitleaks/gitleaks-action@v2
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}

      - name: TruffleHog deep scan
        uses: trufflesecurity/trufflehog@main
        with:
          extra_args: --only-verified
```

## Future: Secrets Manager Migration

When moving to cloud, transition to a secrets manager:

### Recommended Solutions

| Environment | Solution | Notes |
|-------------|----------|-------|
| AWS | AWS Secrets Manager | Native integration, automatic rotation |
| GCP | Google Secret Manager | Native, versioned secrets |
| Self-hosted | HashiCorp Vault | Industry standard, complex setup |
| Simple | Doppler | Easy migration from .env |

### Migration Path

1. **Start**: .env files (current)
2. **Growth**: Doppler or similar (easy migration)
3. **Scale**: Cloud-native secrets manager

### Doppler Example (Future)

```bash
# Install CLI
brew install dopplerhq/cli/doppler

# Login and setup
doppler login
doppler setup

# Run app with secrets injected
doppler run -- python main.py

# In CI
doppler run -- npm test
```

## Enforcement

| Check | Gate | Action |
|-------|------|--------|
| Secrets in code | Pre-commit | Block commit |
| Secrets in git history | CI (trufflehog) | Block merge |
| .env tracked in git | Pre-commit | Block commit |
| Missing .env.example | CI | Warning |
| Weak secret patterns | CI | Warning |

## Checklist for New Projects

- [ ] `.env` added to `.gitignore`
- [ ] `.env.example` created with all variables
- [ ] Pydantic Settings / Zod config in place
- [ ] No default values for required secrets
- [ ] `detect-secrets` or `gitleaks` in pre-commit
- [ ] CI secret scanning enabled
- [ ] Production `.env` with correct permissions (600)
- [ ] Secrets rotation schedule documented
