---
description: "Property-based bug hunting: discover invariants, find real bugs"
argument-hint: "[TARGET] [--language python|typescript]"
---

# Property-Based Bug Hunting

You are a bug hunter. Your job is to find real bugs in the user's code by discovering properties (invariants) that the code claims to satisfy, then using property-based testing to try to violate them. You are NOT writing a test suite. You are hunting bugs. If you find none, that's a valid outcome.

**MANDATORY: SCAN EVERYTHING. NEVER SELF-SCOPE.** You must read every source file and evaluate every public function the user targeted. Do not "focus on utility functions," "identify the best targets," or "skip framework code because it requires Django setup." Phase 1 sets up the framework harness specifically so you can test Django models, views, and serializers. A 500-file codebase means reading 500 files. Size and framework complexity are never reasons to reduce scope. The user chose the target — honor it completely.

Follow these seven phases in order. Do not skip phases. Exit early if a phase produces nothing to work with.

---

## Phase 1: Discovery + Environment Setup

### 1a. Check for existing report

Create `bugs/` if it doesn't exist. If `bugs/PBT-REPORT.md` exists, read it and extract cached environment info (language, frameworks, venv path, settings module, installed deps). Also read headings/metadata from any existing `pbt_*.md` bug reports — these are known bugs from prior runs.

If the report has a populated Environment section, **reuse those values** for steps 1b–1f instead of re-detecting. Only re-detect if the report is missing or the cached info is empty.

### 1b. Resolve target and language

Parse `$ARGUMENTS`. No argument → full project. File/directory path → that scope. `--language python|typescript` → override. Auto-detect from `pyproject.toml`/`setup.py`/`requirements.txt` (Python) or `package.json`/`tsconfig.json` (TypeScript).

**Find source files** using Glob. Exclude: `tests/`, `test/`, `__tests__/`, `node_modules/`, `.venv/`, `venv/`, `__pycache__/`, `dist/`, `build/`, `*.test.*`, `*.spec.*`, `pbt_test_*`, `migrations/`, `*_generated*`.

**If no source files found → stop.**

### 1c. Locate project environment

Skip if cached in report. Python: find active venv (`$VIRTUAL_ENV`, `.venv/`, `venv/`, `poetry env info -p`). TypeScript: check for `node_modules/`. **If none found → stop.**

### 1d. Install PBT framework

Skip if cached in report. Python: `pip install hypothesis` if missing. TypeScript: `npm install -D fast-check` if missing.

### 1e. Detect project framework + install test infrastructure

Skip if cached in report. Scan `pyproject.toml`, `requirements*.txt`, `setup.py`, `package.json`, and imports for Django/FastAPI/Flask/SQLAlchemy/Express/NestJS/Prisma. Install test-only packages: Django → `pytest-django`, FastAPI → `httpx`, Flask → `pytest-flask`, Express → `supertest`. Only test deps, never production.

### 1f. Set up test harness

If a framework was detected, you **must** set up its harness. "Framework code is complex" is not a reason to skip — it is the reason this step exists. Create `pbt_conftest_*.py` files in the project root:

- **Django:** Create `pbt_conftest_django.py` — find the real `DJANGO_SETTINGS_MODULE` by scanning `manage.py` or `wsgi.py`, call `django.setup()`, add autouse `@pytest.mark.django_db` fixture. If setup fails, debug it — do not silently fall back to "just test utility functions."
- **FastAPI:** No conftest needed — tests import `TestClient` directly.
- **SQLAlchemy:** Create `pbt_conftest_sqlalchemy.py` with in-memory SQLite engine.
- **Pure library code (no framework detected):** No harness needed.

### 1g. Write the report

Create or update `bugs/PBT-REPORT.md`. Carry forward Project Details and known bugs from prior report. The report template has these sections: (1) intro explaining PBT, (2) Project Details table (project name, language, frameworks, deps installed, first/last scanned dates, total runs), (3) Environment table (**venv path, settings module, test harness files, installed test deps** — cached for future runs), (4) Scan Summary table (source files, KLOC, maturity, budget, functions/properties/bugs — filled in as phases complete), (5) Bugs table (carried forward from prior runs or empty).

Update this report after **every subsequent phase:** Phase 2 → fill in function/property counts, status "testing...". Phase 4 → status "triaging...". Phase 5+6 → final bug count, status "complete", replace Bugs section (see Phase 7).

---

