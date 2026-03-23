# Graduated Enforcement Standard

This document defines how enforcement levels change during project migration and maturity.

## Overview

Not all projects start at 100% compliance. Graduated enforcement allows projects to:

- Start with warn-only rules
- Progressively tighten enforcement
- Eventually reach full blocking enforcement

This prevents migration paralysis while ensuring eventual compliance.

## Enforcement Levels

### Level 0: Audit Only

**Behavior**: Report violations, never block.

**Use case**: Initial assessment of legacy projects.

```yaml
# .tim-enforcement.yaml
level: 0
name: "audit"
description: "Report violations without blocking"

rules:
  type_check: audit
  test_coverage: audit
  test_naming: audit
  file_size: audit
  complexity: audit
  secrets: block  # Always block secrets
```

### Level 1: Warn on Violations

**Behavior**: Warn on violations, only block critical issues.

**Use case**: Early migration phase.

```yaml
level: 1
name: "warn"
description: "Warn on violations, block critical only"

rules:
  type_check: warn
  test_coverage: warn
  test_naming: warn
  file_size: warn
  complexity: warn
  secrets: block
  security_vulns: block
```

### Level 2: Block New Violations

**Behavior**: Existing violations grandfathered, new violations blocked.

**Use case**: Mid-migration phase.

```yaml
level: 2
name: "freeze"
description: "No new violations allowed"

rules:
  type_check: freeze
  test_coverage: freeze
  test_naming: freeze
  file_size: freeze
  complexity: freeze
  secrets: block
  security_vulns: block

baseline:
  captured_date: "2025-01-15"
  type_errors: 150
  coverage: 75
  non_compliant_tests: 45
```

### Level 3: Ratchet Down

**Behavior**: Must improve on each PR, never regress.

**Use case**: Active migration phase.

```yaml
level: 3
name: "ratchet"
description: "Must improve, never regress"

rules:
  type_check: ratchet
  test_coverage: ratchet
  test_naming: ratchet
  file_size: ratchet
  complexity: ratchet
  secrets: block
  security_vulns: block

ratchet:
  type_errors:
    current: 100
    must_decrease: true
  coverage:
    current: 82
    must_increase: true
  non_compliant_tests:
    current: 30
    must_decrease: true
```

### Level 4: Full Enforcement

**Behavior**: All rules block, no exceptions without approval.

**Use case**: Mature projects, post-migration.

```yaml
level: 4
name: "full"
description: "Full TIM compliance required"

rules:
  type_check: block
  test_coverage: report  # Coverage reported, not gated
  file_size: block  # 500 lines
  complexity: block  # 10 max
  secrets: block
  security_vulns: block
```

## Progression Requirements

### Level 0 → Level 1

**Requirements**:

- Assessment complete
- MIGRATION.md created
- Migration timeline approved

**Timeline**: 1-2 days

### Level 1 → Level 2

**Requirements**:

- Baseline captured
- No new critical violations for 1 week
- Infrastructure in place (pre-commit, CI)

**Timeline**: 1-2 weeks

### Level 2 → Level 3

**Requirements**:

- Baseline violations decreasing
- Test migration started
- At least 25% improvement from baseline

**Timeline**: 2-3 weeks

### Level 3 → Level 4

**Requirements**:

- Type coverage: 100%
- Test coverage: reported (all tests pass)
- No files > 500 lines
- No functions > 50 lines or complexity > 10
- All patterns registered (no MIGRATION status)

**Timeline**: When requirements met

## Implementation

### CI Configuration by Level

**Level 0 (Audit)**:

```yaml
- name: Type Check (audit)
  run: mypy src --strict || true
  continue-on-error: true

- name: Report violations
  run: |
    echo "## Type Check Violations" >> $GITHUB_STEP_SUMMARY
    mypy src --strict 2>&1 | tail -50 >> $GITHUB_STEP_SUMMARY || true
```

**Level 1 (Warn)**:

```yaml
- name: Type Check (warn)
  run: |
    mypy src --strict 2>&1 | tee mypy-output.txt
    if grep -q "error:" mypy-output.txt; then
      echo "::warning::Type check violations found"
    fi
  continue-on-error: true
```

**Level 2 (Freeze)**:

```yaml
- name: Type Check (freeze)
  run: |
    ERRORS=$(mypy src --strict 2>&1 | grep "error:" | wc -l)
    BASELINE=150  # From .tim-enforcement.yaml
    if [ $ERRORS -gt $BASELINE ]; then
      echo "::error::Type errors increased from $BASELINE to $ERRORS"
      exit 1
    fi
```

