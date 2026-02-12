# TIM Remote-First Deployment Policy

All TIM projects operate on a **remote-first deployment model**. This document defines the policy, rationale, and enforcement mechanisms.

## Policy Statement

**Remote by default. All standard environments (dev, uat, prod) run on remote servers.**

Local development is available as an **opt-in option** that requires explicit human approval. AI developers cannot enable local development.

## Rationale

### 1. Environment Parity

Local environments inevitably drift from production:

- Different OS versions
- Different resource constraints
- Missing services (Redis, message queues)
- Different network configurations

Remote-only ensures all environments behave identically.

### 2. Security Enforcement

ops.sh safety tiers cannot be enforced on local machines:

- Developers could bypass restrictions
- No audit trail for local operations
- Secrets could leak to local storage

Remote-only ensures all operations are logged and controlled.

### 3. AI Development Safety

TIM develops exclusively with AI. AI developers:

- Cannot distinguish "safe" local operations from "dangerous" ones
- Will take shortcuts if shortcuts are available
- Need hard boundaries, not guidelines

Remote-only removes the temptation entirely.

### 4. Reproducibility

"It works on my machine" is not acceptable:

- All testing happens in controlled environments
- All deployments follow identical procedures
- All debugging happens with production-like data

## What This Means

### NO Local Docker

```bash
# PROHIBITED - No local docker-compose
docker-compose up -d        # NO
docker run -p 8080:8080 ... # NO

# REQUIRED - Use ops.sh with environment
./ops.sh --env dev deploy   # YES
./ops.sh --env dev logs     # YES
```

### NO Local Databases

```bash
# PROHIBITED - No local PostgreSQL/MySQL
psql -h localhost ...       # NO
mysql -h 127.0.0.1 ...      # NO

# REQUIRED - Database on remote
./ops.sh --env dev db:migrate  # YES
./ops.sh --env dev shell       # Then use psql inside container
```

### NO Direct SSH

```bash
# PROHIBITED - No direct SSH to servers
ssh user@server             # NO
scp file user@server:       # NO

# REQUIRED - Use ops.sh
./ops.sh --env dev shell    # YES (for dev)
./ops.sh --env dev logs     # YES
```

### Local Development Workflow

Developers write code locally, but test remotely:

1. **Write code** on local machine (IDE, git)
2. **Push to branch** triggers CI (Gate 2)
3. **Deploy to dev** via `./ops.sh --env dev deploy`
4. **Test on dev** via browser/API calls to dev environment
5. **Debug** via `./ops.sh --env dev logs` and `./ops.sh --env dev shell`
6. **Iterate** - repeat steps 1-5

### What IS Allowed Locally

| Activity | Allowed | Tool |
|----------|---------|------|
| Writing code | Yes | IDE/editor |
| Running linters | Yes | Pre-commit hooks |
| Running type checkers | Yes | mypy/tsc |
| Running unit tests (no I/O) | Yes | pytest/jest |
| Git operations | Yes | git CLI |
| Editing environments.yaml | Yes | Editor |
| Running ops.sh commands | Yes | ops.sh |

### What IS NOT Allowed Locally

| Activity | Allowed | Why |
|----------|---------|-----|
| Running Docker containers | No | Use remote dev |
| Running databases | No | Use remote dev |
| Integration tests | No | Require real services |
| E2E tests | No | Require deployed app |
| SSH to servers directly | No | Use ops.sh |

## Three Required Environments

Every TIM project must have exactly three remote environments:

### DEV (Development)

- **Purpose:** Rapid iteration and testing
- **Access:** All developers
- **Restrictions:** Minimal (sandbox only)
- **Data:** Test/synthetic data
- **Stability:** Can be broken, will be fixed

### UAT (User Acceptance Testing)

- **Purpose:** Stakeholder review and QA
- **Access:** QA team, tech leads
- **Restrictions:** Moderate
- **Data:** Anonymized production-like data
- **Stability:** Should be stable for testing

### PROD (Production)

- **Purpose:** Live user traffic
- **Access:** DevOps/SRE only
- **Restrictions:** Maximum
- **Data:** Real user data
- **Stability:** Must be stable, always

## Enforcement Mechanisms

### 1. No Local Configuration

ops-config.yaml does not support `environment: local`:

```yaml
# INVALID - will fail validation
environment: "local"  # ERROR: 'local' is not a valid environment

# VALID
environment: "dev"    # Must be dev, uat, or prod
```

### 2. Required --env Flag

ops.sh requires explicit environment specification:

```bash
./ops.sh deploy
# ERROR: --env flag required. Use --env dev, --env uat, or --env prod

./ops.sh --env dev deploy
# OK: Deploying to dev environment
```

### 3. Pre-commit Hook

Block commits that add Docker Compose for local use:

```yaml
# .pre-commit-config.yaml
- repo: local
  hooks:
    - id: no-local-docker
      name: Block local docker-compose
      entry: bash -c 'if grep -r "localhost" docker-compose*.yml 2>/dev/null; then echo "ERROR: No local docker configurations allowed"; exit 1; fi'
      language: system
```

### 4. CI Validation

CI pipeline validates remote-only compliance:

