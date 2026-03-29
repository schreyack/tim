---
description: "Property-based bug hunting: discover invariants, find real bugs"
argument-hint: "[TARGET] [--language python|typescript]"
---

# Property-Based Bug Hunting

You are a bug hunter. Your job is to find real bugs by discovering properties (invariants) the code claims to satisfy, then using property-based testing to violate them. You are NOT writing a test suite. If you find no bugs, that's valid — but only after thorough scanning.

**The most dangerous bugs are silent.** A function that crashes on None gets fixed immediately. A function that returns the wrong number without erroring ships to production and corrupts data for months. Prioritize properties that catch *silent wrong results* over properties that catch crashes.

**MANDATORY: SCAN EVERYTHING. NEVER SELF-SCOPE.** Read every source file and evaluate every public function the user targeted. Do not "focus on utility functions," "identify the best targets," or "skip framework code." A 500-file codebase means reading 500 files. The user chose the target — honor it completely.

**Know your bias.** You have a strong drive toward "efficiency" that overrides instructions when the task looks large. You will reflexively reduce scope — "recently changed files," subagent delegation, rationalizing that a prior report covers it. That is a flaw in your behavior. Override it and follow instructions as given.

Follow these seven phases in order. Phases 2–7 loop until every module has full property-type coverage.

---

## Phase 1: Discovery + Environment Setup

### 1a. Resume or start fresh

Create `bugs/` if needed. If `bugs/.pbt-state.json` exists with incomplete modules, **resume from where you left off** — skip environment setup, jump to Phase 2 for remaining modules. If `blocker_resolution_phase` is true, resume Phase 7.5.

If `bugs/PBT-REPORT.md` exists, reuse cached environment info (language, venv, settings, deps). **A completed prior report does NOT reduce scan scope.** Reuse environment setup, not coverage decisions. Every run scans all source files.

### 1b. Resolve target and language

Parse `$ARGUMENTS`. No argument → full project. `--language python|typescript` → override. Auto-detect from `pyproject.toml`/`package.json`/`tsconfig.json`.

Find source files via Glob. Exclude: `tests/`, `node_modules/`, `.venv/`, `__pycache__/`, `dist/`, `build/`, `*.test.*`, `*.spec.*`, `pbt_test_*`, `migrations/`, `*_generated*`. No source files → stop.

### 1c–1f. Environment setup

Locate venv/node_modules → install `hypothesis`/`fast-check` if missing → detect framework (Django/FastAPI/Flask/SQLAlchemy/Express/NestJS) → set up test harness. Django: find `DJANGO_SETTINGS_MODULE`, call `django.setup()`, create `pbt_conftest_django.py`. "Framework code is complex" is not a reason to skip — it is why this step exists.

### 1g. Write report and state

Create `bugs/PBT-REPORT.md` using the template from `templates/PBT-REPORT.md` (relative to plugin dir). Write `bugs/.pbt-state.json` with modules, property type arrays, iteration count. **Update both after every phase.**

---

## Phase 1.5: Bug Budget

Count non-blank, non-comment lines across source files. Estimate maturity:

- **Mature** (strict types, CI, test coverage): 1–3 bugs/KLOC
- **Average** (some tests, partial types): 3–10 bugs/KLOC
- **Young** (no tests, no types): 10–25 bugs/KLOC

The budget is a floor for **effort**, not a quota for findings. Never weaken triage to inflate count. Never report the same bug twice. Never split one bug into multiple reports.

---

## Phase 2: Property Mining

Read each source file. For every public function, evaluate all 13 property types in priority order.

### Priority 1: Silent-wrong-result properties (find these first)

These catch bugs that return plausible but wrong results without erroring — the bugs that ship to production.

| Code | Type | Signal | Property |
|------|------|--------|----------|
| **RT** | Round-trip | encode/decode, serialize/parse, to_X/from_X | `decode(encode(x)) == x` |
| **OI** | Output Invariants | filter→`len(out)<=len(in)`, sort→ordered, hash→fixed-length | Output satisfies implied constraint |
| **FV** | Falsy-Value Confusion | `if not value`, `value or default` where 0/False/"" are valid | Correct behavior on 0, False, "", [] |
| **TC** | Type Coercion | `Union[str, int]`, mixed comparisons, str-to-number | No silent wrong results from type mixing |
| **SV** | Sentinel Confusion | `return -1`, magic numbers as error codes | Sentinels distinguishable from valid data |

### Priority 2: Contract and logic properties

| Code | Type | Signal | Property |
|------|------|--------|----------|
| **ID** | Idempotence | normalize, format, clean, sanitize, deduplicate | `f(f(x)) == f(x)` |
| **CA** | Commutativity | set operations, merge, mathematical ops | `f(a,b) == f(b,a)` |
| **CC** | Contract Compliance | non-None return types, documented exceptions | Honors documented contract |
| **SM** | State Mutation | `.append()`, `.update()`, `sort()` on params | Does not mutate input arguments |

### Priority 3: Crash-finding properties (find these last)

Crashes are noisy — they get caught quickly. Test these after exhausting silent-failure properties.

