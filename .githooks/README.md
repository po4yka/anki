# Git Hooks

This directory contains git hooks for the Anki project.

## Setup

Configure git to use this hooks directory:

```bash
git config core.hooksPath .githooks
```

## Available Hooks

### pre-commit

Runs before each commit:

1. `cargo fmt --all -- --check` -- ensures Rust code is formatted
2. `cargo clippy --workspace -- -D warnings` -- catches lint warnings
3. `swiftlint` (if installed) -- checks Swift style (non-blocking)

## Bypass

To skip hooks for a single commit:

```bash
SKIP_HOOKS=1 git commit -m "your message"
```
