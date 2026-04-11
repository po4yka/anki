#!/usr/bin/env bash
# audit.sh -- Code quality audit for Rust, Swift, and Proto layers.
# Usage: ./scripts/audit.sh

set -euo pipefail

PASS=0
WARN=0
FAIL=0

section() { echo -e "\n=== $1 ==="; }
pass()    { echo "  PASS: $1"; PASS=$((PASS + 1)); }
warn()    { echo "  WARN: $1"; WARN=$((WARN + 1)); }
fail()    { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

# --- Rust checks ---
section "Rust"

# Legacy baseline for production unwrap/expect usage in rslib/src after
# excluding dedicated test files and #[cfg(test)] modules. The audit should
# flag regressions instead of re-warn on the same known debt every run.
LEGACY_RSLIB_UNWRAP_BASELINE=363
LEGACY_RSLIB_EXPECT_BASELINE=15

if cargo fmt --all -- --check >/dev/null 2>&1; then
    pass "cargo fmt clean"
else
    fail "cargo fmt found formatting issues"
fi

if cargo clippy --workspace -- -D warnings >/dev/null 2>&1; then
    pass "cargo clippy clean"
else
    fail "cargo clippy found warnings"
fi

# Check for unwrap/expect in rslib/src while excluding dedicated test files
# and whole #[cfg(test)] modules embedded in source files.
read -r UNWRAP_COUNT EXPECT_COUNT <<EOF
$(python3 - <<'PY'
from pathlib import Path
import re

root = Path("rslib/src")
unwrap_count = 0
expect_count = 0

for path in root.rglob("*.rs"):
    rel = path.relative_to(root).as_posix()
    if "/tests/" in rel or rel.endswith("/tests.rs") or rel == "tests.rs" or rel.endswith("_test.rs"):
        continue

    lines = path.read_text().splitlines()
    filtered = []
    i = 0
    while i < len(lines):
        stripped = lines[i].strip()
        if stripped.startswith("#[cfg(test)]"):
            j = i + 1
            while j < len(lines) and lines[j].strip() == "":
                j += 1
            if j < len(lines) and re.search(r"\bmod\b", lines[j]):
                brace_depth = lines[j].count("{") - lines[j].count("}")
                i = j + 1
                while i < len(lines) and brace_depth > 0:
                    brace_depth += lines[i].count("{") - lines[i].count("}")
                    i += 1
                continue
        filtered.append(lines[i])
        i += 1

    text = "\n".join(filtered)
    unwrap_count += len(re.findall(r"\.unwrap\s*\(", text))
    expect_count += len(re.findall(r"\.expect\s*\(", text))

print(f"{unwrap_count} {expect_count}")
PY
)
EOF
if [ "$UNWRAP_COUNT" -gt 0 ] || [ "$EXPECT_COUNT" -gt 0 ]; then
    if [ "$UNWRAP_COUNT" -le "$LEGACY_RSLIB_UNWRAP_BASELINE" ] && [ "$EXPECT_COUNT" -le "$LEGACY_RSLIB_EXPECT_BASELINE" ]; then
        pass "rslib unwrap/expect usage stayed within the legacy baseline ($UNWRAP_COUNT unwrap, $EXPECT_COUNT expect)"
    else
        warn "Found $UNWRAP_COUNT unwrap() and $EXPECT_COUNT expect() calls in rslib/src/ library code (legacy baseline: $LEGACY_RSLIB_UNWRAP_BASELINE unwrap, $LEGACY_RSLIB_EXPECT_BASELINE expect)"
    fi
else
    pass "No unwrap/expect in rslib/src/ library code"
fi

# --- Swift checks ---
section "Swift"

if [ -d "AnkiApp/" ]; then
    FORCE_UNWRAP=$(grep -rn '!' AnkiApp/ --include='*.swift' 2>/dev/null | grep -c 'as!' || true)
    FORCE_UNWRAP=$(printf "%s" "$FORCE_UNWRAP" | tr -d '[:space:]')
        if [ "$FORCE_UNWRAP" -gt 0 ]; then
        warn "Found $FORCE_UNWRAP force-unwrap (as!) in AnkiApp/"
    else
        pass "No force-unwrap (as!) in AnkiApp/"
    fi

    OBS_OBJ=$(grep -RIl 'ObservableObject' AnkiApp/ --include='*.swift' 2>/dev/null || true)
    OBS_OBJ=$(printf "%s\n" "$OBS_OBJ" | sed '/^$/d' | wc -l | tr -d ' ')
    if [ "$OBS_OBJ" -gt 0 ]; then
        warn "Found $OBS_OBJ files using ObservableObject (prefer @Observable)"
    else
        pass "No legacy ObservableObject usage"
    fi

    COMBINE=$(grep -RIl 'import Combine' AnkiApp/ --include='*.swift' 2>/dev/null || true)
    COMBINE=$(printf "%s\n" "$COMBINE" | sed '/^$/d' | wc -l | tr -d ' ')
    if [ "$COMBINE" -gt 0 ]; then
        warn "Found $COMBINE files importing Combine (prefer async/await)"
    else
        pass "No Combine imports"
    fi

    XCTEST=$(grep -RIl 'import XCTest' AnkiApp/ --include='*.swift' 2>/dev/null | grep -v '/AnkiAppUITests/' || true)
    XCTEST=$(printf "%s\n" "$XCTEST" | sed '/^$/d' | wc -l | tr -d ' ')
    if [ "$XCTEST" -gt 0 ]; then
        warn "Found $XCTEST files using XCTest (prefer Swift Testing)"
    else
        pass "No legacy XCTest usage"
    fi
else
    warn "AnkiApp/ directory not found -- skipping Swift checks"
fi

# --- SwiftLint ---
section "SwiftLint"

if command -v swiftlint >/dev/null 2>&1; then
    if [ -d "AnkiApp/" ]; then
        SWIFTLINT_OUT=$(swiftlint lint --config .swiftlint.yml --quiet 2>&1 || true)
        SWIFTLINT_ERRORS=$(printf "%s\n" "$SWIFTLINT_OUT" | grep -c ': error:' 2>/dev/null || true)
        SWIFTLINT_ERRORS=$(printf "%s" "$SWIFTLINT_ERRORS" | tr -d '[:space:]')
        SWIFTLINT_WARNS=$(printf "%s\n" "$SWIFTLINT_OUT" | grep -c ': warning:' 2>/dev/null || true)
        SWIFTLINT_WARNS=$(printf "%s" "$SWIFTLINT_WARNS" | tr -d '[:space:]')
        if [ "$SWIFTLINT_ERRORS" -gt 0 ]; then
            fail "swiftlint found $SWIFTLINT_ERRORS error(s) and $SWIFTLINT_WARNS warning(s)"
            echo "$SWIFTLINT_OUT" | grep ': error:' | head -20
        elif [ "$SWIFTLINT_WARNS" -gt 0 ]; then
            warn "swiftlint found $SWIFTLINT_WARNS warning(s)"
            echo "$SWIFTLINT_OUT" | grep ': warning:' | head -20
        else
            pass "swiftlint clean"
        fi
    else
        warn "AnkiApp/ directory not found -- skipping swiftlint"
    fi
else
    warn "swiftlint not installed -- skipping"
fi

# --- SwiftFormat ---
section "SwiftFormat"

if command -v swiftformat >/dev/null 2>&1; then
    if [ -d "AnkiApp/" ]; then
        SWIFTFORMAT_OUT=$(swiftformat --config .swiftformat --lint AnkiApp/AnkiApp/AnkiApp --exclude AnkiApp/AnkiApp/AnkiApp/Proto 2>&1 || true)
        SWIFTFORMAT_ISSUES=$(printf "%s\n" "$SWIFTFORMAT_OUT" | grep -c 'would have been formatted' 2>/dev/null || true)
        SWIFTFORMAT_ISSUES=$(printf "%s" "$SWIFTFORMAT_ISSUES" | tr -d '[:space:]')
        if [ "$SWIFTFORMAT_ISSUES" -gt 0 ]; then
            fail "swiftformat found $SWIFTFORMAT_ISSUES file(s) with formatting issues"
            echo "$SWIFTFORMAT_OUT" | grep 'would have been formatted' | head -20
        else
            pass "swiftformat clean"
        fi
    else
        warn "AnkiApp/ directory not found -- skipping swiftformat"
    fi
else
    warn "swiftformat not installed -- skipping"
fi

# --- cargo deny ---
section "Cargo Deny"

if command -v cargo-deny >/dev/null 2>&1 || cargo deny --version >/dev/null 2>&1; then
    if cargo deny check >/dev/null 2>&1; then
        pass "cargo deny clean"
    else
        DENY_OUT=$(cargo deny check 2>&1 || true)
        DENY_ERRORS=$(echo "$DENY_OUT" | grep -c 'error\[' 2>/dev/null || echo "0")
        DENY_WARNS=$(echo "$DENY_OUT" | grep -c 'warning\[' 2>/dev/null || echo "0")
        if [ "$DENY_ERRORS" -gt 0 ]; then
            fail "cargo deny found $DENY_ERRORS error(s)"
            echo "$DENY_OUT" | grep 'error\[' | head -10
        else
            warn "cargo deny found $DENY_WARNS warning(s)"
        fi
    fi
else
    warn "cargo-deny not installed -- skipping (install with: cargo install cargo-deny)"
fi

# --- Proto checks ---
section "Proto"

if [ -d "proto/anki/" ]; then
    PROTO_SERVICES=$(grep -rch '^service ' proto/anki/ --include='*.proto' 2>/dev/null | paste -sd+ - | bc 2>/dev/null || echo "0")
    echo "  INFO: $PROTO_SERVICES protobuf services defined"

    # The current Apple bridge keeps service/method IDs in Swift, not Rust.
    SERVICE_CONSTANTS_FILES=$(find AnkiApp -name 'ServiceConstants.swift' -print 2>/dev/null || true)
    SERVICE_CONSTANTS_COUNT=$(printf "%s\n" "$SERVICE_CONSTANTS_FILES" | sed '/^$/d' | wc -l | tr -d ' ')
    echo "  INFO: $SERVICE_CONSTANTS_COUNT ServiceConstants.swift file(s) found"
    if [ "$PROTO_SERVICES" -gt 0 ] && [ "$SERVICE_CONSTANTS_COUNT" -eq 0 ]; then
        warn "Proto defines $PROTO_SERVICES services but no ServiceConstants.swift was found in the Apple bridge"
    else
        pass "Proto services have corresponding Swift service constants"
    fi
else
    warn "proto/anki/ directory not found -- skipping proto checks"
fi

# --- Summary ---
section "Summary"
echo "  PASS: $PASS | WARN: $WARN | FAIL: $FAIL"

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
