# Upstream Sync Log

Tracks sync history between this fork (po4yka/anki) and upstream (ankitects/anki).

Upstream remote: `https://github.com/ankitects/anki.git`
Sync script: `scripts/classify-upstream.sh`
Commands: `/sync-upstream` (interactive sync), `/sync-status` (status report)

## Sync Points

Git tags mark sync boundaries: `upstream-sync/YYYY-MM-DD`

---

## Pending Review

No sync has been performed yet. Run `/sync-status` to see what upstream has changed
since the fork diverged, then `/sync-upstream` to begin reviewing commits.

The fork diverged from upstream after the last shared commit in the original
ankitects/anki history. The initial sync will establish the baseline tag
`upstream-sync/initial`.

---

## Sync History

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