**Level 3 (Ratchet)**:

```yaml
- name: Type Check (ratchet)
  run: |
    ERRORS=$(mypy src --strict 2>&1 | grep "error:" | wc -l)
    LAST=$(cat .tim-ratchet/type_errors)
    if [ $ERRORS -ge $LAST ]; then
      echo "::error::Type errors must decrease. Was $LAST, now $ERRORS"
      exit 1
    fi
    echo $ERRORS > .tim-ratchet/type_errors
```

**Level 4 (Full)**:

```yaml
- name: Type Check (full)
  run: mypy src --strict
  # No continue-on-error, no baseline - must pass
```

### Pre-commit Configuration by Level

**Level 0-1**: Hooks report but don't block

```yaml
repos:
  - repo: local
    hooks:
      - id: mypy
        name: mypy (warn only)
        entry: bash -c 'mypy src --strict || echo "Type errors found (not blocking)"'
        language: system
        pass_filenames: false
        always_run: true
```

**Level 2+**: Hooks can block

```yaml
repos:
  - repo: local
    hooks:
      - id: mypy
        name: mypy
        entry: mypy src --strict
        language: system
        pass_filenames: false
        always_run: true
```

## Tracking Progress

### Ratchet State File

```yaml
# .tim-ratchet/state.yaml
last_updated: "2025-01-20"
enforcement_level: 3

metrics:
  type_errors:
    initial: 150
    current: 85
    trend: decreasing

  test_coverage:
    initial: 72
    current: 84
    trend: increasing

  non_compliant_tests:
    initial: 45
    current: 20
    trend: decreasing

  files_over_500:
    initial: 8
    current: 3
    trend: decreasing

history:
  - date: "2025-01-15"
    type_errors: 150
    coverage: 72

  - date: "2025-01-18"
    type_errors: 120
    coverage: 78

  - date: "2025-01-20"
    type_errors: 85
    coverage: 84
```

### Dashboard Metrics

Projects should report:

| Metric | Value | Target | Status |
|--------|-------|--------|--------|
| Enforcement Level | 3 | 4 | 🟡 |
| Type Errors | 85 | 0 | 🟡 |
| Test Coverage | 84% | Reported | ✅ |
| Files > 500 | 3 | 0 | 🟡 |

## Edge Cases

### Regression During Migration

If metrics regress (e.g., coverage drops):

1. PR is blocked
2. Developer must either:
   - Fix the regression, or
   - Provide justification for temporary exception
3. Exceptions require human approval

### Emergency Deployments

For critical production fixes:

1. Create hotfix branch
2. Apply minimal fix
3. Deploy with current level enforcement
4. Create follow-up PR for full compliance
5. Follow-up must be completed within 24 hours

### Multiple Branches with Different Levels

Main branch should have highest enforcement. Feature branches can be lower:

```yaml
# .tim-enforcement.yaml
branches:
  main:
    level: 3
  develop:
    level: 2
  feature/*:
    level: 1
```

## Automation

### Level Promotion Script

```bash
#!/bin/bash
# tim-promote-level.sh

CURRENT=$(yq '.level' .tim-enforcement.yaml)
NEXT=$((CURRENT + 1))

if [ $NEXT -gt 4 ]; then
  echo "Already at maximum enforcement level"
  exit 0
fi

# Check requirements for promotion
case $NEXT in
  1)
    # Level 0 → 1: Need assessment
    if [ ! -f MIGRATION.md ]; then
      echo "ERROR: MIGRATION.md required for Level 1"
      exit 1
    fi
    ;;
  2)
    # Level 1 → 2: Need baseline
    if [ ! -f .tim-ratchet/baseline.yaml ]; then
      echo "Capturing baseline..."
      # Forward reference: capture-baseline.sh does not yet exist
      ./tools/capture-baseline.sh
    fi
    ;;
  3)
    # Level 2 → 3: Need 25% improvement
    # Forward reference: check-improvement.sh does not yet exist
    ./tools/check-improvement.sh 25
    ;;
  4)
    # Level 3 → 4: Need full compliance
    ./tools/tim-compliance-check.sh .
    ;;
esac

# Update level
yq -i ".level = $NEXT" .tim-enforcement.yaml
echo "Promoted to enforcement level $NEXT"
```

## See Also

- [Gates](gates.md)
- [Legacy Onboarding](../operations/legacy-onboarding.md)
- [Strict Compliance](strict-compliance.md)
