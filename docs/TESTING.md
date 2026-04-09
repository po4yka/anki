# Testing Guide

This document describes the testing strategy and patterns used throughout the Anki SwiftUI project.

## Running Tests

### All tests

```bash
# Run the entire test suite
cargo test --workspace

# With output captured (helpful for debugging)
cargo test --workspace -- --nocapture

# Single-threaded (useful if tests interfere with each other)
cargo test --workspace -- --test-threads=1
```

### Per-crate testing

```bash
# Test a specific crate
cargo test -p search
cargo test -p analytics
cargo test -p anki
cargo test -p cli

# Test a specific module
cargo test -p anki scheduler::
```

### SwiftUI tests

In Xcode:
- Open `AnkiApp/AnkiApp.xcodeproj`
- Product → Test (Cmd+U) for all tests
- Cmd+5 to show test navigator, then select individual tests
- UI tests and unit tests run on the simulator

## Test Organization

### Inline Tests (Rust)

Most Rust crates use inline `#[cfg(test)]` modules colocated with the code they test. This pattern keeps tests close to implementation and makes refactoring easier.

```rust
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_something() {
        // test code
    }
}
```

**Where**: Throughout `rslib/src/`, `atlas/*/src/`, `bins/*/src/`

**When to use**: Unit tests for public APIs, internal logic validation

### Integration Tests

Larger integration tests live in dedicated `tests/` directories at the crate level.

```
atlas/database/tests/database_tests.rs
bins/cli/tests/cli_integration.rs
```

**When to use**: Testing across crate boundaries, end-to-end workflows, CLI behavior

## Mocking

### mockall (Atlas crates)

All public traits in Atlas crates are decorated with `#[cfg_attr(test, mockall::automock)]` to enable automatic mock generation.

```rust
#[cfg_attr(test, mockall::automock)]
pub trait VectorRepository: Send + Sync {
    async fn store(&self, id: i64, vector: Vec<f32>) -> Result<()>;
    async fn search(&self, vector: Vec<f32>, limit: usize) -> Result<Vec<i64>>;
}
```

Usage in tests:

```rust
#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_with_mock() {
        let mut mock_repo = MockVectorRepository::new();
        mock_repo.expect_search().return_once(|_, _| Ok(vec![1, 2, 3]));
        
        let searcher = MySearcher::new(mock_repo);
        let results = searcher.find().await.unwrap();
        assert_eq!(results, vec![1, 2, 3]);
    }
}
```

**Pattern**: Test traits with mockall, write manual fakes for concrete types

### Manual Fakes

Some crates (especially those without trait-based DI) use manual fake implementations for testing.

```rust
// In tests
struct FakeVectorRepo {
    vectors: HashMap<i64, Vec<f32>>,
}

impl VectorRepository for FakeVectorRepo {
    async fn store(&self, id: i64, vector: Vec<f32>) -> Result<()> {
        self.vectors.insert(id, vector);
        Ok(())
    }
}
```

## Integration Tests with PostgreSQL

Integration tests requiring PostgreSQL use `testcontainers` to spin up ephemeral Postgres instances.

### Setup Pattern

```rust
use testcontainers::runners::AsyncRunner;
use testcontainers_modules::postgres::Postgres;

#[tokio::test]
async fn test_with_postgres() {
    let container = Postgres::default().start().await.unwrap();
    let host = container.get_host().await.unwrap();
    let port = container.get_host_port_ipv4(5432).await.unwrap();
    let url = format!("postgresql://postgres:postgres@{host}:{port}/postgres");
    
    let pool = sqlx::postgres::PgPoolOptions::new()
        .max_connections(5)
        .connect(&url)
        .await
        .unwrap();
    
    // container is dropped at end of test, cleanup happens automatically
    // test with pool...
}
```

**Where**: `atlas/database/tests/`, `atlas/search/tests/`, `atlas/analytics/tests/`

**Prerequisites**: Docker must be running for testcontainers to work

## SwiftUI Tests

### Unit Tests

Located in `AnkiApp/AnkiApp/AnkiAppTests/`:

```swift
import XCTest

@MainActor
final class DeckBrowserTests: XCTestCase {
    func test_deck_selection() throws {
        let service = AnkiService(mockCollection: true)
        // test code
        XCTAssertTrue(condition)
    }
}
```

