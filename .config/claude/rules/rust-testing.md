---
paths:
  - "**/*.rs"
  - "**/Cargo.toml"
---

# Rust Testing Guidelines

## Test Organization

### Unit Tests

Place in the same file as the code being tested:

```rust
// src/calculator.rs
pub fn add(a: i32, b: i32) -> i32 {
    a + b
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_add() {
        assert_eq!(add(2, 3), 5);
    }

    #[test]
    fn test_add_negative() {
        assert_eq!(add(-1, 1), 0);
    }
}
```

### Integration Tests

Place in `tests/` directory:

```
tests/
├── common/
│   └── mod.rs      # Shared test utilities
├── api_tests.rs
└── db_tests.rs
```

```rust
// tests/api_tests.rs
use my_crate::api::Client;

mod common;

#[test]
fn test_api_request() {
    let client = common::setup_client();
    // ...
}
```

## Test Naming

Use descriptive names that explain the scenario:

```rust
#[test]
fn parse_valid_json_returns_user() { }

#[test]
fn parse_invalid_json_returns_error() { }

#[test]
fn empty_input_returns_none() { }
```

## Assertions

```rust
// Equality
assert_eq!(actual, expected);
assert_ne!(actual, unexpected);

// Boolean
assert!(condition);
assert!(!condition);

// With custom message
assert_eq!(result, 42, "Expected 42 but got {}", result);

// For Result types
assert!(result.is_ok());
assert!(result.is_err());

// Pattern matching
assert!(matches!(value, Some(x) if x > 0));
```

## Testing Errors

```rust
#[test]
fn invalid_input_returns_error() {
    let result = parse("invalid");
    assert!(result.is_err());

    // Check specific error type
    let err = result.unwrap_err();
    assert!(matches!(err, ParseError::InvalidFormat(_)));
}

#[test]
#[should_panic(expected = "index out of bounds")]
fn panics_on_invalid_index() {
    let v = vec![1, 2, 3];
    let _ = v[10];
}
```

## Async Tests

With `tokio`:

```rust
#[tokio::test]
async fn test_async_operation() {
    let result = fetch_data().await;
    assert!(result.is_ok());
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn test_concurrent_operations() {
    // ...
}
```

## Test Fixtures

```rust
struct TestContext {
    db: Database,
    client: Client,
}

impl TestContext {
    fn new() -> Self {
        Self {
            db: Database::in_memory(),
            client: Client::new(),
        }
    }
}

impl Drop for TestContext {
    fn drop(&mut self) {
        // Cleanup
    }
}

#[test]
fn test_with_context() {
    let ctx = TestContext::new();
    // Test using ctx.db and ctx.client
}
```

## Parameterized Tests

With `rstest`:

```rust
use rstest::rstest;

#[rstest]
#[case(2, 2, 4)]
#[case(0, 5, 5)]
#[case(-1, 1, 0)]
fn test_add(#[case] a: i32, #[case] b: i32, #[case] expected: i32) {
    assert_eq!(add(a, b), expected);
}

#[rstest]
#[case("hello", 5)]
#[case("", 0)]
#[case("rust", 4)]
fn test_len(#[case] input: &str, #[case] expected: usize) {
    assert_eq!(input.len(), expected);
}
```

### Fixtures with rstest

```rust
use rstest::{rstest, fixture};

#[fixture]
fn database() -> TestDb {
    TestDb::new()
}

#[rstest]
fn test_insert(database: TestDb) {
    database.insert("key", "value");
    assert_eq!(database.get("key"), Some("value"));
}
```

## Mocking

With `mockall`:

```rust
use mockall::{automock, predicate::*};

#[automock]
trait UserRepository {
    fn find(&self, id: i64) -> Option<User>;
    fn save(&self, user: &User) -> Result<(), Error>;
}

#[test]
fn test_user_service() {
    let mut mock = MockUserRepository::new();

    mock.expect_find()
        .with(eq(1))
        .times(1)
        .returning(|_| Some(User { id: 1, name: "Alice".into() }));

    let service = UserService::new(mock);
    let user = service.get_user(1).unwrap();
    assert_eq!(user.name, "Alice");
}
```

### Conditional mock compilation

```rust
#[cfg_attr(test, automock)]
pub trait Database {
    fn query(&self, sql: &str) -> Result<Vec<Row>>;
}
```

## Property-Based Testing

With `proptest`:

```rust
use proptest::prelude::*;

proptest! {
    #[test]
    fn doesnt_crash(s in "\\PC*") {
        let _ = parse(&s);
    }

    #[test]
    fn roundtrip(v: Vec<i32>) {
        let encoded = encode(&v);
        let decoded = decode(&encoded).unwrap();
        assert_eq!(v, decoded);
    }
}
```

## Cargo.toml Test Configuration

```toml
[dev-dependencies]
tokio = { version = "1", features = ["rt-multi-thread", "macros"] }
rstest = "0.23"
proptest = "1"
pretty_assertions = "1"
mockall = "0.13"

[[test]]
name = "integration"
path = "tests/integration.rs"

[profile.test]
opt-level = 0  # Fast compilation for tests
```

## Running Tests

```bash
cargo test                      # All tests
cargo test test_name            # Specific test
cargo test module::             # Tests in module
cargo test -- --ignored         # Run ignored tests
cargo test -- --test-threads=1  # Single-threaded
cargo test -- --nocapture       # Show stdout
```
