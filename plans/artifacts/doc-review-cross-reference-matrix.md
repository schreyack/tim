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
| 3.1.1 | `standards/enforcement/gates.md` | pending | enforcement-locked |
| 3.1.2 | `standards/enforcement/ai-behavioral-gates.md` | pending | enforcement-locked |
| 3.1.3 | `standards/enforcement/ai-developer-ready-checklist.md` | pending | |
| 3.1.4 | `standards/enforcement/ai-instruction-enforcement.md` | pending | |
| 3.1.5 | `standards/enforcement/ai-review-checklist.md` | pending | |
| 3.1.6 | `standards/enforcement/graduated-enforcement.md` | pending | |
| 3.1.7 | `standards/enforcement/strict-compliance.md` | pending | enforcement-locked |
| 3.2.1 | `standards/operations/plan-management.md` | pending | |
| 3.2.2 | `standards/operations/ai-coordination.md` | pending | |
| 3.2.3 | `standards/operations/afk-coding-patterns.md` | pending | |
| 3.2.4 | `standards/operations/legacy-onboarding.md` | pending | |
| 3.2.5 | `standards/operations/tim-loop-integration.md` | pending | |
| 3.3.1 | `standards/coding/python.md` | pending | |
| 3.3.2 | `standards/coding/typescript.md` | pending | |
| 3.3.3 | `standards/coding/api-versioning.md` | pending | |
| 3.3.4 | `standards/coding/code-organization.md` | pending | |
| 3.4.1 | `standards/testing/requirements.md` | pending | |
| 3.4.2 | `standards/testing/e2e-requirements.md` | pending | |
| 3.4.3 | `standards/testing/dev-server-verification.md` | pending | |
| 3.4.4 | `standards/testing/promotion-gates.md` | pending | |
| 3.4.5 | `standards/testing/test-data-sot.md` | pending | |
| 3.4.6 | `standards/testing/test-helpers.md` | pending | |
| 3.4.7 | `standards/testing/test-migration.md` | pending | |
| 3.5.1 | `standards/security/authentication.md` | pending | |
| 3.5.2 | `standards/security/headers.md` | pending | |
| 3.5.3 | `standards/security/owasp-checklist.md` | pending | |
| 3.5.4 | `standards/security/secrets.md` | pending | |
| 3.6.1 | `standards/deployment/canary.md` | pending | |
| 3.6.2 | `standards/deployment/ci-integration.md` | pending | |
| 3.6.3 | `standards/deployment/command-matrix.md` | pending | |
| 3.6.4 | `standards/deployment/environments.md` | pending | |
| 3.6.5 | `standards/deployment/feature-flags.md` | pending | |
| 3.6.6 | `standards/deployment/observability.md` | pending | |
| 3.6.7 | `standards/deployment/ops-script.md` | pending | |
| 3.6.8 | `standards/deployment/ops-security.md` | pending | |
| 3.6.9 | `standards/deployment/remote-only.md` | pending | |
| 3.7.1 | `standards/architecture/shared-libraries.md` | pending | |
| 3.7.2 | `standards/database/migrations.md` | pending | |
| 3.7.3 | `standards/governance/rule-classification.md` | pending | |
| 3.7.4 | `standards/incident/response.md` | pending | |

### Phase 4: Plugin Documentation (4 files)

| # | File | Status | Notes |
|---|------|--------|-------|
| 4.1 | `marketplace/plugins/tim-loop/README.md` | pending | |
| 4.2 | `marketplace/plugins/tim-loop/commands/tim-loop.md` | pending | |
| 4.3 | `marketplace/plugins/tim-loop/commands/cancel-tim-loop.md` | pending | |
| 4.4 | `marketplace/plugins/tim-loop/config.yaml` | pending | |

### Phase 5: Templates, Examples, and Libraries (20 files)

| # | File | Status | Notes |
|---|------|--------|-------|
| 5.1 | `templates/README.md` | pending | |
| 5.2 | `templates/CLAUDE.md.template` | pending | |
| 5.3 | `templates/plan.md.template` | pending | |
| 5.4 | `templates/tim-patterns.yaml.template` | pending | |
| 5.5 | `templates/ops/ops-config.yaml.template` | pending | |
| 5.6 | `templates/ops/ops.sh.template` | pending | |
| 5.7 | `templates/environments.yaml.example` | pending | |
| 5.8 | `templates/ci/node-ci.yml` | pending | |
| 5.9 | `templates/ci/python-ci.yml` | pending | |
| 5.10 | `templates/node/.pre-commit-config.yaml` | pending | |
| 5.11 | `templates/python/.pre-commit-config.yaml` | pending | |
| 5.12 | `examples/python/README.md` | pending | |
| 5.13 | `examples/node/README.md` | pending | |
| 5.14 | `examples/python/.tim-patterns.yaml` | pending | |
| 5.15 | `examples/node/.tim-patterns.yaml` | pending | |
| 5.16 | `examples/python/.env.example` | pending | |
| 5.17 | `examples/node/.env.example` | pending | |
| 5.18 | `libs/python/README.md` | pending | |
| 5.19 | `libs/node/README.md` | pending | |
| 5.20 | `tools/APPROVAL-QUICK-REFERENCE.md` | pending | |

### Phase 6: GitHub and Supporting Files (6 files)

| # | File | Status | Notes |
|---|------|--------|-------|
| 6.1 | `.github/PULL_REQUEST_TEMPLATE.md` | pending | |
| 6.2 | `.github/ISSUE_TEMPLATE/bug_report.md` | pending | |
| 6.3 | `.github/ISSUE_TEMPLATE/feature_request.md` | pending | |
| 6.4 | `.github/ISSUE_TEMPLATE/standard_proposal.md` | pending | |
| 6.5 | `.github/ISSUE_TEMPLATE/config.yml` | pending | |
| 6.6 | `.github/workflows/ci.yml` | pending | |

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

---

## Inconsistencies Found During Inventory

| # | Description | Files Involved | Severity |
|---|-------------|---------------|----------|
| I-1 | `templates/tim-patterns.yaml.template` references `standards/coding/api-design.md#versioning` but actual file is `standards/coding/api-versioning.md` | tim-patterns.yaml.template | broken link |
| I-2 | `tools/APPROVAL-QUICK-REFERENCE.md` references `./plugins/tim-loop/scripts/plan-ops.sh` but plan-ops is at `bin/plan-ops` | APPROVAL-QUICK-REFERENCE.md | stale path |
| I-3 | README.md references `plugins/tim-loop/README.md` but actual path is `marketplace/plugins/tim-loop/README.md` | README.md | broken link |
| I-4 | CONTRIBUTING.md references `libs/python` and `libs/node` as bare paths (not linking to README.md files within) | CONTRIBUTING.md | minor |
| I-5 | CHANGELOG.md references `plugins/tim-loop/scripts/` paths that may have moved to `marketplace/plugins/tim-loop/` | CHANGELOG.md | historical (verify) |
| I-6 | `standards/enforcement/ai-behavioral-gates.md` references `code-quality-validator.py` and `excuse-detector.py` - verify these exist at documented paths | ai-behavioral-gates.md | verify |
| I-7 | `standards/architecture/shared-libraries.md` references `tim-ops-lib.sh` - verify this exists | shared-libraries.md | verify |

---

*Last updated: Phase 1 inventory complete. Statuses will be updated as files are reviewed in Phases 2-6.*