```yaml
# .github/workflows/ci.yml
validate-remote-only:
  runs-on: ubuntu-latest
  steps:
    - name: Check for local configurations
      run: |
        # Fail if docker-compose files have localhost
        if grep -r "localhost" docker-compose*.yml 2>/dev/null; then
          echo "ERROR: Local docker configurations not allowed"
          exit 1
        fi

        # Fail if .env has local database URLs
        if grep -r "localhost" .env.example 2>/dev/null | grep -i "database"; then
          echo "ERROR: Local database URLs not allowed"
          exit 1
        fi
```

## Migration Path

For existing projects with local development:

### Phase 1: Set Up Remote Dev

1. Provision dev server (same spec as prod but smaller)
2. Configure `environments.yaml` with dev environment
3. Deploy current code to dev: `./ops.sh --env dev deploy`

### Phase 2: Migrate Developers

1. Remove local docker-compose files
2. Update onboarding docs
3. Train team on `./ops.sh --env dev` workflow
4. Monitor for `localhost` in commits (block at CI)

### Phase 3: Remove Local Support

1. Add pre-commit hooks blocking local configs
2. Update CLAUDE.md with remote-only instructions
3. Archive local development documentation

## Optional: Human-Enabled Local Development

While TIM defaults to remote-only, local development can be enabled for specific projects by a human.

### Why Allow Local Dev?

Sometimes local development is appropriate:

- Rapid iteration during feature development
- Debugging complex issues with local tools
- Working with limited or no network access
- Personal preference for certain workflows

### The Approval Requirement

Local development is **disabled by default** and requires explicit human approval:

```bash
# A human must run this (AI cannot):
tim-local-dev-enable --project /path/to/project

# Check status
tim-local-dev-enable --check --project /path/to/project

# Revoke access
tim-local-dev-enable --revoke --project /path/to/project

# List all enabled projects
tim-local-dev-enable --list
```

### AI Bypass Prevention

The `tim-local-dev-enable` tool has multiple layers to prevent AI from enabling local dev:

1. **Interactive terminal check** - Requires stdin attached to a terminal
2. **Environment variable detection** - Blocks if CLAUDE_CODE_SESSION or TIM_LOOP_SESSION_ID is set
3. **Process tree inspection** - Walks up process hierarchy looking for claude-related processes
4. **No --approver flag** - Requires interactive email prompt

### What Changes Once Approved

Once local dev is enabled for a project:

| Aspect | Before Approval | After Approval |
|--------|-----------------|----------------|
| `--env local` | Blocked with error | Allowed |
| All commands | N/A | SAFE tier (no restrictions) |
| Docker access | N/A | Direct (not via SSH) |
| File sync | N/A | Not needed (already local) |

### Local Environment Workflow

```bash
# After enabling local dev:
./ops.sh --env local deploy      # Build and start containers locally
./ops.sh --env local status      # Check local container status
./ops.sh --env local logs        # View local container logs
./ops.sh --env local shell       # Open shell in local container
./ops.sh --env local db:migrate  # Run migrations on local database
```

### Local Docker Compose File

Local development uses `docker-compose.local.yml` by default, falling back to `docker-compose.yml` if not present.

You can customize this in `environments.yaml`:

```yaml
environments:
  local:
    remote:
      compose_file: "docker-compose.local.yml"
```

### Audit Logging

All local operations are logged to `~/.tim-ops/local-dev-audit.log` for accountability:

```text
2025-01-19T10:30:00Z | user | myproject | LOCAL | deploy | STARTED | 0s
2025-01-19T10:30:45Z | user | myproject | LOCAL | deploy | SUCCESS | 45s
```

### When to Use Local vs Remote Dev

| Use Local When | Use Remote Dev When |
|----------------|---------------------|
| Rapid iteration on features | Testing environment parity |
| Debugging with local tools | Team collaboration |
| Limited network access | CI/CD pipeline integration |
| Personal preference | Pre-production validation |

### Revoking Access

If local dev is no longer needed or appropriate:

```bash
tim-local-dev-enable --revoke --project /path/to/project
```

After revocation, `./ops.sh --env local` will fail with instructions on how to re-enable.

## FAQ

### Q: What about offline development?

A: TIM projects require network access. If offline, you can:

- Write code (no execution)
- Run linters and type checkers
- Write tests (no execution)
- Commit changes (push when online)

### Q: What about slow network connections?

A: Dev environments are optimized for low-latency development:

- Deploy only changed files (rsync delta)
- Persistent SSH connections
- Log streaming with buffering

### Q: What about cost?

A: Remote dev is cheaper than you think:

- Single small server for all developers
- Shared resources (database, Redis)
- Auto-shutdown during off-hours (optional)

Estimated cost: $20-50/month for small team.

### Q: What about local testing?

A: Local testing is allowed for:

- Unit tests (no I/O, mocked dependencies)
- Linting and type checking
- Static analysis

Integration and E2E tests run on remote dev or UAT.

## Compliance Checklist

- [ ] No `docker-compose.yml` with `localhost` (unless `docker-compose.local.yml`)
- [ ] No `.env` with local database URLs
- [ ] `environments.yaml` defines dev, uat, prod (local is optional)
- [ ] ops.sh requires `--env` flag
- [ ] CI validates remote-first compliance
- [ ] `docker-compose.local.yml` is gitignored (if present)
- [ ] Developer onboarding uses remote dev by default
- [ ] CLAUDE.md documents remote-first workflow
- [ ] `tim-local-dev-enable` is available in PATH for human opt-in
