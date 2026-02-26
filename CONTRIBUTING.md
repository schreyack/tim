# Contributing to TIM Standards

Thank you for your interest in contributing to TIM Standards. This project gets better with real-world usage and feedback.

## How to Contribute

### Reporting Issues

- Use [GitHub Issues](https://github.com/schreyack/tim/issues) to report bugs or suggest improvements
- Search existing issues before creating a new one
- Include enough detail for others to understand and reproduce the issue

### Submitting Changes

1. Fork the repository
2. Create a branch for your changes (`git checkout -b feature/your-feature`)
3. Make your changes following the standards in this repository
4. Test your changes
5. Commit with conventional commit messages (see below)
6. Push to your fork and submit a pull request

### Commit Message Format

Use [Conventional Commits](https://www.conventionalcommits.org/):

```text
feat: add user authentication standard
fix: correct migration rollback example
docs: clarify coverage requirements
refactor: simplify pre-commit configuration
```

Types: `feat`, `fix`, `docs`, `refactor`, `test`, `chore`

### What We're Looking For

- **New patterns** that AI keeps hallucinating incorrectly
- **Gaps in standards** you discovered in real projects
- **Improved enforcement** tools or hooks
- **Better documentation** and examples
- **Bug fixes** in shared libraries or templates
- **Plugin improvements** for Tim Loop, Tim PBT, or Tim E2E

### Project Structure

| Directory | What Goes Here |
|-----------|----------------|
| `standards/` | Standards documentation (coding, testing, security, deployment, enforcement) |
| `libs/` | Shared libraries — `python/` (tim-lib), `node/` (@tim/lib), `bash/` (tim-common.sh) |
| `marketplace/plugins/` | Claude Code plugins — `tim-loop/`, `tim-pbt/`, `tim-e2e/` |
| `templates/` | Ready-to-copy configs for new projects |
| `tools/` | Enforcement and compliance tools |
| `bin/` | Core CLI scripts (`sync-claude-md`, `sync-pre-commit`, `tim-sync`, etc.) |
| `examples/` | Reference implementations (Python/FastAPI, Node.js/Express) |

### Code Style

This repository follows its own standards:

- Python: `ruff` for linting and formatting
- TypeScript: `eslint` + `prettier`
- Bash: shellcheck-compliant, source `tim-common.sh` for shared utilities
- Markdown: Clear, concise, scannable

### Testing

- Run `pre-commit run --all-files` before submitting
- For shared library changes, run the test suite in `libs/python` or `libs/node`
- For tim-loop changes, run the tests in `marketplace/plugins/tim-loop/scripts/`

## Questions?

Open an issue with your question. We're happy to help.
