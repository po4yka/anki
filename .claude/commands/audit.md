Run `scripts/audit.sh` and report findings.

Additionally check for:
1. `unwrap()` usage in `rslib/` library code (not tests or build scripts)
2. `ObservableObject` usage in SwiftUI code (should use `@Observable` instead)
3. `proto/anki/` ServiceConstants consistency -- verify method indices match

Report all violations with file paths and line numbers.
