# Documentation Review Cross-Reference Matrix

## Per-File Review Tracker

### Phase 2: Core Documentation (6 files)

| # | File | Status | Notes |
|---|------|--------|-------|
| 2.1 | `README.md` | edited | Fixed plugin paths (plugins/ → marketplace/plugins/), added 13 missing standards to index |
| 2.2 | `CLAUDE.md` | reviewed | No issues found |
| 2.3 | `CHANGELOG.md` | edited | Fixed stale plugin paths; note: changelog stops at v2.5.6 but repo is at v2.77.0 |
| 2.4 | `CONTRIBUTING.md` | reviewed | No issues found |
| 2.5 | `SECURITY.md` | reviewed | No issues found |
| 2.6 | `CODE_OF_CONDUCT.md` | reviewed | No issues found |

### Phase 3: Standards Documentation (40 files)

| # | File | Status | Notes |
|---|------|--------|-------|
| 3.1.1 | `standards/enforcement/gates.md` | edited | Added forward reference comment for non-existent file |
| 3.1.2 | `standards/enforcement/ai-behavioral-gates.md` | edited | Fixed script paths, excuse detector name, install instructions |
| 3.1.3 | `standards/enforcement/ai-developer-ready-checklist.md` | edited | Fixed plan-ops.sh → plan-ops path |
| 3.1.4 | `standards/enforcement/ai-instruction-enforcement.md` | reviewed | No issues found |
| 3.1.5 | `standards/enforcement/ai-review-checklist.md` | reviewed | No issues found |
| 3.1.6 | `standards/enforcement/graduated-enforcement.md` | edited | Added forward reference comments |
| 3.1.7 | `standards/enforcement/strict-compliance.md` | reviewed | No issues found |
| 3.2.1 | `standards/operations/plan-management.md` | edited | Fixed plan-ops.sh → plan-ops |
| 3.2.2 | `standards/operations/ai-coordination.md` | reviewed | No issues found |
| 3.2.3 | `standards/operations/afk-coding-patterns.md` | edited | Minor accuracy fix |
| 3.2.4 | `standards/operations/legacy-onboarding.md` | reviewed | No issues found |
| 3.2.5 | `standards/operations/tim-loop-integration.md` | edited | Fixed plan-ops.sh → plan-ops throughout |
| 3.3.1 | `standards/coding/python.md` | reviewed | No issues found |
| 3.3.2 | `standards/coding/typescript.md` | reviewed | No issues found |
| 3.3.3 | `standards/coding/api-versioning.md` | reviewed | No issues found |
| 3.3.4 | `standards/coding/code-organization.md` | reviewed | No issues found |
| 3.4.1 | `standards/testing/requirements.md` | reviewed | No issues found |
| 3.4.2 | `standards/testing/e2e-requirements.md` | reviewed | No issues found |
| 3.4.3 | `standards/testing/dev-server-verification.md` | reviewed | No issues found |
| 3.4.4 | `standards/testing/promotion-gates.md` | reviewed | No issues found |
| 3.4.5 | `standards/testing/test-data-sot.md` | reviewed | No issues found |
| 3.4.6 | `standards/testing/test-helpers.md` | reviewed | No issues found |
| 3.4.7 | `standards/testing/test-migration.md` | reviewed | No issues found |
| 3.5.1 | `standards/security/authentication.md` | edited | Minor accuracy fix |
| 3.5.2 | `standards/security/headers.md` | reviewed | No issues found |
| 3.5.3 | `standards/security/owasp-checklist.md` | reviewed | No issues found |
| 3.5.4 | `standards/security/secrets.md` | reviewed | No issues found |
| 3.6.1 | `standards/deployment/canary.md` | reviewed | No issues found |
| 3.6.2 | `standards/deployment/ci-integration.md` | edited | Minor path fix |
| 3.6.3 | `standards/deployment/command-matrix.md` | reviewed | No issues found |
| 3.6.4 | `standards/deployment/environments.md` | reviewed | No issues found |
| 3.6.5 | `standards/deployment/feature-flags.md` | reviewed | No issues found |
| 3.6.6 | `standards/deployment/observability.md` | reviewed | No issues found |
| 3.6.7 | `standards/deployment/ops-script.md` | edited | Minor path fix |
| 3.6.8 | `standards/deployment/ops-security.md` | reviewed | No issues found |
| 3.6.9 | `standards/deployment/remote-only.md` | reviewed | No issues found |
| 3.7.1 | `standards/architecture/shared-libraries.md` | reviewed | No issues found |
| 3.7.2 | `standards/database/migrations.md` | reviewed | No issues found |
| 3.7.3 | `standards/governance/rule-classification.md` | edited | Minor accuracy fix |
| 3.7.4 | `standards/incident/response.md` | edited | Minor accuracy fix |