### UI Tests

Located in `AnkiApp/AnkiApp/AnkiAppUITests/`:

```swift
final class ReviewerUITests: XCTestCase {
    func test_card_review_flow() throws {
        let app = XCUIApplication()
        app.launch()
        
        // Navigate and interact
        let reviewCard = app.buttons["show-answer"]
        XCTAssertTrue(reviewCard.exists)
        reviewCard.tap()
        
        // Assert UI state
        let easyButton = app.buttons["rate-easy"]
        XCTAssertTrue(easyButton.isHittable)
    }
}
```

**Run in Xcode**: Product → Test or Cmd+U

## Test Conventions

### Naming

- Rust: `test_<behavior>()` (e.g., `test_search_returns_results()`)
- Swift: `test_<component>_<action>()` (e.g., `testDeckBrowser_selection()`)

### Assertions

**Rust**:
```rust
assert_eq!(actual, expected, "message");
assert!(condition, "message");
assert_matches!(result, Ok(_));
```

**Swift**:
```swift
XCTAssertEqual(actual, expected)
XCTAssertTrue(condition)
XCTAssertThrowsError(try something())
```

### Test Data Helpers

Many crates provide test helpers in a `test.rs` module:

```rust
// In rslib/src/scheduler/answering/mod.rs
#[cfg(test)]
pub fn v3_test_collection(card_count: usize) -> Result<(Collection, Vec<CardId>)> {
    // Create a test collection with `card_count` cards
}
```

Use these to reduce boilerplate:

```rust
#[test]
fn test_scheduling() -> Result<()> {
    let (mut col, cids) = v3_test_collection(10)?;
    col.answer_easy();
    // test...
}
```

## Coverage

### Current State

Coverage is tracked via `cargo tarpaulin` for CI runs. Main coverage targets:

- **rslib**: Core scheduler, sync, storage (>80%)
- **atlas crates**: Service logic, transformations (>70%)
- **bridge**: FFI marshalling (>60%, lower priority)
- **bins**: CLI, MCP (>60%, lower priority)

### Running Coverage Locally

```bash
# Install tarpaulin
cargo install cargo-tarpaulin

# Generate coverage report
cargo tarpaulin --workspace --out Html
```

### Coverage Gaps to Address

- SwiftUI view models (low integration with Rust makes testing difficult)
- Error recovery paths (exercised mainly via integration tests)
- Sync conflict resolution edge cases (requires full AnkiWeb setup)

## Tips for Writing Tests

1. **Test behavior, not implementation** — Assert what users/callers care about
2. **Use `Result<()>` return type** — Cleaner error handling with `?`
3. **Keep tests small** — One assertion per test when possible
4. **Mock external dependencies** — Database, HTTP, filesystem
5. **Use fixtures for complex setup** — Helper functions, test collections
6. **Document non-obvious tests** — Why this specific case matters
7. **Run locally before pushing** — `cargo test --workspace && cargo clippy --workspace`

## Common Test Patterns

### Testing Result types

```rust
#[test]
fn returns_error_for_invalid_input() {
    let result = function_under_test(invalid_input);
    assert!(result.is_err());
    assert_eq!(result.unwrap_err().to_string(), "expected message");
}
```

### Testing async code

```rust
#[tokio::test]
async fn async_operation_completes() {
    let result = async_function().await;
    assert_eq!(result, expected_value);
}
```

### Testing collections

```rust
#[test]
fn collects_all_items() {
    let items: Vec<_> = (0..100).map(|i| transform(i)).collect();
    assert_eq!(items.len(), 100);
    assert!(items.iter().all(|item| item.is_valid()));
}
```

## Troubleshooting

**Tests hang or timeout**: Check for unbounded async operations or missing `.await`

**testcontainers fails**: Ensure Docker is running: `docker ps`

**Swift test build fails**: Verify Rust bridge compiled: `cargo build --release -p anki_bridge`

**Flaky tests**: Check for timing assumptions, use proper async/await, avoid sleep()

**Large test output**: Use `--nocapture` only for specific tests, not entire suite

See [CONTRIBUTING.md](../CONTRIBUTING.md) for more development guidance.
