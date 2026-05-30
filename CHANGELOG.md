# Changelog

All notable changes to TIM Standards will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.92.0] - 2026-05-30

### Added

- **Native (C++/Swift/Python) project support.** Onboard native macOS desktop projects (C++17/20 + Swift/SwiftUI, optional unpackaged Python; no backend, no k3s).
  - `detect_template_type()` returns `native` for a root `CMakeLists.txt`, an `*.xcodeproj`, or a `Package.swift` at depth ≤2 — checked above node/python so stray `.py` does not misclassify.
  - New `templates/native/.pre-commit-config.yaml`: clang-format/clang-tidy (C++), swift-format/swiftlint (Swift), Python gates scoped via `types: [python]` so the template stays layout-agnostic, plus the shared secrets/commit/hygiene, TIM enforcement, and pattern-drift (Gate 4) hooks. C++/Swift function size and complexity are owned by clang-tidy/swiftlint (as ESLint owns TS complexity); the 500/50/10 thresholds apply.
  - `check-code-quality.py --language native`: file-size (500) for `.h/.hpp/.hh/.cc/.cpp/.cxx/.swift`, full file+function+complexity for Python.
  - `check-pattern-drift.py` parses CMake (`find_package`/`FetchContent`), `Package.swift`, and `Package.resolved` dependencies; new `native` section in `pattern-library-map.yaml` (starter set for desktop/audio libraries).
  - New `native-app` preset: excludes the vendored `lib/` submodule from the Python linters. No remote-first deploy — Gate 3 (ops.sh/k3s/canary) does not apply to a desktop app.
  - New `standards/coding/native.md` coding standard (C++/Swift toolchain, strict builds, size/complexity enforcement split, real-time-audio safety, gate mapping) and `templates/tim-patterns.native.yaml.template`. README and templates/README updated with the native stack and standard.
  - `templates/native/.pre-commit-config.yaml` added to the enforcement protection (protect-enforcement-files hook + `.tim-enforcement-files` lock list), for parity with the node/python/fullstack templates.

## [2.91.0] - 2026-04-08

### Fixed

- **tim-loop** v3.1.0 → v3.1.1 — Task drift hook reliability. Three layered fixes to eliminate false positives where the hook fired on legitimate continuations of approved fix work:
  1. **Drift context gating**: pattern 4 (`"let me fix the/these/those/this"`) now requires a drift indicator (`I found / I noticed / while I'm here / too / as well / also`) within ±120 chars of the match. Bare `"Let me fix those SIM401 violations"` no longer trips drift; `"Let me fix the bugs I noticed"` still does.
  2. **Multi-turn human intent scanning**: `_user_requested_action` now scans the last 3 human turns for action verbs (`fix / commit / deploy / ...`) instead of only the most recent. A clarifying question (`"why is it failing?"`) mid-session no longer invalidates an earlier `"commit and push"`.
  3. **Active task awareness**: drifts whose action verb (`fix / implement / refactor / ...`) appears in any non-completed `TaskCreate` subject or description are filtered out. The task list is the authoritative scope — if `Fix mypy violations` is in-progress, `"Let me fix the issues I found"` is on-task, not drift. Reconstructs task state by walking `TaskCreate` / tool-result / `TaskUpdate` entries in the transcript.
- Same active-task filter wired into the Stop-hook (`excuse_detector_v2.check_task_drift`) so PostToolUse and Stop stay consistent.
- 10 new tests covering each layer (drift context gating, multi-turn scanning, active/completed/unrelated/pending task coverage); 24 total in `test_fast_pattern_detector.py`, all 210 tim-loop tests passing.

## [2.90.0] - 2026-03-24

### Added

- **Block piped ops.sh commands** — PreToolUse hook prevents piping ops.sh output through tail, head, grep, tee, etc. Piping buffers streaming output and causes Claude Code sessions to hang. Detects both `ops.sh` and project aliases (via `ops-config.yaml` discovery and `--env` heuristic).
- **tim-loop plugin** v2.89.7 → v2.90.0

## [2.88.0] - 2026-03-05

### Added

