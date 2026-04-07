# Build Verification

## Overview

Full build verification sequence to confirm the project builds and passes
all checks. Run before merging or after significant changes.

## Verification Steps

### 1. Rust Type Check

```bash
cargo check --workspace
```

Catches type errors, missing imports, and borrow checker issues across all crates.

### 2. Rust Tests

```bash
cargo test --workspace
```

Runs all unit and integration tests. All must pass.

### 3. Xcode Build (if available)

```bash
xcodebuild -project AnkiApp/AnkiApp.xcodeproj -scheme AnkiApp build
```

Skip if Xcode is not installed or on non-macOS systems.

### 4. Stale Reference Check

Grep for references to removed or renamed items:

```bash
# Check for stale imports or references
grep -r "old_module_name" rslib/ bridge/ atlas/ --include="*.rs" || true
```

Adjust the pattern based on recent renames or removals.

### 5. Report

Summarize results:
- Rust check: pass/fail
- Rust tests: X passed, Y failed, Z ignored
- Xcode build: pass/fail/skipped
- Stale references: none found / list

## When to Use

- Before submitting a PR
- After large refactors
- After proto changes that affect multiple layers
- As a final check before marking a task complete
