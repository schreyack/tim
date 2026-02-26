# Enforcement Gates

This document defines the hard gates that block code progression through the development pipeline. All gates are **hard blocks** - no exceptions without documented security review approval.

## Gate Philosophy

- **Never trust**: Assume all code is broken until proven otherwise
- **Always verify**: Automated checks at every stage
- **Defense in depth**: Multiple layers catch different failure modes
- **Fast feedback**: Fail early, fail loud, fail locally when possible

## Gate 1: Local (Pre-commit)

Runs on every `git commit` attempt. Blocks commit on any failure.

### Python Stack

| Check | Tool | Failure Condition |
|-------|------|-------------------|
| Type checking | mypy --strict | ANY type error |
| Linting | ruff check | ANY error or warning |
| Formatting | ruff format --check | ANY formatting diff |
| Secrets | detect-secrets | ANY secret detected |
| Commit format | commitizen | Invalid commit message |

### Node.js Stack

| Check | Tool | Failure Condition |
|-------|------|-------------------|
| Type checking | tsc --noEmit | ANY type error |
| Linting | eslint --max-warnings 0 | ANY error or warning |
| Formatting | prettier --check | ANY formatting diff |
| Secrets | gitleaks | ANY secret detected |
| Commit format | commitizen | Invalid commit message |

### Bypass Policy

Pre-commit hooks can be bypassed with `--no-verify`. However:

- CI will catch the same issues and block merge
- Repeated bypasses trigger code review flag
- Production branches have branch protection requiring CI pass

## Gate 2: CI (Pull Request)

Runs on every PR creation and update. Blocks merge on any failure.

### All Stacks

| Check | Tool | Failure Condition | Priority |
|-------|------|-------------------|----------|
| Gate 1 checks | (see above) | ANY failure | P0 |
| Unit tests (if present) | pytest/jest | ANY test failure | P0 |
| Coverage report (if tests) | Codecov | Reported, no threshold | Informational |
| Security scan (code) | bandit/eslint-security | HIGH or CRITICAL | P0 |
| Security scan (deps) | safety/npm audit | HIGH or CRITICAL | P0 |
| Secrets scan (deep) | trufflehog | ANY detection | P0 |
| Container scan | trivy | HIGH or CRITICAL | P0 |
| License compliance | license-checker (Node) / pip-licenses (Python) | GPL, AGPL, or unlicensed | P1 |

### Coverage Reporting

If a project has tests, coverage is collected and uploaded to Codecov for reviewer visibility. No threshold blocks merge. Tests are not required — writing tests is a human decision, not an AI mandate.

### Security Severity Mapping

| Severity | Action |
|----------|--------|
| CRITICAL | Block merge immediately |
| HIGH | Block merge |
| MEDIUM | Warning, review required |
| LOW | Warning only |

## Gate 3: Deploy (Pre-deployment)

Runs before production deployment. Blocks deploy on any failure.

| Check | Description | Failure Condition |
|-------|-------------|-------------------|
| Integration tests | Cross-service tests | ANY failure |
| E2E tests | Critical user paths | ANY failure |
| Migration dry-run | Database migration preview | ANY error |
| Health endpoints | All services respond | ANY unhealthy |
| Security headers | Header verification | Missing required header |
| Rollback test | Verify rollback works | Rollback fails |
| Canary deployment | 10% traffic test | Error rate > 0.5% |
| Manual approval | Human sign-off | Missing approval |

### Production Approval Checklist

Human approvers must verify before signing off on production deployment:

**Code Quality (AI-Specific)**:

- [ ] Logic reviewed line-by-line - does it actually do what's claimed?
- [ ] No placeholder or TODO code in changes
- [ ] No hallucinated APIs or methods
- [ ] Edge cases are implemented, not just mentioned
- [ ] Test assertions are meaningful

**Deployment Readiness**:

- [ ] All CI checks passed (green build)
- [ ] E2E tests passed on UAT environment
- [ ] Canary deployment completed without issues
- [ ] No new HIGH/CRITICAL security vulnerabilities
- [ ] Database migrations tested with rollback

**Observability**:

- [ ] Logging is in place for new functionality
- [ ] Metrics exposed for new endpoints
- [ ] Alerts configured for failure conditions
- [ ] Dashboard updated if needed

