# CI/CD Integration Standard

This document explains how CI/CD pipelines integrate with the TIM four-gate model and ops.sh deployment system.

**CRITICAL**: All deployments are remote-only. There are no local environments. See `standards/deployment/remote-only.md` for the policy.

## Overview

```text
┌─────────────────────────────────────────────────────────────────────────────┐
│                        CI/CD + OPS.SH INTEGRATION                            │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  Developer                                                                   │
│      │                                                                       │
│      ▼                                                                       │
│  ┌──────────────────┐                                                       │
│  │ GATE 1: LOCAL    │◄─── Pre-commit hooks (runs locally)                   │
│  │ - Type check     │     Can bypass with --no-verify                       │
│  │ - Lint           │     (but CI will catch it)                            │
│  │ - Format         │                                                       │
│  │ - Secrets scan   │                                                       │
│  └────────┬─────────┘                                                       │
│           │                                                                  │
│           ▼                                                                  │
│  ┌──────────────────┐                                                       │
│  │ git push         │                                                       │
│  └────────┬─────────┘                                                       │
│           │                                                                  │
│           ▼                                                                  │
│  ┌──────────────────────────────────────────────────────────────┐           │
│  │ GATE 2: CI PIPELINE (GitHub Actions)                         │           │
│  │                                                               │           │
│  │  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐         │           │
│  │  │Typecheck│  │  Lint   │  │  Test   │  │Security │         │           │
│  │  │(mypy/   │  │(ruff/   │  │(pytest/ │  │(bandit/ │         │           │
│  │  │ tsc)    │  │eslint)  │  │ vitest) │  │npm audit│         │           │
│  │  └────┬────┘  └────┬────┘  └────┬────┘  └────┬────┘         │           │
│  │       │            │            │            │                │           │
│  │       └────────────┴────────────┴────────────┘                │           │
│  │                        │                                      │           │
│  │                        ▼                                      │           │
│  │              ┌──────────────────┐                            │           │
│  │              │ ALL MUST PASS    │                            │           │
│  │              │ to merge PR      │                            │           │
│  │              └────────┬─────────┘                            │           │
│  └───────────────────────┼──────────────────────────────────────┘           │
│                          │                                                   │
│                          ▼                                                   │
│                 ┌──────────────────┐                                        │
│                 │ PR Merged to     │                                        │
│                 │ main branch      │                                        │
│                 └────────┬─────────┘                                        │
│                          │                                                   │
│                          ▼                                                   │
│  ┌──────────────────────────────────────────────────────────────┐           │
│  │ GATE 3: DEPLOYMENT (CI triggers ops.sh)                      │           │
│  │                                                               │           │
│  │  ┌─────────────────────────────────────────────────────┐     │           │
│  │  │ ArgoCD syncs from git → k8s cluster                   │     │           │
│  │  │                                                      │     │           │
│  │  │  1. GHA builds container image                      │     │           │
│  │  │  2. ArgoCD detects manifest/image change            │     │           │
│  │  │  3. Canary rollout (Argo Rollouts, 10%)             │     │           │
│  │  │  4. Health checks                                   │     │           │
│  │  │  5. Full rollout or auto-rollback                   │     │           │
│  │  │                                                      │     │           │
│  │  └─────────────────────────────────────────────────────┘     │           │
│  └──────────────────────────────────────────────────────────────┘           │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Why Both CI and ops.sh?

| Component | Purpose | When It Runs |
|-----------|---------|--------------|
| CI Pipeline | Automated quality gates | On every push/PR |
| ops.sh | Deployment execution | When deploying |

**CI ensures code quality before it can be merged.**
**ops.sh handles the actual deployment safely.**

They're complementary:

- CI blocks bad code from entering `main`
- ops.sh deploys good code from `main` to production

## Pipeline Templates

### Python Projects

Copy `templates/ci/python-ci.yml` to `.github/workflows/ci.yml`:

```yaml
# Runs automatically on every push and PR
name: CI

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main, develop]

jobs:
  typecheck:   # mypy --strict
  lint:        # ruff check + format
  test:        # pytest with coverage reporting
  security:    # bandit + safety
  secrets:     # trufflehog
  container:   # trivy (if Dockerfile exists)
```

### Node.js Projects

Copy `templates/ci/node-ci.yml` to `.github/workflows/ci.yml`:

```yaml
# Runs automatically on every push and PR
name: CI

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main, develop]

jobs:
  typecheck:   # tsc --noEmit
  lint:        # eslint + prettier
  test:        # vitest with coverage reporting
  security:    # npm audit + snyk
  secrets:     # gitleaks + trufflehog
  build:       # verify build works
  container:   # trivy (if Dockerfile exists)
```

## Branch Protection

Enable these branch protection rules on `main`:

```yaml
# Settings > Branches > Branch protection rules

Branch name pattern: main

