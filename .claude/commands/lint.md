Run the following lint checks and report any issues:

**Rust**
1. `cargo fmt --all -- --check` -- check formatting
2. `cargo clippy --workspace -- -D warnings` -- lint all crates
3. `cargo deny check` -- check dependencies for advisories, licenses, and bans

**Swift**
4. `swiftlint lint --config .swiftlint.yml` -- lint Swift sources
5. `swiftformat --config .swiftformat --lint AnkiApp/AnkiApp/AnkiApp --exclude AnkiApp/AnkiApp/AnkiApp/Proto` -- check Swift formatting

Report each warning or error with file location. If everything passes, confirm clean.
