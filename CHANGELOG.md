# Changelog

All notable changes to this project will be documented in this file.

The format is based on Keep a Changelog,
and this project follows Semantic Versioning.

## [Unreleased]

## [0.3.0] - 2026-05-14

### Added

- **Hidden commands** — `Command.new` now accepts a `hidden : Bool` keyword argument (default `false`). Hidden commands are omitted from all help listings but remain fully callable by name. Useful for internal or escape-hatch commands that should not be advertised to end users.

## [0.2.0]

### Added

- **Command aliases** — `Command.new` now accepts an `aliases : Array(String)` keyword argument. Each alias is registered in the parent's routing table alongside the canonical name, so `argy b` dispatches identically to `argy build`. Aliases are displayed inline in help output (e.g. `build, b, bld`).

### Changed

- Expanded command/help edge-case coverage.