Rules:
  ✓ Require a pull request before merging
    ✓ Require approvals: 1
    ✓ Dismiss stale PR approvals when new commits are pushed

  ✓ Require status checks to pass before merging
    ✓ Require branches to be up to date
    Required checks:
      - typecheck
      - lint
      - test
      - security
      - secrets
      - gate2-complete

  ✓ Do not allow bypassing the above settings
```

## Deployment Integration

### Deployment Model

Deployments are handled by ArgoCD, not ops.sh. The workflow:

1. **GHA builds** container image on push/merge
2. **ArgoCD detects** manifest or image changes in the infra repo
3. **ArgoCD syncs** the k8s cluster automatically

ops.sh is for operational commands only (logs, status, shell, db operations).

```bash
# Operational commands via alias - ALWAYS specify --env
myapp --env dev status
myapp --env dev logs backend
myapp --env prod health
```

### GitHub Secrets Required

Add these to repository Settings > Secrets and variables > Actions:

| Secret | Description |
|--------|-------------|
| `GHCR_TOKEN` | GitHub Container Registry token for image push |
| `SNYK_TOKEN` | (Optional) Snyk API token for security scanning |

### Environment Protection

Create a `production` environment in Settings > Environments:

```yaml
Environment: production
Protection rules:
  ✓ Required reviewers: [your-username]
  ✓ Wait timer: 0 minutes (or add delay for canary observation)
```

## Workflow

### Day-to-Day Development

```text
1. Create feature branch from main
2. Write code (Gate 1 pre-commit runs locally)
3. Push branch (Gate 2 CI runs automatically)
4. CI fails? Fix issues, push again
5. CI passes? Create PR
6. Get review + approval
7. Merge to main
8. ArgoCD deploys automatically on merge
```

### When CI Fails

```bash
# View failed workflow in GitHub Actions tab
# Click on the failed job to see logs

# Common fixes:
# Type errors → Fix code, push again
# Lint errors → Run `ruff check --fix` or `npm run lint:fix`
# Test failures → Fix tests, push again
# Security issues → Update vulnerable dependencies
# Secrets detected → Remove secret, rotate it immediately
```

## Self-Hosted Runners (Optional)

For faster builds or private network access:

```yaml
# Add self-hosted runner
jobs:
  test:
    runs-on: self-hosted  # Instead of ubuntu-latest
```

Setup:

1. Settings > Actions > Runners > New self-hosted runner
2. Follow instructions to install runner on your server
3. Runner auto-connects and picks up jobs

## Comparison: CI vs Local vs ops.sh

| Check | Gate 1 (Local) | Gate 2 (CI) | Gate 3 (ops.sh) |
|-------|----------------|-------------|-----------------|
| Type check | Pre-commit hook | CI job | - |
| Lint | Pre-commit hook | CI job | - |
| Format | Pre-commit hook | CI job | - |
| Secrets scan | Pre-commit hook | CI job (deep) | - |
| Unit tests | - | CI job | - |
| Coverage | - | CI job (reported) | - |
| Security scan | - | CI job | - |
| Container scan | - | CI job | - |
| Security verify | - | - | ops.sh verify |
| Deploy | - | - | ArgoCD (automatic) |
| Health check | - | - | ops.sh health |
| Canary | - | - | Argo Rollouts |
| Rollback | - | - | ops.sh rollback |

## Remote-First Validation

CI should validate the remote-first policy while allowing opt-in local development:

```yaml
validate-remote-policy:
  name: Validate Remote-First Policy
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@v4

    - name: Verify ops-config.yaml exists
      run: |
        if [[ ! -f ops-config.yaml ]]; then
          echo "ERROR: ops-config.yaml required"
          exit 1
        fi
        echo "OK: ops-config.yaml exists"

    - name: Check for local database URLs
      run: |
        # Fail if .env.example has local database URLs
        if grep -r "localhost" .env.example 2>/dev/null | grep -i "database"; then
          echo "ERROR: Local database URLs not allowed in .env.example"
          exit 1
        fi
        echo "OK: No localhost database URLs in .env.example"

    - name: Verify no stale docker-compose references
      run: |
        if [[ -f docker-compose.yml ]] || [[ -f docker-compose.prod.yml ]]; then
          echo "WARNING: docker-compose files found - deployment uses k8s/ArgoCD"
        fi
        echo "OK: Stale reference check complete"
```

---

## Checklist for New Projects

- [ ] Copy appropriate CI workflow to `.github/workflows/ci.yml`
- [ ] Configure branch protection on `main`
- [ ] Add `GHCR_TOKEN` secret (for container image push)
- [ ] Create `production` environment with protection rules
- [ ] Test workflow by creating a PR
- [ ] Verify all checks pass before first production deploy
- [ ] Create `ops-config.yaml` with namespace and alias
- [ ] Add k8s manifests to infra repo
- [ ] Configure ArgoCD Application for the service
