# Upstream Sync Log

Tracks sync history between this fork (po4yka/anki) and upstream (ankitects/anki).

Upstream remote: `https://github.com/ankitects/anki.git`
Sync script: `scripts/classify-upstream.sh`
Commands: `/sync-upstream` (interactive sync), `/sync-status` (status report)

## Sync Points

Git tags mark sync boundaries: `upstream-sync/YYYY-MM-DD`

---

## Sync History

## Sync 2026-04-07
Upstream ref: ankitects/anki@64386cab63 (upstream/main as of 2026-04-07)
Divergence base: 922953acf4638435b5daf5c6657eacaa957c72e6 (2026-04-03)
Tag: upstream-sync/2026-04-07

### Applied
_(none — no commits touched rslib/, proto/, ftl/, or root Cargo.toml)_

### Skipped
- `c7679305` Add a standardized pull request template (#4655) (reason: GitHub infra only, `.github/pull_request_template.md`)
- `447795bbb` Add pre-commit for automated pre-push checks (#4660) (reason: upstream uses Python/ninja toolchain; fork uses `.githooks/`)
- `64386cab6` fix: clipboard image paste produces [sound:] tag instead of `<img>` (#4668) (reason: `qt/aqt/editor.py` — Python/Qt UI, stripped from this fork)

---

<!-- Entries added here after each sync, newest first. Format:

## Sync YYYY-MM-DD
Upstream ref: ankitects/anki@<full-hash>
Tag: upstream-sync/YYYY-MM-DD

### Applied
- `abc1234` Subject line (paths: rslib/scheduler/)

### Adapted
- `def5678` Subject line — stripped UI portion, kept scheduler logic

### Skipped
- `ghi9012` Subject line (reason: UI-only change)

### Deferred
- `jkl3456` Subject line (reason: needs bridge/ update first, see TODO.md)

-->
