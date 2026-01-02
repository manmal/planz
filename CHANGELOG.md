# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-01-02

### Added

- Initial release
- Hierarchical plan management with up to 4 levels of nesting
- Stable node IDs (per-plan auto-increment)
- Path-based node addressing (`"Phase 1/Task A"`) and ID-based (`#5`)
- Cascading done/undone status updates
- Refine command to expand leaf nodes into subtrees
- Multiple output formats: text, JSON, XML, Markdown
- SQLite backend with WAL mode for concurrent access
- Project-scoped plans (tied to working directory)
- Comprehensive test suite (173 tests)
- CI/CD with builds for Linux (x86_64, aarch64) and macOS (x86_64, aarch64)

[unreleased]: https://github.com/manmal/planz/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/manmal/planz/releases/tag/v0.1.0
