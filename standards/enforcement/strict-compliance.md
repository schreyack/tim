# Strict Compliance Enforcement

This document defines how TIM **enforces** standards compliance. The goal is to make non-compliance impossible to deploy - not just discouraged.

**Philosophy**: If a human can bypass a rule, an AI definitely will. Make enforcement automatic and unavoidable.

## Enforcement Layers

```text
┌─────────────────────────────────────────────────────────────────────────────┐
│                      COMPLIANCE ENFORCEMENT LAYERS                           │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  LAYER 1: PROACTIVE (Before code is written)                                │
│  ┌────────────────────────────────────────────────────────────────────────┐ │
│  │ • AI system prompts include standards                                  │ │
│  │ • CLAUDE.md in every project                                           │ │
│  │ • Templates enforce patterns                                           │ │
│  └────────────────────────────────────────────────────────────────────────┘ │
│                                                                              │
│  LAYER 2: PREVENTIVE (Before code is committed)                             │
│  ┌────────────────────────────────────────────────────────────────────────┐ │
│  │ • Pre-commit hooks (Gate 1)                                            │ │
│  │ • IDE/editor integrations                                              │ │
│  │ • Local compliance checker                                             │ │
│  └────────────────────────────────────────────────────────────────────────┘ │
│                                                                              │
│  LAYER 3: DETECTIVE (After code is pushed)                                  │
│  ┌────────────────────────────────────────────────────────────────────────┐ │
│  │ • CI pipeline (Gate 2) - BLOCKS MERGE                                  │ │
│  │ • Automated compliance scan                                            │ │
│  │ • Human review checklist enforcement                                   │ │
│  └────────────────────────────────────────────────────────────────────────┘ │
│                                                                              │
│  LAYER 4: BLOCKING (Before deployment)                                      │
│  ┌────────────────────────────────────────────────────────────────────────┐ │
│  │ • Deploy gate compliance check - BLOCKS DEPLOY                         │ │
│  │ • Security verification                                                │ │
│  │ • Standards coverage validation                                        │ │
│  └────────────────────────────────────────────────────────────────────────┘ │
│                                                                              │
│  LAYER 5: UNDEFINED PATTERN HANDLING                                        │
│  ┌────────────────────────────────────────────────────────────────────────┐ │
│  │ • Automatic detection of novel patterns                                │ │
│  │ • Mandatory human review for undefined areas                           │ │
│  │ • Standards extension process                                          │ │
│  └────────────────────────────────────────────────────────────────────────┘ │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

## The Undefined Pattern Problem

AI developers will encounter situations where:

1. No standard exists for a pattern
2. Multiple valid approaches exist
3. The AI makes a reasonable-looking but non-standard choice

### Solution: Mandatory Pattern Registry

Every significant design pattern must be registered. If code uses an unregistered pattern, deployment is blocked.

```yaml
# .tim-patterns.yaml - Required in every project root
patterns:
  authentication:
    standard: "jwt-bearer"
    reference: "standards/security/authentication.md"
    implemented: true

  database_access:
    standard: "sqlalchemy-async"  # or "prisma"
    reference: "standards/coding/python.md#sqlalchemy-patterns"
    implemented: true

  error_handling:
    standard: "app-error-hierarchy"
    reference: "standards/coding/python.md#error-handling"
    implemented: true

  logging:
    standard: "structured-json"
    reference: "standards/deployment/observability.md#logging"
    implemented: true

  api_versioning:
    standard: "url-prefix"
    reference: "standards/coding/api-versioning.md"
    implemented: true

  # If you need a pattern not listed in standards:
  custom_audio_processing:
    standard: "CUSTOM"  # Triggers mandatory review
    justification: "No TIM standard exists for audio DSP"
    approved_by: "tim@example.com"
    approved_date: "2025-01-15"
    ticket: "STANDARDS-42"  # Must link to standards extension ticket
```

### Compliance Checker Behavior

When the compliance checker finds code:

| Situation | Action |
|-----------|--------|
| Uses registered standard pattern | PASS |
| Uses standard but not registered | WARN - add to registry |
| Uses non-standard pattern | BLOCK - must register as CUSTOM |
| CUSTOM pattern without approval | BLOCK - needs human approval |
| CUSTOM pattern with approval | PASS |

## Automated Compliance Checker

A script that runs at Gate 2 (CI) and Gate 3 (deploy) to verify compliance.

### What It Checks

```bash
# tim-compliance-check.sh - Run in CI and before deploy

CHECKS=(
  # Structure
  "has_claude_md"           # CLAUDE.md exists
  "has_pattern_registry"    # .tim-patterns.yaml exists
  "has_env_example"         # .env.example exists
  "has_pre_commit"          # .pre-commit-config.yaml exists

  # Dependencies
  "uses_tim_lib"            # tim-lib is a dependency
  "no_vanilla_js"           # No .js files (TypeScript only)

  # Configuration
  "strict_mode_enabled"     # mypy --strict or tsconfig strict
  "coverage_threshold_set"  # 90% coverage configured

  # Security
  "no_secrets_in_code"      # detect-secrets passes
  "env_not_in_git"          # .env not tracked

  # Patterns
  "all_patterns_registered" # Every pattern in registry
  "no_unapproved_custom"    # CUSTOM patterns have approval
)
```

### Example Output

```text
TIM Compliance Check - my-project
==================================

