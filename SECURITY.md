# Security Policy

## Reporting a Vulnerability

If you discover a security vulnerability in TIM Standards, please report it responsibly.

**Do not open a public issue for security vulnerabilities.**

Instead:

1. Email the maintainer directly (see GitHub profile for contact)
2. Or use GitHub's private vulnerability reporting if available

Include:

- Description of the vulnerability
- Steps to reproduce
- Potential impact
- Any suggested fixes (optional)

## Response Timeline

- **Acknowledgment**: Within 48 hours
- **Initial assessment**: Within 1 week
- **Resolution**: Depends on severity and complexity

## Scope

This security policy applies to:

- The TIM Standards documentation and templates
- The shared libraries (`tim-lib` for Python, `@tim/lib` for Node.js, `tim-common.sh` for Bash)
- All marketplace plugins: Tim Loop (task completion), Tim PBT (property-based testing), Tim E2E (E2E testing)
- The plan-ops CLI and enforcement tools (`tim-sync`, `tim-lock-enforcement`, `git-guard`)
- Example implementations

## What to Report

- Security vulnerabilities in shared library code
- Secrets accidentally committed to the repository
- Insecure defaults in templates or examples
- Documentation that encourages insecure practices

## What Not to Report

- Vulnerabilities in dependencies (report to upstream maintainers)
- Security issues in your own projects using TIM standards
- General security questions (use GitHub Discussions or Issues)

## Recognition

We appreciate responsible disclosure. Contributors who report valid security issues will be acknowledged in the fix commit (unless they prefer to remain anonymous).