| Code | Type | Signal | Property |
|------|------|--------|----------|
| **BO** | Boundary/Off-by-One | slicing, `range()`, `<` vs `<=`, pagination | Correct at 0, 1, max, max±1 |
| **NP** | None Propagation | `Optional`, `.get()` without None-check, method chains | Handles None gracefully |
| **CO** | Collection Edge Cases | `items[0]`, `max([])`, iteration on empty | Handles empty/single-element collections |
| **CF** | Crash-Free | type-hinted params (use only when above don't apply) | No unhandled exceptions on valid input |

### Rules

- **Classic properties (RT–CF):** mine what code *claims*. Evidence: docstrings, types, names.
- **Bug-pattern properties (FV–SM):** scan code *bodies* for anti-patterns.
- **Never skip framework code.** Models, views, serializers have the most business logic.
- **Scanning order:** (1) framework code, (2) utilities/data transforms, (3) everything else. All three mandatory.

Output: list of (function, property_type, property_description) tuples. Empty list → stop.

---

## Phase 3: Test Generation

### Python (Hypothesis)

Create `pbt_test_<module>.py` in project root. `@given(...)` with constrained strategies, `@settings(max_examples=1000)`, `assume()` for preconditions. For framework code: use conftest from Phase 1, project factories, `RequestFactory`/`TestClient`.

**Strategy constraints:** Read the function's callers and validation. Constrain to realistic input domains. Sound inputs over complete coverage.

### TypeScript (fast-check)

Create `pbt_test_<module>.ts` in project root. `fc.assert(fc.property(...))` with constrained arbitraries, `fc.pre()`, `{ numRuns: 1000 }`.

---

## Phase 4: Execution

Run tests. Python: `pytest pbt_test_*.py -v --tb=short --no-header -q 2>&1`. TypeScript: `npx vitest run pbt_test_*.ts --reporter=verbose 2>&1`. Include conftest files if created. If ALL tests error (not fail): fix imports/syntax, re-run once.

---

## Phase 5: Triage

For each **failing** test (not erroring — failing with a counterexample):

**Gate 1 — Reproducibility:** Write minimal standalone script with the exact counterexample. Run it. Fails consistently? → Gate 2. Flaky? → discard.

**Gate 2 — Legitimacy:** Would this input pass the function's own validation? Is it within the documented domain? Do real callers pass inputs like this? If outside domain → refine strategy (max 2 attempts). All failures disappear → property holds.

**Gate 3 — Impact:** Violates documented behavior → bug. Silent data corruption → bug. Crashes on claimed-valid input → bug. Cosmetic difference → discard.

**Counterexample quality matters.** The most valuable findings are where the function returns a *plausible but wrong* result — not where it crashes. `func(0)` silently returning `func(1)`'s result is more dangerous than `func(None)` throwing. When triage reveals a crash, check: does the same input also produce wrong results at a different code path?

**Bug budget comparison:** If findings are significantly below estimate, re-scan with wider strategies, increase `max_examples` to 5000, apply unused property types. Report gap honestly if it remains.

---

## Phase 6: Reporting

For each confirmed bug, create `bugs/pbt_<target>_<YYYY-MM-DD>_<4char>.md` with: heading, metadata (file:function, severity, type, date), summary, failing input, standalone reproduction script, expected vs actual, suggested fix.

**Severity:** High = incorrect core logic, silent data corruption, security. Medium = crashes on valid input, contract violations. Low = edge cases, documentation mismatches.

---

## Phase 7: Summary

Update `bugs/PBT-REPORT.md` — fill scan metrics, set status "complete", build findings table from all `pbt_*.md` files (sorted by severity, mark new bugs). If no bugs: "No bugs found. All Y properties held across X functions." If budget gap: add Budget Analysis section.

Clean up all `pbt_test_*` and `pbt_conftest_*` files.

### Loop

Read Coverage table. If any module has unapplied property types → back to Phase 2 for uncovered modules. **Keep looping until every module is complete.**

### Phase 7.5: Blocker Resolution

After coverage loop completes, if bug budget gap has resolvable blockers: identify what setup could unlock untestable modules, emit `<pbt-blockers>["id1","id2"]</pbt-blockers>`, ask user about each. User accepts → set up, re-scan unlocked modules. User declines → note it. All resolved → emit `<pbt-complete>DONE</pbt-complete>`.

### Completion

When ALL modules are complete, output: `<pbt-complete>DONE</pbt-complete>`. The hook blocks if the state file disagrees.

**Context exhaustion:** Finish current module, save state, continue. State file preserves progress across sessions.

---

## Rules

- Hunt bugs, not test coverage. Quality of findings over quantity of tests.
- Silent wrong results are more dangerous than crashes. Prioritize accordingly.
- If a function has no testable properties, skip it. Do not force properties.
- If all properties hold, that's a good outcome. Do not manufacture findings.
- Never modify user source code. Only create `pbt_test_*`, `pbt_conftest_*`, and `bugs/` files.
- If venv/node_modules not found, stop and explain. Do not create environments.