Structure:
  ✓ CLAUDE.md exists
  ✓ .tim-patterns.yaml exists
  ✓ .env.example exists
  ✓ .pre-commit-config.yaml exists

Dependencies:
  ✓ tim-lib installed
  ✓ No vanilla JavaScript files

Configuration:
  ✓ Strict mode enabled (tsconfig.json)
  ✓ Coverage threshold: 90%

Security:
  ✓ No secrets detected
  ✓ .env not in git

Patterns:
  ✓ authentication: jwt-bearer (registered)
  ✓ database_access: prisma (registered)
  ✓ logging: structured-json (registered)
  ✗ UNREGISTERED: Found usage of Redis caching
    → Add to .tim-patterns.yaml or create CUSTOM entry

╔══════════════════════════════════════════════════════════════════════╗
║                    COMPLIANCE CHECK FAILED                            ║
║                                                                        ║
║  1 unregistered pattern found. Options:                               ║
║                                                                        ║
║  1. If TIM standard exists: Add to .tim-patterns.yaml                 ║
║  2. If no standard exists: Create CUSTOM entry with justification     ║
║  3. If pattern should become standard: Create standards ticket        ║
║                                                                        ║
║  Deployment is BLOCKED until resolved.                                ║
╚══════════════════════════════════════════════════════════════════════╝
```

## Undefined Pattern Workflow

When AI or developer needs to use a pattern without a standard:

```text
┌─────────────────────────────────────────────────────────────────────────────┐
│                     UNDEFINED PATTERN WORKFLOW                               │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  1. Developer/AI identifies need for undefined pattern                       │
│                   │                                                          │
│                   ▼                                                          │
│  2. Check if TIM standard exists but isn't registered                        │
│                   │                                                          │
│           ┌───────┴───────┐                                                  │
│           │               │                                                  │
│     Standard exists   No standard                                            │
│           │               │                                                  │
│           ▼               ▼                                                  │
│     Add to registry   Create CUSTOM entry                                    │
│           │               │                                                  │
│           │               ▼                                                  │
│           │     3. Write justification                                       │
│           │               │                                                  │
│           │               ▼                                                  │
│           │     4. Create standards ticket                                   │
│           │         (STANDARDS-XXX)                                          │
│           │               │                                                  │
│           │               ▼                                                  │
│           │     5. Request human approval                                    │
│           │               │                                                  │
│           │       ┌───────┴───────┐                                          │
│           │       │               │                                          │
│           │   Approved        Rejected                                       │
│           │       │               │                                          │
│           │       ▼               ▼                                          │
│           │   Add approved_by  Must use                                      │
│           │   and date         existing standard                             │
│           │       │               │                                          │
│           └───────┼───────────────┘                                          │
│                   │                                                          │
│                   ▼                                                          │
│  6. Compliance check passes                                                  │
│                   │                                                          │
│                   ▼                                                          │
│  7. After deployment: Create formal standard                                 │
│     (if pattern proves successful)                                           │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

## CUSTOM Pattern Entry Requirements

```yaml
# .tim-patterns.yaml
patterns:
  # CUSTOM entry example
  audio_stem_separation:
    standard: "CUSTOM"

    # REQUIRED: Why no TIM standard applies
    justification: |
      Audio DSP requires specialized processing not covered by TIM standards.
      Using Demucs library for ML-based stem separation.
      Patterns follow library conventions.

    # REQUIRED: Human who approved
    approved_by: "tim@example.com"

    # REQUIRED: When approved
    approved_date: "2025-01-15"

    # REQUIRED: Standards extension ticket
    ticket: "STANDARDS-42"

    # OPTIONAL: Expected standard creation date
    standardize_by: "2025-03-01"

    # OPTIONAL: Alternative approaches considered
    alternatives_considered:
      - "Spleeter - rejected (less accurate)"
      - "OpenUnmix - rejected (slower)"
```

## Human Approval Process

### Who Can Approve

| Pattern Type | Approver |
|--------------|----------|
| Security-related | Security team or senior engineer |
| Database/data | Data team or senior engineer |
| Infrastructure | DevOps or senior engineer |
| All others | Project lead or senior engineer |

### Approval Checklist

Before approving a CUSTOM pattern:

- [ ] No existing TIM standard applies
- [ ] Alternatives were considered and documented
- [ ] Pattern follows general TIM principles (security, type safety, etc.)
- [ ] Standards ticket created for future formalization
- [ ] Pattern is isolated and replaceable when standard is created
- [ ] Tests exist for the custom implementation