**Rollback Plan**:

- [ ] Rollback procedure documented
- [ ] Rollback tested (migrations reversible)
- [ ] Feature flags in place for new features

Approver must check ALL items before approving. Missing items = deployment blocked.

### Required Security Headers

Every HTTP response must include:

```text
Content-Security-Policy: default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'
Strict-Transport-Security: max-age=31536000; includeSubDomains; preload
X-Content-Type-Options: nosniff
X-Frame-Options: DENY
X-XSS-Protection: 1; mode=block
Referrer-Policy: strict-origin-when-cross-origin
Permissions-Policy: geolocation=(), microphone=(), camera=()
```

### Health Check Requirements

Every service must expose:

```text
GET /health        → Liveness probe (is process running)
GET /health/ready  → Readiness probe (can accept traffic)
GET /health/live   → Full health with dependency status
```

## Gate 4: Pattern Compliance

Runs at deploy time. Blocks deploy if non-compliant.

Every TIM project must register all design patterns in `.tim-patterns.yaml`. This gate verifies:

| Check | Description | Failure Condition |
|-------|-------------|-------------------|
| Pattern registry exists | .tim-patterns.yaml in project root | Missing file |
| All patterns registered | Code patterns match registry | Unregistered pattern detected |
| CUSTOM patterns approved | Non-standard patterns have approval | Missing approval metadata |
| Shared library installed | tim-lib/@tim/lib is dependency | Not in requirements/package.json |
| No secrets in code | Hardcoded secrets check | ANY secret pattern |

### Pattern Detection

The compliance checker (`tim-compliance-check.sh`) detects common patterns:

| Pattern | Detection Method |
|---------|------------------|
| Redis/caching | Import statements, connection strings |
| WebSockets | Library imports, upgrade handlers |
| Message queues | RabbitMQ, SQS, Celery imports |
| External APIs | HTTP client configurations |
| Custom auth | Non-standard auth middleware |

### CUSTOM Pattern Requirements

For patterns without TIM standards:

```yaml
custom_pattern:
  standard: "CUSTOM"
  justification: "Why no TIM standard exists"
  approved_by: "human@example.com"  # REQUIRED
  approved_date: "2025-01-15"       # REQUIRED
  ticket: "STANDARDS-42"            # REQUIRED - link to extension request
  standardize_by: "2025-03-01"      # When formal standard should be created
```

CUSTOM patterns without all required fields are blocked at deploy.

### Enforcement Integration

Gate 4 is enforced by:

1. `tim-compliance-check.sh` in CI pipeline (Gate 2)
2. `tim-compliance-check.sh` pre-deploy (Gate 3)
3. Manual review of CUSTOM patterns

See [strict-compliance.md](strict-compliance.md) for detailed pattern registry documentation.

---

## Exception Process

Exceptions to any gate require:

1. **Written justification**: Why is this exception necessary?
2. **Risk assessment**: What could go wrong?
3. **Mitigation plan**: How will we address the risk?
4. **Time limit**: When will the exception expire?
5. **Approval**: Security team sign-off for security-related exceptions

<!-- Forward reference: exceptions.md does not yet exist -->
Exceptions are tracked in `exceptions.md` with expiration dates. Expired exceptions are removed and the gate is re-enabled.

## Monitoring Gates

Post-deployment monitoring also acts as a gate for rollback:

| Metric | Warning | Critical (Auto-rollback) |
|--------|---------|--------------------------|
| Error rate | > 0.5% | > 1% |
| P99 latency | > 1s | > 3s |
| Health check failures | 1 | 3 consecutive |

## Implementation Checklist

For each TIM project:

- [ ] Pre-commit hooks installed (`pre-commit install`)
- [ ] CI pipeline configured (GitHub Actions)
- [ ] Coverage reporting configured (Codecov upload)
- [ ] Security scanning enabled (bandit/eslint-security + trivy)
- [ ] Secrets scanning enabled (detect-secrets/gitleaks + trufflehog)
- [ ] Deploy gates configured (health checks, migration dry-run)
- [ ] Monitoring alerts configured (error rate, latency)
- [ ] Branch protection enabled (require CI pass)
