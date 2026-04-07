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

# Check for unwrap/expect in rslib/src (excluding tests)
UNWRAP_COUNT=$(grep -rn '\.unwrap()' rslib/src/ --include='*.rs' | grep -v '#\[cfg(test)\]' | grep -v '#\[test\]' | grep -v 'mod tests' | grep -cv '_test\.rs' 2>/dev/null || echo "0")
EXPECT_COUNT=$(grep -rn '\.expect(' rslib/src/ --include='*.rs' | grep -v '#\[cfg(test)\]' | grep -v '#\[test\]' | grep -v 'mod tests' | grep -cv '_test\.rs' 2>/dev/null || echo "0")
if [ "$UNWRAP_COUNT" -gt 0 ] || [ "$EXPECT_COUNT" -gt 0 ]; then
    warn "Found $UNWRAP_COUNT unwrap() and $EXPECT_COUNT expect() calls in rslib/src/ (excluding test files)"
else
    pass "No unwrap/expect in rslib/src/ library code"
fi

# --- Swift checks ---
section "Swift"

if [ -d "AnkiApp/" ]; then
    FORCE_UNWRAP=$(grep -rn '!' AnkiApp/ --include='*.swift' | grep -c 'as!' 2>/dev/null || echo "0")
    if [ "$FORCE_UNWRAP" -gt 0 ]; then
        warn "Found $FORCE_UNWRAP force-unwrap (as!) in AnkiApp/"
    else
        pass "No force-unwrap (as!) in AnkiApp/"
    fi

    OBS_OBJ=$(grep -rcl 'ObservableObject' AnkiApp/ --include='*.swift' 2>/dev/null | wc -l | tr -d ' ')
    if [ "$OBS_OBJ" -gt 0 ]; then
        warn "Found $OBS_OBJ files using ObservableObject (prefer @Observable)"
    else
        pass "No legacy ObservableObject usage"
    fi

    COMBINE=$(grep -rcl 'import Combine' AnkiApp/ --include='*.swift' 2>/dev/null | wc -l | tr -d ' ')
    if [ "$COMBINE" -gt 0 ]; then
        warn "Found $COMBINE files importing Combine (prefer async/await)"
    else
        pass "No Combine imports"
    fi

    XCTEST=$(grep -rcl 'import XCTest' AnkiApp/ --include='*.swift' 2>/dev/null | wc -l | tr -d ' ')
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
        SWIFTLINT_ERRORS=$(echo "$SWIFTLINT_OUT" | grep -c ': error:' 2>/dev/null || echo "0")
        SWIFTLINT_WARNS=$(echo "$SWIFTLINT_OUT" | grep -c ': warning:' 2>/dev/null || echo "0")
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
        SWIFTFORMAT_ISSUES=$(echo "$SWIFTFORMAT_OUT" | grep -c 'would have been formatted' 2>/dev/null || echo "0")
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

    # Check if ServiceConstants enums exist in bridge
    if [ -d "bridge/src/" ]; then
        BRIDGE_ENUMS=$(grep -c 'enum.*Service' bridge/src/*.rs 2>/dev/null || echo "0")
        echo "  INFO: $BRIDGE_ENUMS service enum(s) in bridge/"
        if [ "$PROTO_SERVICES" -gt 0 ] && [ "$BRIDGE_ENUMS" -eq 0 ]; then
            warn "Proto defines $PROTO_SERVICES services but no ServiceConstants enum found in bridge/"
        else
            pass "Proto services have corresponding bridge enums"
        fi
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