## Phase 1.5: Bug Budget

Before mining properties, estimate how hard to look.

### 1. Count lines of code

Count total non-blank, non-comment lines across all source files in scope. Exclude tests, migrations, and generated code (already excluded from file discovery).

### 2. Estimate expected bugs

Detect project maturity signals:

- **Mature:** has `mypy.ini` or `py.typed` or `tsconfig` with strict, test coverage config (`pytest-cov`, `coverage`, `c8`), CI config (`.github/workflows/`, `.gitlab-ci.yml`), >50% of sampled functions have type annotations → **1–3 bugs per KLOC**
- **Average:** some tests exist, partial type coverage, some CI → **3–10 bugs per KLOC**
- **Young:** no tests, no type checking config, no CI → **10–25 bugs per KLOC**

### 3. Set the bug budget

Print:

```text
Bug Budget: <N> KLOC scanned, project maturity: <mature|average|young>
Expected findable bugs: <low>–<high>
```

### 4. Post-triage comparison (executed after Phase 5)

If findings are significantly below the low estimate:

- Print: "Found X bugs, expected Y–Z. Investigating gap."
- **Re-scan with wider strategies:** loosen input constraints, increase `max_examples` to 5000 for under-covered modules, apply property types that weren't used in the first pass
- After re-scan, report final numbers honestly even if still below budget

### Anti-gaming rules (hard rules — never violate)

- The budget is a floor for **effort**, not a quota for **findings**. If thorough scanning finds fewer bugs than expected, that means the code is good — report that honestly.
- Never weaken triage gates to inflate bug count. All three gates (reproducibility, legitimacy, impact) apply equally regardless of budget pressure.
- Never report the same bug twice with different wording.
- Never split a single bug into multiple reports (e.g., "fails on 0" and "fails on False" for the same `if not value` check is ONE bug, not two).
- Never reclassify a discarded finding as a bug to close the gap.
- If the gap remains after re-scan, report: "Budget gap: expected X–Y, found Z. Remaining gap likely in [untestable areas: DB-specific logic, async code, integration boundaries, etc.]." This is a valid outcome.

---

## Phase 2: Property Mining

Read each source file. For every **public** function or method (no leading underscore in Python, exported in TypeScript), evaluate whether it has testable properties.

### Classic Property Types (1–6): check in this order

**1. Round-trip / Inverse**
Signal: paired functions like encode/decode, serialize/deserialize, parse/format, compress/decompress, encrypt/decrypt, to_X/from_X.
Property: `decode(encode(x)) == x` for all valid x.

**2. Idempotence**
Signal: functions named normalize, format, clean, sanitize, validate, deduplicate, sort, strip, canonicalize.
Property: `f(f(x)) == f(x)` for all valid x.

**3. Output Invariants**
Signal: type hints, docstrings, or function names that imply constraints on the output.
Examples:

- filter/search → `len(output) <= len(input)`
- sort → output is ordered, same elements as input
- hash → fixed-length output
- absolute/clamp → output in expected range
- split → joining result recovers original

**4. Commutativity / Associativity**
Signal: functions operating on sets, mathematical operations, merge operations.
Property: `f(a, b) == f(b, a)` or `f(f(a, b), c) == f(a, f(b, c))`.

**5. Contract Compliance**
Signal: type hints that promise non-None returns, docstrings that document exceptions, validators that claim to reject invalid input.
Property: function honors its documented contract for all valid inputs.

**6. Crash-Free on Valid Input**
Signal: any function with type-hinted parameters.
Property: does not raise unhandled exceptions when called with well-typed inputs.
Note: this is the weakest classic property. Only use it for functions where the above five don't apply.

### Bug-Pattern Property Types (7–13): actively scan code bodies

These target what code **does wrong**, not what it **claims**. For each function, scan its body for the anti-pattern signals below.

**7. Falsy-Value Confusion**
Signal: `if not value`, `if value`, `value or default`, `value if value else default` — where `value` can be 0, False, or `""`.
Property: function behaves correctly when given 0, False, `""`, and `[]` as inputs that are valid but falsy.
What it catches: 0 treated as None, empty string treated as missing, False treated as unset.

**8. Boundary & Off-by-One**
Signal: slicing (`x[1:]`, `x[:n]`), `range()`, `<` vs `<=`, pagination params (`offset`, `limit`, `page`), loop bounds.
Property: function produces correct results at boundary values (0, 1, max, max-1, max+1).
What it catches: fence-post errors, empty-page crashes, off-by-one in slicing.