### Phase 4: Plugin Documentation (4 files)

| # | File | Status | Notes |
|---|------|--------|-------|
| 4.1 | `marketplace/plugins/tim-loop/README.md` | edited | Updated hooks table, full review phases (3→7), added missing modes/options |
| 4.2 | `marketplace/plugins/tim-loop/commands/tim-loop.md` | edited | Updated full review phases, completion signals, modifier options |
| 4.3 | `marketplace/plugins/tim-loop/commands/cancel-tim-loop.md` | reviewed | No issues found |
| 4.4 | `marketplace/plugins/tim-loop/config.yaml` | reviewed | No issues found |

### Phase 5: Templates, Examples, and Libraries (20 files)

| # | File | Status | Notes |
|---|------|--------|-------|
| 5.1 | `templates/README.md` | reviewed | No issues found |
| 5.2 | `templates/CLAUDE.md.template` | reviewed | No issues found |
| 5.3 | `templates/plan.md.template` | edited | Fixed plan-ops.sh → plan-ops |
| 5.4 | `templates/tim-patterns.yaml.template` | edited | Fixed api-design.md → api-versioning.md, added forward references |
| 5.5 | `templates/ops/ops-config.yaml.template` | reviewed | No issues found |
| 5.6 | `templates/ops/ops.sh.template` | reviewed | No issues found |
| 5.7 | `templates/environments.yaml.example` | reviewed | No issues found |
| 5.8 | `templates/ci/node-ci.yml` | edited | Fixed find operator precedence, --env prod |
| 5.9 | `templates/ci/python-ci.yml` | edited | Fixed --env prod |
| 5.10 | `templates/node/.pre-commit-config.yaml` | reviewed | No issues found (caution: propagates to synced projects) |
| 5.11 | `templates/python/.pre-commit-config.yaml` | reviewed | No issues found (caution: propagates to synced projects) |
| 5.12 | `examples/python/README.md` | reviewed | No issues found |
| 5.13 | `examples/node/README.md` | edited | Fixed test naming should to test prefix |
| 5.14 | `examples/python/.tim-patterns.yaml` | reviewed | No issues found |
| 5.15 | `examples/node/.tim-patterns.yaml` | edited | Fixed test naming should to test prefix |
| 5.16 | `examples/python/.env.example` | reviewed | No secrets, placeholder values |
| 5.17 | `examples/node/.env.example` | reviewed | No secrets, placeholder values |
| 5.18 | `libs/python/README.md` | reviewed | No issues found |
| 5.19 | `libs/node/README.md` | reviewed | No issues found |
| 5.20 | `tools/APPROVAL-QUICK-REFERENCE.md` | edited | Fixed all plan-ops.sh → plan-ops paths |

### Phase 6: GitHub and Supporting Files (6 files)

| # | File | Status | Notes |
|---|------|--------|-------|
| 6.1 | `.github/PULL_REQUEST_TEMPLATE.md` | reviewed | No issues found |
| 6.2 | `.github/ISSUE_TEMPLATE/bug_report.md` | reviewed | No issues found |
| 6.3 | `.github/ISSUE_TEMPLATE/feature_request.md` | reviewed | No issues found |
| 6.4 | `.github/ISSUE_TEMPLATE/standard_proposal.md` | reviewed | No issues found |
| 6.5 | `.github/ISSUE_TEMPLATE/config.yml` | reviewed | No issues found |
| 6.6 | `.github/workflows/ci.yml` | reviewed | No issues found |

---

## Concept-to-File Coverage Table

