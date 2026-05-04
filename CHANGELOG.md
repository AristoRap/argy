# Changelog

All notable changes to this project will be documented in this file.

The format is based on Keep a Changelog,
and this project follows Semantic Versioning.

## [Unreleased]

### Added

- **Command aliases** — `Command.new` now accepts an `aliases : Array(String)` keyword argument. Each alias is registered in the parent's routing table alongside the canonical name, so `argy b` dispatches identically to `argy build`. Aliases are displayed inline in help output (e.g. `build, b, bld`).

### Changed

- Expanded command/help edge-case coverage.
