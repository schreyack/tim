# Documentation Review: File-to-File Dependency Graph

Direct markdown links and explicit file path references between documentation files.

## Core Docs → Standards

| Source File | References To |
|-------------|--------------|
| `README.md` | `standards/enforcement/gates.md`, `standards/operations/plan-management.md`, `standards/operations/ai-coordination.md`, `standards/operations/legacy-onboarding.md`, `standards/operations/afk-coding-patterns.md`, `standards/coding/python.md`, `standards/coding/typescript.md`, `standards/coding/code-organization.md`, `standards/coding/api-versioning.md`, `standards/testing/requirements.md`, `standards/testing/e2e-requirements.md`, `standards/testing/test-migration.md`, `standards/security/owasp-checklist.md`, `standards/security/secrets.md`, `standards/security/authentication.md`, `standards/database/migrations.md`, `standards/deployment/ci-integration.md`, `standards/deployment/ops-script.md`, `standards/deployment/ops-security.md`, `standards/deployment/feature-flags.md`, `standards/deployment/canary.md`, `standards/deployment/observability.md`, `standards/incident/response.md`, `standards/enforcement/graduated-enforcement.md`, `standards/enforcement/strict-compliance.md`, `standards/enforcement/ai-review-checklist.md`, `standards/enforcement/ai-behavioral-gates.md` |
| `README.md` | `libs/python/README.md`, `libs/node/README.md`, `plugins/tim-loop/README.md` (should be marketplace/), `templates/README.md`, `examples/python/`, `examples/node/`, `tools/tim-compliance-check.sh` |

## Standards Internal References

| Source File | References To |
|-------------|--------------|
| `standards/enforcement/gates.md` | `strict-compliance.md`, `ai-behavioral-gates.md` |
| `standards/enforcement/ai-behavioral-gates.md` | `gates.md` |
| `standards/enforcement/strict-compliance.md` | `gates.md`, `graduated-enforcement.md` |
| `standards/enforcement/graduated-enforcement.md` | `gates.md`, `strict-compliance.md`, `legacy-onboarding.md` |
| `standards/deployment/ops-script.md` | `environments.md`, `remote-only.md`, `command-matrix.md` |
| `standards/architecture/shared-libraries.md` | `standards/coding/python.md`, `standards/coding/typescript.md` |

## Templates → Standards

| Source File | References To |
|-------------|--------------|
| `templates/README.md` | `standards/enforcement/gates.md`, `standards/enforcement/ai-behavioral-gates.md`, `standards/enforcement/strict-compliance.md`, `standards/operations/plan-management.md`, `standards/operations/afk-coding-patterns.md`, `standards/deployment/ops-script.md`, `standards/deployment/environments.md`, `standards/architecture/shared-libraries.md`, `standards/coding/code-organization.md` |
| `templates/tim-patterns.yaml.template` | `standards/security/authentication.md`, `standards/coding/python.md`, `standards/coding/api-design.md` (BROKEN - should be api-versioning.md), `standards/deployment/observability.md` |
| `templates/ops/ops.sh.template` | `standards/deployment/remote-only.md` |
| `templates/environments.yaml.example` | `standards/deployment/environments.md` |

## Pre-commit Templates → Tools

| Source File | References To |
|-------------|--------------|
| `templates/node/.pre-commit-config.yaml` | `lib/tim/tools/check-code-quality.py` |
| `templates/python/.pre-commit-config.yaml` | `lib/tim/tools/check-code-quality.py` |

## Plugin → Standards

| Source File | References To |
|-------------|--------------|
| `marketplace/plugins/tim-loop/README.md` | `standards/enforcement/gates.md`, `standards/operations/plan-management.md` |

## Tools/GitHub → Standards

| Source File | References To |
|-------------|--------------|
| `tools/APPROVAL-QUICK-REFERENCE.md` | `standards/enforcement/ai-developer-ready-checklist.md`, `standards/operations/plan-management.md`, `plugins/tim-loop/scripts/plan-ops.sh` (STALE - now bin/plan-ops) |

---

*Last updated: Phase 1 inventory. Will be re-verified in Phase 7.*
