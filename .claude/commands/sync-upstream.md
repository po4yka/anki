Perform an interactive upstream sync with ankitects/anki.

Steps:

1. Check if the `upstream` remote exists (`git remote -v`). If it does not exist, add it:
   ```
   git remote add upstream https://github.com/ankitects/anki.git
   ```
   Then enable rerere: `git config rerere.enabled true`

2. Fetch upstream: `git fetch upstream`

3. Find the last sync point:
   - Run `git describe --tags --match 'upstream-sync/*' --abbrev=0` to find the last sync tag.
   - If no tag exists, use `git merge-base HEAD upstream/main` as the base.
   - Report the base commit hash and when it was tagged.

4. Count new commits: `git log <base>..upstream/main --oneline | wc -l`
   - If zero new commits, report "Already in sync" and stop.

5. Classify commits by running: `bash scripts/classify-upstream.sh <base>..upstream/main`
   - Present a summary table: RELEVANT / CHECK / SKIP / UNKNOWN counts.

6. Walk through RELEVANT and CHECK commits one by one:
   - Show the commit hash, subject line, and affected files.
   - Show the diff filtered to relevant paths: `git show <hash> -- rslib/ proto/ ftl/ Cargo.toml`
   - Ask the user: Apply / Adapt / Defer / Skip?
   - Record the decision.

7. Apply approved commits:
   - For "Apply": `git cherry-pick <hash>` (resolve any conflicts, then continue).
   - For "Adapt": `git cherry-pick -n <hash>`, then make modifications, then commit.
   - For "Defer" or "Skip": note the hash and reason for the tracking file.

8. After all commits are processed, verify: `cargo check --workspace`
   - If check fails, report the errors and ask the user how to proceed before tagging.

9. If verification passes:
   - Create tag: `git tag upstream-sync/$(date +%Y-%m-%d)`
   - Update `docs/upstream-sync.md` with a new sync entry listing applied, skipped, and deferred commits.

10. Report a final summary: N applied, M skipped, K deferred.

Reference the `fork-sync` skill for classification rules and conflict resolution strategies.