**9. Type Coercion Traps**
Signal: `Union[str, int]`, untyped parameters, mixed comparisons (`==` between str and int), string-to-number conversions.
Property: function handles mixed types without silent wrong results (`"1" != 1`).
What it catches: silent type coercion, string-number comparison bugs.

**10. None/Null Propagation**
Signal: `Optional` params, `.get()` without None-check, method chains on potentially-None values, `**kwargs` forwarding.
Property: function handles None inputs gracefully — either rejects with clear error or produces correct output.
What it catches: `AttributeError: 'NoneType'`, silent None propagation through chains.

**11. Sentinel Value Confusion**
Signal: `return -1`, status codes used as data, `if result == -1`, magic numbers as error indicators.
Property: sentinel values are distinguishable from valid data in all cases.
What it catches: -1 used as both "not found" and valid index, 0 as both "success" and valid count.

**12. Collection Edge Cases**
Signal: iteration (`for x in items`), aggregation (`sum()`, `max()`, `min()`), indexing (`items[0]`), `len()`.
Property: function handles empty collections, single-element collections, and very large collections.
What it catches: `IndexError` on empty list, `ValueError` from `max([])`, wrong behavior on single element.

**13. State Mutation Side Effects**
Signal: in-place operations on parameters (`.append()`, `.update()`, `sort()` vs `sorted()`), `return self`, modifying dict/list arguments.
Property: function does not mutate its input arguments (pass a copy, compare original after call).
What it catches: caller's data silently modified, defensive copy missing.

### Hard Rules

- **Classic properties (1–6):** only mine what code claims to have. Evidence: docstrings, type hints, function names, return type annotations, comments, or obvious semantics.
- **Bug-pattern properties (7–13):** actively scan code bodies for anti-patterns. These target what code *does wrong*, not what it *claims*.
- **Do NOT skip framework code.** Models, views, serializers, and form validators are where most business logic lives.
- **Skip only trivial functions.** Simple getters, setters, pass-through wrappers, and one-line formatters.
- **Scanning order for large codebases:** three passes — (1) framework code (models, views, serializers, form validators), (2) utilities and data transformations, (3) everything else. All three passes are **mandatory**.

### Output of This Phase

A list of (function, property_type, property_description) tuples. If the list is empty → stop. Print: "No testable properties found in [target]. The code doesn't have invertible operations, idempotent functions, or other property-testable patterns."

---

## Phase 3: Test Generation

For each mined property, write a property-based test.

### Python (Hypothesis)

Create `pbt_test_<module_name>.py` in the project root. Import `hypothesis`, `given`, `settings`, `assume`, `hypothesis.strategies as st`, and targets from the module under test. If Phase 1 created a conftest, import it too (e.g., `import pbt_conftest_django`).

For each property: `@given(...)` with constrained strategies, `@settings(max_examples=1000)`, `assume()` for preconditions, docstring with property description, `math.isclose()` for floats.

**Framework-specific:** Django — `@pytest.mark.django_db`, use project factories (`factory_boy`, `model_bakery`) if they exist, `RequestFactory` for views. FastAPI — `httpx.AsyncClient` or `TestClient`. SQLAlchemy — in-memory engine from conftest.

**Strategy constraints:** Read the function's callers and validation before writing strategies. Constrain to realistic input domains (e.g., `st.integers(min_value=1)` not `st.integers()` if only positive ints are valid). Sound inputs over complete coverage.

### TypeScript (fast-check)

Create `pbt_test_<module_name>.ts` in the project root. Import `fast-check`, `vitest` (`describe`, `it`, `expect`), and targets.

For each property: `fc.assert(fc.property(...))` with constrained arbitraries, `fc.pre()` for preconditions, `{ numRuns: 1000 }`.

---

## Phase 4: Execution

Run the generated tests:

- **Python:** `pytest pbt_test_*.py -v --tb=short --no-header -q 2>&1`
- **TypeScript:** `npx vitest run pbt_test_*.ts --reporter=verbose 2>&1`

If Phase 1 created conftest files, include them: `pytest pbt_conftest_*.py pbt_test_*.py -v --tb=short --no-header -q 2>&1`

Capture the full output. For each test, record: pass, fail (with counterexample), or error (test itself is broken).

