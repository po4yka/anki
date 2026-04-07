Report the current upstream sync status (read-only, no changes made).

Steps:

1. Check if the `upstream` remote exists (`git remote -v`).
   - If it does not exist, report: "upstream remote not configured — run /sync-upstream to set it up."
   - Stop here if no remote.

2. Fetch upstream silently: `git fetch upstream --quiet`

3. Find the last sync point:
   - Run `git describe --tags --match 'upstream-sync/*' --abbrev=0 2>/dev/null`
   - If no tag found, report "No sync history found — this is the first sync."
   - Show the tag name and the date it was created.

4. Count commits since last sync:
   ```
   git log <last-tag>..upstream/main --oneline | wc -l
   ```
   - If zero, report "Up to date with upstream" and stop.

5. Run the classifier: `bash scripts/classify-upstream.sh <last-tag>..upstream/main`

6. Report a summary table:
   ```
   Upstream commits since last sync: N
   ┌──────────┬───────┐
   │ Category │ Count │
   ├──────────┼───────┤
   │ RELEVANT │   X   │
   │ CHECK    │   Y   │
   │ SKIP     │   Z   │
   │ UNKNOWN  │   W   │
   └──────────┴───────┘
   ```

7. List all RELEVANT commits with their hash and subject:
   ```
   RELEVANT commits to review:
     abc1234  Fix scheduler interval calculation (rslib/scheduler/)
     def5678  Add new proto field for deck options (proto/anki/)
   ```

8. List CHECK commits (dependency or build changes):
   ```
   CHECK commits (dependency/build changes):
     ghi9012  Bump serde to 1.0.200
   ```

9. If there are UNKNOWN commits, list them for manual triage.

10. Suggest next action: "Run /sync-upstream to begin the sync process."
