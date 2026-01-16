# CI/CD Integration Standard

This document explains how CI/CD pipelines integrate with the TIM three-gate model and ops.sh deployment system.

## Overview

```
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
│  │  │ ops.sh deploy --environment production --confirm     │     │           │
│  │  │                                                      │     │           │
│  │  │  1. Security verification (verify-ops-security.sh)  │     │           │
│  │  │  2. Sync files to remote                            │     │           │
│  │  │  3. Build containers                                │     │           │
│  │  │  4. Canary deployment (10%)                         │     │           │
│  │  │  5. Health checks                                   │     │           │
│  │  │  6. Full rollout or auto-rollback                   │     │           │
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
  test:        # pytest with 90% coverage
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
  test:        # vitest with 90% coverage
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

### Manual Deployment (Recommended Initially)

After CI passes and PR is merged:

```bash
# From local machine
./ops.sh deploy --environment production --confirm
```

### Automated Deployment

Uncomment the deploy job in the CI workflow:

```yaml
deploy:
  name: Deploy to Production
  needs: [gate2-complete]
  runs-on: ubuntu-latest
  if: github.ref == 'refs/heads/main' && github.event_name == 'push'
  environment: production  # Requires manual approval in GitHub
  steps:
    - uses: actions/checkout@v4

    - name: Setup SSH key
      uses: webfactory/ssh-agent@v0.9.0
      with:
        ssh-private-key: ${{ secrets.DEPLOY_SSH_KEY }}

    - name: Deploy via ops.sh
      run: ./ops.sh deploy --environment production --confirm

    - name: Verify deployment
      run: ./ops.sh health --environment production
```

### GitHub Secrets Required

Add these to repository Settings > Secrets and variables > Actions:

| Secret | Description |
|--------|-------------|
| `DEPLOY_SSH_KEY` | Private SSH key for deployment server |
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

```
1. Create feature branch from main
2. Write code (Gate 1 pre-commit runs locally)
3. Push branch (Gate 2 CI runs automatically)
4. CI fails? Fix issues, push again
5. CI passes? Create PR
6. Get review + approval
7. Merge to main
8. Deploy via ops.sh (manual or automated)
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
| Coverage | - | CI job (90%) | - |
| Security scan | - | CI job | - |
| Container scan | - | CI job | - |
| Security verify | - | - | ops.sh verify |
| Deploy | - | - | ops.sh deploy |
| Health check | - | - | ops.sh health |
| Canary | - | - | ops.sh canary |
| Rollback | - | - | ops.sh rollback |

## Checklist for New Projects

- [ ] Copy appropriate CI workflow to `.github/workflows/ci.yml`
- [ ] Configure branch protection on `main`
- [ ] Add `DEPLOY_SSH_KEY` secret (for automated deploys)
- [ ] Create `production` environment with protection rules
- [ ] Test workflow by creating a PR
- [ ] Verify all checks pass before first production deploy