- **Anti-cheat enforcement** — Ban all inline suppression comments (`# noqa`, `// eslint-disable`, `// @ts-ignore`, `# type: ignore`, etc.) with file-level exemptions only via `.tim-no-suppression.yaml`
- **AI cheat detection** — AST-based detection of code-level enforcement evasion: empty except handlers, broad exception catches, log-and-swallow patterns, `typing.cast()`, `defaultdict`, double-cast (`as unknown as Type`), empty catch blocks
- **Try/except fallback detection** — `no-fallback-defaults` now catches `try: v = d["key"] except KeyError: v = "default"` and `DEFAULT_*` variable fallbacks
- **New tools**: `no-suppression-comments.py`, `cheat_python.py`, `cheat_typescript.py`, `detect-ai-cheats.py`
- **New config files**: `.tim-no-suppression.yaml`, `.tim-no-fallback.yaml`, `.tim-ai-cheat.yaml` (all protected by `protect-enforcement-files`)
- **tim-loop** PostToolUse hook now detects suppression comments at write time

### Changed

- Removed `grep -v noqa` universal bypass from all bash-based pre-commit hooks
- Removed inline `# noqa: no-fallback` suppression from fallback detection tools (file-level exemption only)
- **tim-loop plugin** v2.81.0 → v2.82.0

## [2.87.0] - 2026-02-27

### Added

- **tim-pbt plugin** v2.0.1 → v2.1.1 — Blocker resolution loop: when budget gap has resolvable blockers (missing test DB, framework deps, config), Claude pauses and asks the user instead of silently exiting. New Phase 7.5 in prompt, `<pbt-blockers>` signal, blocker state tracking with pending/accepted/resolved/rescanned/declined lifecycle. Anti-self-scoping prompt reinforcement: behavioral bias warning at top + guardrail in Phase 1a preventing prior report from narrowing scope.

### Fixed

- **tim-pbt plugin** v2.0.0 → v2.0.1 — `is_coverage_complete()` now validates evaluated arrays contain all 13 property types, not just the `complete` flag. `get_remaining_work()` catches modules marked complete but with missing types.

## [2.86.0] - 2026-02-27

### Changed

- **tim-pbt plugin** v1.5.0 → v2.0.0 — Hook-enforced autonomous loop with module+property-type coverage tracking

### Fixed

- Standards count corrected from 41 to 40 across README and rules
- `git-guard` removed from standalone tools lists (lives in tim-loop plugin, not `tools/`)
- `your-org/tim` placeholder URLs → `schreyack/tim` in both library READMEs
- Node.js library license corrected from "Internal use only" to Apache 2.0
- tim-loop README: `settings.local.json` → `hooks/hooks.json`, `plugins/cache/` → `plugins/marketplaces/`
- `tools/` tree in README expanded to reflect all files on disk
- Added Tim PBT/E2E to feature request template and plugin update type to PR template

## [2.85.0] - 2026-02-26

### Added

- **tim-pbt plugin** (v1.0.0) — Property-based bug hunting with Hypothesis (Python) and fast-check (TypeScript)
- **tim-e2e plugin** (v1.2.2) — Playwright MCP-driven E2E testing where Claude drives a real browser
  - Auto-installs Playwright MCP server when missing
  - Detects base URL from `playwright.config.ts`, env vars, and `package.json`
  - Prompts user when app is unreachable; persists `--base-url` to config
- **tim-sync** script for syncing submodule updates across projects
- **git-guard** wrapper blocking destructive git commands (PreToolUse hook + standalone)
- **no-hardcoded-settings** pre-commit hook enforcing settings source-of-truth
- **Settings SOT checker** (`sot_common.py`, `sot_python.py`, `sot_typescript.py`) with two-tier enforcement and blocked-pattern support
- `database_app_service` config key to `tim-ops-lib`
- OSC 52 clipboard copy for SSH sessions in plan-ops

### Changed

- tim-loop plugin: 2.15.0 → 2.80.0 (see detailed history below)
- Marketplace plugin versions now tracked independently (tim-loop, tim-pbt, tim-e2e)
- Documentation overhaul: cross-reference matrix, dependency graph, 7-phase review of all docs
- Testing standards rewritten for value-driven testing
- Coverage thresholds removed from enforcement (reported only)
- Migration rollback testing requirement removed

### Fixed

- Destructive git command patterns in PreToolUse hook (`git checkout <ref> -- .`)
- Staged-files-only scanning in bandit and code-quality hooks
- Correct `identify` type tags in node template

## [2.80.0] - 2026-02-22

### Added

- Comprehensive pre-commit enforcement with industry best practices
- Enforcement file locking (`chflags uchg` + `schg`)
- Path-agnostic templates for symlink distribution
- **LLM judge** for semantic evasion detection (`--llm-loop` flag)
  - Task-context-aware criteria with original task in prompt
  - Hard stop on FAIL verdict with human options
  - Config file support for judge settings