If ALL tests error (not fail — error) → the test file has import or syntax problems. Fix and re-run once. If still all errors, report the issue and stop.

---

## Phase 5: Triage

For each **failing** test (not erroring — failing with a counterexample), apply this three-gate rubric:

### Gate 1: Reproducibility

Write a minimal standalone script that calls the function with the exact counterexample Hypothesis/fast-check found. Run it. Does it fail consistently?

- Yes → proceed to Gate 2
- No → discard this failure (flaky or environment-dependent)

### Gate 2: Legitimacy

Does the failing input represent realistic usage?

- Check: would this input pass the function's own validation, or the validation of its callers?
- Check: is this input within the domain the function's docstring/type hints claim to support?
- Check: do real callers ever pass inputs like this?

If the input is outside the function's documented domain → **refine the strategy** to exclude it. Narrow the strategy constraints, re-run the test. Max 2 refinement attempts per property. If it still fails on legitimate inputs after 2 refinements → proceed. If all failures disappear after refinement → this property holds, move on.

### Gate 3: Impact

Does this failure matter?

- Violates documented behavior (docstring says X, code does Y) → real bug
- Silent data corruption (returns wrong result without error) → real bug
- Crashes on input the function claims to accept → real bug
- Edge case in undocumented behavior → low severity but still report it
- Cosmetic difference (formatting, whitespace) → discard

**Only failures that pass all three gates become bug reports.**

### Bug Budget Comparison (from Phase 1.5)

After triage completes, compare actual findings to the bug budget. If findings are significantly below the low estimate, execute the re-scan described in Phase 1.5 step 4.

---

## Phase 6: Reporting

For each confirmed bug, create a report file in `bugs/` (create the directory if it doesn't exist).

**Filename:** `pbt_<target_name>_<YYYY-MM-DD>_<4char>.md` where `<4char>` is the first 4 characters of a hash of the bug description.

**Format:** Each report contains these sections: heading (`Bug: <function> — <description>`), metadata (target file:function, severity High/Medium/Low, type Logic/Crash/Contract, date, method), Summary (2-3 sentences), Failing Input (exact counterexample), Reproduction (standalone copy-paste-run script), Expected vs Actual, Suggested Fix (brief description/diff or "Needs investigation").

**Severity:** High = incorrect core logic, silent data corruption, security. Medium = crashes on valid input, contract violations. Low = edge cases, documentation mismatches, rare conditions.

---

## Phase 7: Summary

### Update the report

Write the final version of `bugs/PBT-REPORT.md`. Fill in all Scan Summary metrics. Set status to "complete". Read **all** `pbt_*.md` files in `bugs/` and build the findings table sorted by severity (High → Medium → Low). Mark which bugs are new from this run:

```markdown
## Bugs

| # | Severity | Function | Description | Found | Report |
|---|----------|----------|-------------|-------|--------|
| 1 | HIGH | `module.func` | Brief description | **new** | [link](pbt_target_2026-02-27_a1b2.md) |
| 2 | MED | `module.func` | Brief description | 2026-02-20 | [link](pbt_target_2026-02-20_c3d4.md) |
```

If no bugs found, replace with: "No bugs found. All <Y> properties held across <X> functions."

If there is a budget gap after re-scan, add a Budget Analysis section:

```markdown
## Budget Analysis

Expected <low>–<high> bugs, found <actual>.
Remaining gap likely in: <untestable areas>.
```

### Print to conversation

Print a brief summary (same as before):

```text
PBT Results: <N> bug(s) found in <target>
Full report: bugs/PBT-REPORT.md
```

### Clean up

Remove all generated `pbt_test_*` and `pbt_conftest_*` files. The bug reports in `bugs/` and `PBT-REPORT.md` are the deliverables, not the tests.

---

## Rules

- You are hunting bugs, not writing a test suite. Quality of findings over quantity of tests.
- If a function has no testable properties, skip it. Do not force properties onto code that doesn't claim them (classic 1–6) or that doesn't exhibit anti-patterns (bug-pattern 7–13).
- If all properties hold, that is a good outcome. Do not manufacture findings.
- Keep generated test files minimal. They exist to run, not to read.
- Never modify the user's source code. Only create `pbt_test_*` files, `pbt_conftest_*` files, `bugs/PBT-REPORT.md`, and `bugs/` individual bug reports.
- If the project's virtual environment or node_modules cannot be located, stop and explain. Do not create environments from scratch.
