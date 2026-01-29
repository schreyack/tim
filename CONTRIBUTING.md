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

```
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

### Code Style

This repository follows its own standards:

- Python: `ruff` for linting and formatting
- TypeScript: `eslint` + `prettier`
- Markdown: Clear, concise, scannable

### Testing

- Run `pre-commit run --all-files` before submitting
- For shared library changes, run the test suite in `libs/python` or `libs/node`

## Questions?

Open an issue with your question. We're happy to help.
