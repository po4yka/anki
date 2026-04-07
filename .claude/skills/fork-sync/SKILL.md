# Fork Sync

## Overview

Workflow for syncing this fork (po4yka/anki) with upstream (ankitects/anki).
This fork replaces the Python/Qt/Svelte UI with SwiftUI + Rust. The Rust core
(`rslib/`), protobuf API (`proto/`), and translations (`ftl/`) are shared with
upstream and must be kept in sync. Atlas crates (`atlas/`) and the Swift bridge
(`bridge/`) are fork-only additions.

Upstream: `https://github.com/ankitects/anki.git`
Tracking: `docs/upstream-sync.md` and git tags `upstream-sync/YYYY-MM-DD`

---

## Path Classification

Every upstream commit falls into one of four categories based on the files it touches:

| Category | Paths | Action |
|----------|-------|--------|
| **RELEVANT** | `rslib/`, `proto/`, `ftl/`, root `Cargo.toml` | Review and apply |
| **CHECK** | `Cargo.lock`, `.cargo/`, root `build.rs` | Review for dependency changes |
| **SKIP** | `qt/`, `pylib/`, `ts/`, `web/`, `aqt/`, `pip/`, `python/`, `node_modules/` | Discard |
| **UNKNOWN** | Everything else | Manual triage |

A commit touching both RELEVANT and SKIP paths is **RELEVANT** — the relevant
files must be reviewed even if most of the commit is UI-only.

### Sub-classification for RELEVANT commits

Within `rslib/`, prioritize by module:

- `scheduler/` -- high priority; core algorithm changes affect card quality
- `sync/` -- relevant if keeping the embedded sync server (we are)
- `storage/` -- high priority; SQLite schema changes affect persistence
- `search/` -- relevant; shared query engine
- `i18n/` -- low risk; translation string additions
- `browser/`, `importing/` -- review individually; may have UI coupling

---

## Setup (one-time)

```bash
# Add upstream remote
git remote add upstream https://github.com/ankitects/anki.git

# Enable conflict resolution memory
git config rerere.enabled true

# Establish initial sync tag at current fork divergence point
# Find the last shared commit before fork divergence:
git log --oneline | tail -20   # find the upstream base commit
git tag upstream-sync/initial <that-commit-hash>
```

---

## Sync Workflow

### Step 1: Fetch upstream

```bash
git fetch upstream
```

### Step 2: Find last sync point

```bash
# Get the last sync tag
git describe --tags --match 'upstream-sync/*' --abbrev=0

# List all commits since that tag
git log <last-tag>..upstream/main --oneline
```

### Step 3: Classify commits

```bash
bash scripts/classify-upstream.sh
# or with explicit range:
bash scripts/classify-upstream.sh <last-tag>..upstream/main
```

Output format:
```
RELEVANT  abc1234567  Fix scheduler interval calculation
CHECK     def8901234  Bump serde to 1.0.200
SKIP      ghi5678901  Update Qt theme colors
UNKNOWN   jkl2345678  Update CI configuration
```

### Step 4: Review RELEVANT commits

For each RELEVANT commit, inspect the diff:

```bash
git show <hash> -- rslib/ proto/ ftl/ Cargo.toml
```

Decision for each commit:
- **Apply** -- cherry-pick immediately
- **Adapt** -- cherry-pick with modifications (e.g., strip UI parts, adjust imports)
- **Defer** -- record in tracking file, skip for now
- **Discard** -- upstream change conflicts with fork architecture

### Step 5: Apply approved commits

```bash
# Single commit
git cherry-pick <hash>

# Multiple commits without auto-committing (review staged diff first)
git cherry-pick -n <hash1> <hash2> <hash3>
git diff --cached
git commit -m "Sync: <description> (upstream <hash>)"

# If cherry-pick hits conflicts
git cherry-pick --continue   # after resolving
git cherry-pick --skip       # skip this commit
git cherry-pick --abort      # abort the whole operation
```

For CHECK commits (dependency updates), apply to root `Cargo.toml` and run:

```bash
cargo check --workspace
```

### Step 6: Verify

```bash
cargo check --workspace
cargo test --workspace
```

### Step 7: Record the sync

```bash
# Tag the sync point
git tag upstream-sync/$(date +%Y-%m-%d)

# Update the tracking file
# Edit docs/upstream-sync.md: move DEFERRED items, add APPLIED/SKIPPED entries
```

---

## Conflict Resolution

### Cargo.toml conflicts

Upstream modifies dependencies; this fork adds workspace members (`atlas/`, `bridge/`, `bins/`).

Resolution strategy:
1. Accept upstream's `[dependencies]` and `[workspace.members]` changes
2. Re-add fork-specific workspace members: `atlas/*`, `bridge`, `bins/*`
3. Verify: `cargo check --workspace`

### proto/ conflicts

This fork does not extend upstream proto messages (use wrapper messages instead).
Conflicts here indicate upstream added fields — accept upstream's additions.

If field numbers clash, upstream's field numbers take precedence. Never reassign
upstream field numbers; renumber fork extensions if needed (using 1000+ range).

### rslib/ conflicts

This fork minimizes direct changes to `rslib/`. Conflicts typically mean:
- An upstream refactor touched a file where we added atlas integration hooks
- Resolution: accept upstream's structural changes, re-apply our additions

Keep atlas integration in thin adapter layers (`atlas/src/adapters/`) rather
than modifying rslib files to minimize future conflict surface.

---

## Tracking

All sync activity is recorded in `docs/upstream-sync.md`:

```markdown
## Sync YYYY-MM-DD
Upstream ref: ankitects/anki@<hash>

### Applied
- `abc123` Fix scheduler interval calculation

### Skipped
- `def456` Update Qt theme (UI-only)

### Deferred
- `ghi789` New proto field for deck options — needs bridge update
```

Git tags mark sync boundaries: `upstream-sync/YYYY-MM-DD`

---

## When to Use

- Periodically (weekly/biweekly) to stay current with upstream bug fixes
- Before starting work on a shared component (`rslib/`, `proto/`)
- When upstream fixes a scheduler or storage bug affecting card quality
- When upstream adds new proto fields needed for planned features
- Run `/sync-status` first to assess the volume before committing to a full sync
