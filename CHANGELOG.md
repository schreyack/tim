# Changelog

All notable changes to TIM Design Standards will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
- Initial release of TIM Design Standards
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