### Emergency Approval

For urgent deployments:

1. Senior engineer can approve with `emergency: true`
2. Must include `emergency_reason`
3. Automatically expires in 7 days
4. Creates alert for standards team

```yaml
redis_caching:
  standard: "CUSTOM"
  justification: "Performance hotfix required immediately"
  approved_by: "tim@example.com"
  approved_date: "2025-01-15"
  ticket: "HOTFIX-123"
  emergency: true
  emergency_reason: "Production performance degradation"
  expires: "2025-01-22"  # 7 days
```

## CI Integration

```yaml
# .github/workflows/compliance.yml
name: Compliance Check

on:
  push:
  pull_request:

jobs:
  compliance:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Run TIM Compliance Check
        run: |
          # Download compliance checker
          curl -sSL https://raw.githubusercontent.com/your-org/design_standards/main/tools/tim-compliance-check.sh \
            -o tim-compliance-check.sh
          chmod +x tim-compliance-check.sh

          # Run check - exits non-zero on failure
          ./tim-compliance-check.sh

      - name: Check for unapproved CUSTOM patterns
        run: |
          # Parse .tim-patterns.yaml for CUSTOM without approval
          if grep -q 'standard: "CUSTOM"' .tim-patterns.yaml; then
            # Check each CUSTOM has approved_by
            python3 -c "
import yaml
with open('.tim-patterns.yaml') as f:
    data = yaml.safe_load(f)
for name, pattern in data.get('patterns', {}).items():
    if pattern.get('standard') == 'CUSTOM':
        if not pattern.get('approved_by'):
            print(f'BLOCKED: CUSTOM pattern {name} needs human approval')
            exit(1)
        if not pattern.get('ticket'):
            print(f'BLOCKED: CUSTOM pattern {name} needs standards ticket')
            exit(1)
print('All CUSTOM patterns have required approvals')
"
          fi
```

## Ops.sh Integration

```bash
# In tim-ops-lib.sh, add to deploy command:

verify_compliance() {
    log_info "Running compliance verification..."

    # Download and run compliance check
    local check_result
    check_result=$(curl -sSL "$TIM_COMPLIANCE_CHECK_URL" | bash)

    if [[ $? -ne 0 ]]; then
        log_error "Compliance check failed:"
        echo "$check_result"
        log_error "Deployment BLOCKED"
        return 10
    fi

    log_success "Compliance verified"
}

# Add to deploy command
cmd_deploy() {
    # ... existing code ...

    # NEW: Compliance check before deploy
    verify_compliance || return $?

    # ... rest of deploy ...
}
```

## Pattern Detection Heuristics

The compliance checker identifies patterns by:

### Code Analysis

```python
# Pattern detection examples

# Authentication pattern detected by:
# - JWT imports (python-jose, jsonwebtoken)
# - OAuth2PasswordBearer usage
# - /auth endpoints

# Database pattern detected by:
# - SQLAlchemy/Prisma imports
# - Model definitions
# - Connection strings

# Caching pattern detected by:
# - Redis imports
# - @cache decorators
# - Cache-Control headers

# Logging pattern detected by:
# - structlog/pino imports
# - logger.* calls
# - Log configuration
```

### New Pattern Alert

When checker detects a pattern not in registry:

```text
⚠️  UNREGISTERED PATTERN DETECTED

Pattern: Redis caching
Evidence:
  - Import: redis (src/services/cache.py:1)
  - Usage: redis.get() (src/services/cache.py:15)
  - Config: REDIS_URL in .env.example

This pattern is not in .tim-patterns.yaml.

Options:
  1. If TIM standard exists → Add pattern to registry
  2. If no standard exists → Create CUSTOM entry with justification

See: standards/enforcement/strict-compliance.md#undefined-pattern-workflow
```

## Metrics and Reporting

Track compliance health:

```yaml
# Generated weekly compliance report
compliance_report:
  date: "2025-01-15"
  projects_scanned: 5
  total_patterns: 23
  standard_patterns: 20
  custom_patterns: 3

  custom_patterns_detail:
    - project: "audio-service"
      pattern: "audio_stem_separation"
      age_days: 30
      standardize_by: "2025-03-01"
      status: "pending_standardization"

  compliance_rate: 87%

  actions_needed:
    - "audio_stem_separation approaching standardize_by date"
    - "Project X has 2 unapproved CUSTOM patterns"
```

## Summary

| Layer | Enforcement | Bypass Possible? |
|-------|-------------|------------------|
| Proactive | CLAUDE.md, templates | Yes (new project) |
| Preventive | Pre-commit | Yes (--no-verify) |
| Detective | CI pipeline | No (blocks merge) |
| Blocking | Deploy gate | No (blocks deploy) |
| Undefined | Pattern registry | No (blocks deploy) |

The key insight: **You cannot deploy code with unregistered or unapproved patterns.** The compliance checker runs at deploy time and is not bypassable.
