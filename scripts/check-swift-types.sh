#!/usr/bin/env bash
# Check that Swift Atlas DTOs match Rust surface-contracts types.
# Usage: ./scripts/check-swift-types.sh

set -euo pipefail

SWIFT_FILE="AnkiApp/AnkiApp/AnkiApp/Bridge/AtlasDTOs.swift"
RUST_DIR="atlas/surface-contracts/src"

echo "Checking Swift-Rust type sync..."
echo

# Extract Swift struct/enum names
if [ ! -f "$SWIFT_FILE" ]; then
    echo "Warning: $SWIFT_FILE not found, skipping check"
    exit 0
fi

swift_types=$(grep -E '^\s*(struct|enum|class)\s+\w+' "$SWIFT_FILE" \
    | grep -v 'CodingKeys' \
    | sed -E 's/^[[:space:]]*(struct|enum|class)[[:space:]]+([A-Za-z_][A-Za-z0-9_]*).*$/\2/' \
    | sort -u)

# Extract Rust pub struct/enum names from surface-contracts
if [ ! -d "$RUST_DIR" ]; then
    echo "Warning: $RUST_DIR not found, skipping check"
    exit 0
fi

rust_types=$(grep -rE '^\s*pub\s+(struct|enum)\s+\w+' "$RUST_DIR" \
    | sed -E 's/^[^:]*:[[:space:]]*pub[[:space:]]+(struct|enum)[[:space:]]+([A-Za-z_][A-Za-z0-9_]*).*$/\2/' \
    | sort -u)

echo "Swift types ($(echo "$swift_types" | wc -l | tr -d ' ')):"
echo "$swift_types" | sed 's/^/  /'
echo
echo "Rust surface-contracts types ($(echo "$rust_types" | wc -l | tr -d ' ')):"
echo "$rust_types" | sed 's/^/  /'
echo

# Find Swift types that don't have a Rust counterpart
missing_in_rust=""
while IFS= read -r type; do
    if ! echo "$rust_types" | grep -qw "$type"; then
        missing_in_rust="${missing_in_rust}  $type\n"
    fi
done <<< "$swift_types"

# Find Rust types that don't have a Swift counterpart
missing_in_swift=""
while IFS= read -r type; do
    if ! echo "$swift_types" | grep -qw "$type"; then
        missing_in_swift="${missing_in_swift}  $type\n"
    fi
done <<< "$rust_types"

has_issues=0

if [ -n "$missing_in_rust" ]; then
    echo "Swift types WITHOUT Rust counterpart (may be Swift-only):"
    echo -e "$missing_in_rust"
    has_issues=1
fi

if [ -n "$missing_in_swift" ]; then
    echo "Rust types WITHOUT Swift counterpart (may need DTO):"
    echo -e "$missing_in_swift"
    has_issues=1
fi

if [ $has_issues -eq 0 ]; then
    echo "All types are in sync."
fi

echo "Note: This is a name-based check only. Field-level drift requires manual review."
echo "See docs/SWIFT_TYPES.md for the full mapping reference."