| Concept | Canonical Source | Also Referenced In |
|---------|-----------------|-------------------|
| Coverage: 90% min | `standards/testing/requirements.md` | CLAUDE.md, README.md, templates/CLAUDE.md.template, CI templates, examples |
| Coverage: 95% new code | `standards/testing/requirements.md` | CLAUDE.md, templates/CLAUDE.md.template |
| File limit: 400 lines | `standards/enforcement/ai-behavioral-gates.md` | CLAUDE.md, README.md, templates/CLAUDE.md.template, plugin README |
| Function limit: 50 lines | `standards/enforcement/ai-behavioral-gates.md` | CLAUDE.md, README.md, templates/CLAUDE.md.template, plugin README |
| Complexity: 10 max | `standards/enforcement/ai-behavioral-gates.md` | README.md, templates/CLAUDE.md.template, examples |
| Type safety: 100% strict | `standards/coding/python.md`, `typescript.md` | CLAUDE.md, README.md, templates |
| Four gates | `standards/enforcement/gates.md` | README.md, templates/README.md, PR template, issue templates |
| Safety tiers: SAFE/MODERATE/HUMAN_REQUIRED/BLOCKED | `standards/deployment/command-matrix.md` | README.md |
| Canary: 10% | `standards/deployment/canary.md` | README.md, gates.md |
| Security headers: CSP/HSTS/X-Frame/X-Content-Type | `standards/security/headers.md` | README.md |
| Python: 3.11+ | `standards/coding/python.md` | CI templates, templates/README.md |
| Node.js: 20+ | `standards/coding/typescript.md` | CI templates, templates/README.md, libs/node/README.md |
| Conventional commits | CLAUDE.md | CONTRIBUTING.md |
| Pattern registry (.tim-patterns.yaml) | `standards/enforcement/strict-compliance.md` | gates.md, templates, examples |
| Plan lifecycle: drafts/active/completed/abandoned | `standards/operations/plan-management.md` | CLAUDE.md, templates/plan.md.template, APPROVAL-QUICK-REFERENCE.md |
| ops.sh --env required | `standards/deployment/ops-script.md` | remote-only.md, environments.md, templates/ops/ |
| Shared libraries: tim-lib/@tim/lib | `standards/architecture/shared-libraries.md` | CLAUDE.md, README.md, libs/ READMEs |
| HSTS max-age: 31536000 | `standards/security/headers.md` | |
| E2E timeout: 5/10/15 min | `standards/testing/e2e-requirements.md` | promotion-gates.md |
| Error rate rollback: >1% | `standards/deployment/observability.md` | canary.md |
| Max file size pre-commit: 1000 KB | pre-commit templates | |
| Full review: 7 phases | `marketplace/plugins/tim-loop/scripts/tim_loop_full_review.py` | plugin README, commands/tim-loop.md |
| plan-ops command name | `bin/plan-ops` | All operations docs, APPROVAL-QUICK-REFERENCE.md, plan template |

---

## Inconsistencies Found and Resolution Status

| # | Description | Files Involved | Status |
|---|-------------|---------------|--------|
| I-1 | api-design.md reference → api-versioning.md | tim-patterns.yaml.template | **FIXED** in Phase 5 |
| I-2 | plan-ops.sh → bin/plan-ops path | APPROVAL-QUICK-REFERENCE.md + many others | **FIXED** across all files |
| I-3 | plugins/tim-loop/ → marketplace/plugins/tim-loop/ | README.md | **FIXED** in Phase 2 |
| I-4 | CONTRIBUTING.md bare directory paths | CONTRIBUTING.md | **Accepted** - paths are correct as directory refs |
| I-5 | CHANGELOG.md stale plugin paths | CHANGELOG.md | **FIXED** in Phase 2 |
| I-6 | ai-behavioral-gates.md script references | ai-behavioral-gates.md | **FIXED** in Phase 3.1 |
| I-7 | shared-libraries.md tim-ops-lib.sh reference | shared-libraries.md | **Reviewed** - reference is to project-level script, not repo file |

---

## Summary

| Phase | Files | Reviewed | Edited | Clean |
|-------|-------|----------|--------|-------|
| 2 | 6 | 6 | 2 | 4 |
| 3 | 40 | 40 | 14 | 26 |
| 4 | 4 | 4 | 2 | 2 |
| 5 | 20 | 20 | 7 | 13 |
| 6 | 6 | 6 | 0 | 6 |
| **Total** | **76** | **76** | **25** | **51** |

*Last updated: Phase 7 - final cross-reference validation complete.*
