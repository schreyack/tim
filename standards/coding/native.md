# Native (C++/Swift) Coding Standards

All TIM native projects must follow these standards. Violations block commits and merges.

These cover native desktop applications — C++17/20 and Swift/SwiftUI, with optional
Python tooling. No backend, no k3s, no remote-first deploy. For the Python portions of a
native project, [python.md](python.md) applies in full.

## Stack Requirements

- **C++**: C++17/20
- **Swift**: 5.9+ / SwiftUI
- **Toolchain**: LLVM/clang **≥ 20** (required for RealtimeSanitizer)
- **C++ build**: CMake (with `compile_commands.json` for clang-tidy)
- **Swift packaging**: Swift Package Manager (`Package.swift`)
- **Python (optional)**: per [python.md](python.md); often unpackaged (no `pyproject.toml`)

## Strict Builds (the "100% type safety" analogue)

There is no `mypy --strict` for C++/Swift; the equivalent is treating all warnings as errors.

- **C++**: compile with `-Werror` and a strict warning set; `clang-tidy --warnings-as-errors=*`.
- **Swift**: `swiftc` warnings-as-errors and strict concurrency checking.
- **Python**: `mypy --strict`, zero warnings (see [python.md](python.md)).

## Formatting and Linting (Gate 1)

Each language runs a formatter **and** a linter — the same split Python uses (`ruff-format` + `ruff`):

| Language | Formatter | Linter | Config |
|----------|-----------|--------|--------|
| C++ | `clang-format` | `clang-tidy` | `.clang-format`, `.clang-tidy` |
| Swift | `swift-format` | `swiftlint --strict` | `.swiftlint.yml` |
| Python | `ruff-format` | `ruff` | `pyproject.toml` / overrides |

These run via the `native` pre-commit template
([templates/native/.pre-commit-config.yaml](../../templates/native/.pre-commit-config.yaml)).
clang-format and swift-format auto-fix in place — re-stage and re-commit when they do.

## Size and Complexity Thresholds

The standard thresholds apply to C++/Swift exactly as to every other language:

- **Files**: 500 lines max
- **Functions**: 50 lines max
- **Cyclomatic complexity**: 10 max

Enforcement is split by what each tool can see (mirroring "ESLint owns TS complexity"):

- **File size** — `tools/check-code-quality.py --language native` (language-agnostic line count).
- **Function size / complexity** — owned by the language linter:
  - C++: `clang-tidy` (`readability-function-size`, `readability-function-cognitive-complexity`).
  - Swift: `swiftlint` (`function_body_length`, `cyclomatic_complexity`).
  - Python: full AST check in `check-code-quality.py`.

Native projects MUST ship a `.clang-tidy` and `.swiftlint.yml` that encode the 50-line /
complexity-10 rules.

## Banned Patterns

- No `TODO`/`FIXME`/`XXX` comments.
- No placeholder implementations (`fatalError("unimplemented")`, `NotImplementedError`,
  `// TODO: implement`).
- No print debugging (`std::cout`/`print` for diagnostics) — use the project logger (`spdlog`).
- No silent fallbacks — if an operation fails, the caller must know (see CLAUDE.md).

## Real-Time Audio Safety

For audio projects, **RealtimeSanitizer (RTSan)** proves the audio callback performs no
allocation, locking, or syscalls, and **AddressSanitizer (ASan)** covers the lock-free
handoff. Both require LLVM/clang ≥ 20.

This is currently a **project-local gate, not a TIM-blessed standard** — there is one audio
project today, and a net-new gate *kind* shouldn't be standardized for an N-of-1 case.
Register it in `.tim-patterns.yaml` as a `CUSTOM` `realtime_audio_safety` pattern (see the
[native patterns template](../../templates/tim-patterns.native.yaml.template)). Revisit
promoting it to a TIM standard if a second audio project appears.

## Pattern Registry

Register significant libraries in `.tim-patterns.yaml`. `check-pattern-drift.py` parses CMake
(`find_package`, `FetchContent`), `Package.swift`, and `Package.resolved` dependencies and
cross-checks them against the registry via the `native` section of
[pattern-library-map.yaml](../../tools/pattern-library-map.yaml). Common categories:
`audio_framework`, `audio_io`, `audio_file_io`, `dsp_fft`, `plugin_format`, `serialization`,
`logging`. Start from [tim-patterns.native.yaml.template](../../templates/tim-patterns.native.yaml.template).

## Gates for Native Projects

See [enforcement/gates.md](../enforcement/gates.md) for the full model. How each gate maps:

- **Gate 1 (Local / pre-commit)** — clang-format/clang-tidy, swift-format/swiftlint, Python
  gates, secrets, hygiene, size/complexity. Full coverage.
- **Gate 2 (CI)** — TIM does **not** standardize a billable GitHub-hosted macOS runner lane.
  Native CI (and AU plugin-hosting tests, which need plugins installed) gate **local/manual**.
- **Gate 3 (Deploy)** — **not applicable**. A desktop app has no remote-first deploy; the
  `native-app` profile treats release as **build → code-sign → notarize**, outside `ops.sh`.
- **Gate 4 (Pattern compliance)** — `.tim-patterns.yaml` + pattern-drift, as above.

## Project Structure

A typical native project:

```text
project/
├── CMakeLists.txt          # C++ build (root manifest → detected as `native`)
├── .clang-format
├── .clang-tidy             # readability-function-size, cognitive-complexity
├── .swiftlint.yml          # function_body_length, cyclomatic_complexity
├── engine/                 # C++ sources
├── native/<App>/           # Swift / SwiftUI (Package.swift)
├── core/ transport/ ...    # optional Python (see python.md)
├── .tim-patterns.yaml      # from tim-patterns.native.yaml.template
└── .pre-commit-config.yaml # generated from templates/native (locked)
```