- **LLM-based task type classification** replacing regex detection
- **Context-efficient full review** for large plans (delegates to subagents)
- **Sticky system halt** (`continue:false`) persists across turns and agents
- **Interactive plan picker** in plan-ops wizard when no args given
- **Behavioral directives** moved from CLAUDE.md into tim-loop prompt (v2.77.0)
- Per-phase iteration tracking for full-review mode
- 7-phase full review: Tech, Devil's Advocate, Security, AI-Ready, Goal Alignment, PM, User Advocate
- Unilateral decision detection and User Advocate review phase
- Mode violation detector for wrong task execution
- Task drift detection with option expander for stop hooks
- `--team` flag for parallel implementation with agent teams (experimental)
- PreToolUse hook blocking `--no-verify` and `chflags` bypass attempts
- Fast pattern detector for PostToolUse hook
- Verification failure recovery with `<!-- VERIFIED: FAILED -->` markers

### Changed

- Hooks moved from `settings.local.json` to `hooks.json` (v2.73.0)
- Code quality violations now warn instead of halting (configurable)
- Review passes reframed to prevent work-pacing behavior
- Excuse detection skipped when user is interacting or in implement/full-review mode
- Stop hook no longer burns iterations on agent-coordination turns
- Setup instructions updated for submodule + symlink approach
- `mirrors-mypy` replaced with local hook in Python template

### Fixed

- Full-review phase tracking survives context compaction
- Multi-project support with PID-based state lookup
- Cross-session staleness cleanup prevention
- Hook accumulation in long sessions
- False positives in task drift, excuse patterns, and LLM judge
- Plan-ops status header detection, wizard stage/folder mismatches

## [2.70.4] - 2026-02-12

### Added

- **Shared bash library** (`libs/bash/tim-common.sh`) for colors and project loading
- **sync-claude-md** and **sync-pre-commit** scripts for propagating TIM standards
- `protect-enforcement-files` pre-commit hook for sub-project templates
- "No optional work in plans" principle added to standards

### Changed

- **tim-loop-setup.sh** split from 983 lines into 6 modular files: `setup-core.sh`, `setup-help.sh`, `setup-hooks.sh`, `setup-prompts.sh`, `setup-prompts-review.sh`
- **tim-loop-prompt-manager.sh** split into 3 modules: `prompt-manager-commands.sh`, `prompt-manager-core.sh`, `prompt-manager-security.sh`
- Python transcript utilities deduplicated with shared helpers
- Test validation scripts split into modular test files
- `tim-lock-enforcement` refactored to use `tim-common.sh` and `.tim-enforcement-files`
- Plan-ops helpers deduplicated; dead code removed across codebase
- Plugins moved from top-level to `marketplace/` directory
- Pre-commit symlinks replaced with generated configs (`sync-pre-commit`)

### Fixed

- Enforcement file bitmask values in flag detection
- ANSI color variable ordering (module-level dependency)
- Plan-ops path resolution after marketplace move

## [2.51.0] - 2026-02-07

### Added

- True system halt using `continue:false` response
- Session isolation with global excuse detection
- Hard stop after full-review completion
- Plan-ops full review option for any plan state
- Structured verification of "already done" plan items

### Changed

- Excuse detector only runs when tim-loop is active
- Skip task drift detection in full-review and implement modes

### Fixed

- Plan-ops auto-repair for invalid Stage fields
- Excuse detection scans stop at human turn boundary
- Bypass attempts hardened in stop hooks

## [2.43.0] - 2026-02-04

### Added

- YAML-based excuse patterns with optional LLM-as-judge
- Config file support for LLM judge and auto-pattern feedback
- Two-phase persona-switching for tech review
- Per-phase iteration tracking for full-review
- 6-phase full-review with complexity enforcement and hook health check
- Staleness detection for tim-loop sessions

### Changed

- LLM judge uses original task instead of guessing context
- Instruction-following made primary LLM judge check
- Mode/task checks limited to last 10 assistant messages

### Fixed

- LLM verdict parsing handles markdown formatting
- Reduced false positives in excuse patterns and LLM judge
- Cross-session staleness cleanup prevention

## [2.27.0] - 2026-02-01

### Added

- Verification gate vulnerability fixes

### Fixed

- Plan-ops package prompt buffering issue
- Send prompt output to `/dev/tty`

---

## [2.5.6] - 2025-01-29

### Added

- Category Q: Shortcut Reasoning patterns (93-100) for excuse detector
  - Catches "simplest fix", "easiest solution", "quickest approach" language
  - Gentle response that encourages analysis of alternatives, not accusatory
  - New mitigation patterns (16-20) for when Claude considers alternatives
