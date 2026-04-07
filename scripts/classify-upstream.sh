#!/usr/bin/env bash
# classify-upstream.sh
# Classify upstream commits by the paths they touch.
#
# Usage:
#   bash scripts/classify-upstream.sh [git-range]
#
# If no range is given, defaults to last upstream-sync/* tag..upstream/main.
#
# Output format (one line per commit):
#   CATEGORY  short-hash  commit subject
#
# Categories:
#   RELEVANT  rslib/, proto/, ftl/, root Cargo.toml — must review
#   CHECK     Cargo.lock, .cargo/, build.rs — review for dep changes
#   SKIP      qt/, pylib/, ts/, web/, aqt/, pip/, python/ — discard
#   UNKNOWN   everything else — manual triage

set -euo pipefail

# Determine the git range
if [ $# -ge 1 ]; then
    RANGE="$1"
else
    LAST_TAG=$(git describe --tags --match 'upstream-sync/*' --abbrev=0 2>/dev/null || true)
    if [ -z "$LAST_TAG" ]; then
        BASE=$(git merge-base HEAD upstream/main 2>/dev/null || true)
        if [ -z "$BASE" ]; then
            echo "Error: no upstream-sync/* tag found and upstream/main not reachable." >&2
            echo "Run: git fetch upstream" >&2
            exit 1
        fi
        RANGE="${BASE}..upstream/main"
    else
        RANGE="${LAST_TAG}..upstream/main"
    fi
fi

# Count commits
TOTAL=$(git log "$RANGE" --format="%H" 2>/dev/null | wc -l | tr -d ' ')
if [ "$TOTAL" -eq 0 ]; then
    echo "No commits in range: $RANGE"
    exit 0
fi

echo "Classifying $TOTAL commits in range: $RANGE"
echo ""

# Process each commit
git log "$RANGE" --format="%H %s" | while IFS=' ' read -r hash subject; do
    short="${hash:0:10}"
    files=$(git diff-tree --no-commit-id --name-only -r "$hash" 2>/dev/null || echo "")

    if [ -z "$files" ]; then
        printf "UNKNOWN   %s  %s\n" "$short" "$subject"
        continue
    fi

    # Count files per category
    has_relevant=$(echo "$files" | grep -cE '^(rslib/|proto/|ftl/)' || true)
    has_cargo_toml=$(echo "$files" | grep -cxF 'Cargo.toml' || true)
    has_check=$(echo "$files" | grep -cE '^(Cargo\.lock$|\.cargo/|build\.rs$)' || true)
    # SKIP: removed UI stacks + GitHub/Python/CI infra that is irrelevant to this fork
    has_skip=$(echo "$files" | grep -cE \
        '^(qt/|pylib/|ts/|web/|aqt/|pip/|python/|node_modules/|design/|ankidroid/|ankiweb/|tools/|\.github/|\.pre-commit-config\.yaml$|pyproject\.toml$|uv\.lock$|CONTRIBUTORS$|README\.md$|CHANGELOG\.md$|CHANGELOG$|ninja$|ninja\.bat$|Makefile$|\.vale\.ini$|\.editorconfig$|\.gitattributes$|docs/contributing\.md$|docs/development\.md$)' \
        || true)
    total_files=$(echo "$files" | wc -l | tr -d ' ')

    if [ "$has_relevant" -gt 0 ] || [ "$has_cargo_toml" -gt 0 ]; then
        printf "RELEVANT  %s  %s\n" "$short" "$subject"
    elif [ "$has_check" -gt 0 ]; then
        printf "CHECK     %s  %s\n" "$short" "$subject"
    elif [ "$has_skip" -gt 0 ] && [ "$has_skip" -eq "$total_files" ]; then
        printf "SKIP      %s  %s\n" "$short" "$subject"
    else
        printf "UNKNOWN   %s  %s\n" "$short" "$subject"
    fi
done