- New file: `marketplace/plugins/tim-loop/scripts/patterns_shortcut.py`
- New test file: `marketplace/plugins/tim-loop/scripts/test_excuse_patterns_shortcut.py`

### Changed

- tim-loop plugin version: 2.14.0 -> 2.15.0
- Excuse detector now routes shortcut patterns to gentle "consider alternatives" response

## [2.5.5] - 2025-01-26

### Added

- CHANGELOG.md with full version history
- GitHub issue templates (bug report, feature request, standard proposal)
- GitHub pull request template

## [2.5.4] - 2025-01-26

### Added

- Community files for open source release (CODE_OF_CONDUCT.md, CONTRIBUTING.md, SECURITY.md)

### Changed

- Improved README based on review feedback
- Prepared documentation for open source release

## [2.5.3] - 2025-01-25

### Added

- Call for PR contributions in personal note from Tim Schreyack

## [2.5.2] - 2025-01-25

### Added

- Personal note from Tim Schreyack explaining project origins

## [2.5.1] - 2025-01-25

### Added

- Recommended 3-terminal workflow documentation for plan-ops

## [2.5.0] - 2025-01-25

### Changed

- Restructured READMEs for clarity and accuracy

## [2.4.1] - 2025-01-24

### Changed

- Simplified redundant platform checks in tim-local-dev-enable

### Fixed

- Removed orphaned reference to non-existent file

### Security

- Removed remaining private data from examples
- Updated .gitignore for open source
- Sanitized repository for open source release

## [2.4.0] - 2025-01-24

### Added

- Scope protection rules in tim-loop prompts
- Accountability rules for AI enforcement

## [2.3.2] - 2025-01-23

### Fixed

- Auto-cleanup of tim-loop state on user termination

## [2.3.1] - 2025-01-23

### Changed

- Cleaned up redundant files
- Abandoned outdated plans

## [2.2.0] - 2025-01-22

### Added

- Comprehensive excuse detector enhancement with 38 new patterns
- Scope reduction detection patterns
- Constraint deflection pattern detection

## [2.1.0] - 2025-01-21

### Changed

- Plan review is now optional for single-phase plans

## [2.0.3] - 2025-01-20

### Fixed

- Search now checks top-level plans/ directory in plan-ops

## [2.0.2] - 2025-01-20

### Fixed

- Removed redundant hooks reference (now auto-loaded by default)

## [2.0.1] - 2025-01-20

### Fixed

- Added explicit hooks reference to plugin.json for auto-loading

## [2.0.0] - 2025-01-20

### Changed

- **BREAKING**: Consolidated review functionality into Tim Loop
- Removed Ralph Loop dependency

## [1.9.2] - 2025-01-19

### Added

- /clear reminder to all loop command outputs

## [1.9.1] - 2025-01-19

### Fixed

- log_info/log_warn now output to stderr to avoid capture issues

## [1.9.0] - 2025-01-19

### Added

- /tim-loop:cancel-tim-loop command

### Fixed

- Wizard auto-moves plans from plans/ root to correct subfolder

## [1.8.0] - 2025-01-18

### Added

- plan-ops added to PATH for easier access
- PATH setup instructions in main README

### Changed

- Removed tools/plan-ops.sh in favor of plugin-bundled version

## [1.7.0] - 2025-01-17

### Changed

- Refactored plan-ops.sh into modular structure

### Added

- Plugin version management instructions in CLAUDE.md

## [1.6.0] - 2025-01-16

### Added

- Native PreCompact hook for context compaction recovery

## [1.5.0] - 2025-01-15

### Added

- Mitigation detection in excuse detector
- Expanded excuse patterns for better coverage

## [1.4.0] - 2025-01-14

### Added

- Additional excuse detector patterns for deflection coverage

## [1.3.1] - 2025-01-13

### Fixed

- Use namespaced plugin command /tim-loop:tim-loop

## [1.2.0] - 2025-01-12

### Added

- Session cleanup enhancement to tim-loop plugin

## [1.1.0] - 2025-01-11

### Added

- AI behavioral gates to tim-loop plugin
- Code quality validator hook
- Excuse pattern detector hook

## [1.0.0] - 2025-01-10

### Added

- Initial release of TIM Standards
- Tim Loop as official Claude Code plugin
- Four-gate enforcement model (Local, CI, Deploy, Pattern Compliance)
- Python shared library (tim-lib)
- Node.js shared library (@tim/lib)
- Pre-commit hooks configuration
- CI/CD pipeline templates
- Comprehensive standards documentation
- Plan lifecycle management with plan-ops
- Remote-first deployment strategy
- AI Developer Ready gate
- Verification tim-loop for plan completion
