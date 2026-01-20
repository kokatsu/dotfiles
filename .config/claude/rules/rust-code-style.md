---
paths:
  - "**/*.rs"
  - "**/Cargo.toml"
---

# Rust Code Style

## Naming Conventions

- **Types** (structs, enums, traits): `PascalCase`
- **Functions, methods, variables**: `snake_case`
- **Constants**: `SCREAMING_SNAKE_CASE`
- **Lifetimes**: short lowercase, typically `'a`, `'b`
- **Type parameters**: single uppercase letter `T`, `E`, `K`, `V` or descriptive `Item`, `Error`

## Formatting

- Use `rustfmt` defaults (run `cargo fmt`)
- Max line length: 100 characters
- Use 4 spaces for indentation (no tabs)

## Imports

```rust
// Group imports: std, external crates, internal modules
use std::collections::HashMap;

use serde::{Deserialize, Serialize};
use tokio::sync::mpsc;

use crate::config::Config;
use crate::error::Result;
```

## Documentation

- Use `///` for public items
- Use `//!` for module-level docs
- Include examples in doc comments for public APIs

```rust
/// Calculates the sum of two numbers.
///
/// # Examples
///
/// ```
/// let result = my_crate::add(2, 3);
/// assert_eq!(result, 5);
/// ```
pub fn add(a: i32, b: i32) -> i32 {
    a + b
}
```

## Patterns

### Prefer iterators over loops

```rust
// Good
let sum: i32 = numbers.iter().sum();
let doubled: Vec<_> = numbers.iter().map(|x| x * 2).collect();

// Avoid when iterator is cleaner
let mut sum = 0;
for n in &numbers {
    sum += n;
}
```

### Use `if let` for single pattern matching

```rust
// Good
if let Some(value) = optional {
    process(value);
}

// Unnecessary for single pattern
match optional {
    Some(value) => process(value),
    None => {},
}
```

### Use `let-else` for early returns

```rust
// Good: flat structure with early return
let Some(user) = get_user(id) else {
    return Err(Error::NotFound);
};
process(user);

// Avoid: deep nesting
if let Some(user) = get_user(id) {
    process(user);
} else {
    return Err(Error::NotFound);
}
```

### Derive common traits

```rust
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub struct UserId(String);

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct User {
    id: UserId,
    name: String,
}
```

## Memory Efficiency

### Copy vs Clone

```rust
// Small types: implement Copy
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Point { x: i32, y: i32 }

// Large types: Clone only
#[derive(Debug, Clone)]
pub struct Document {
    content: String,
    metadata: HashMap<String, String>,
}
```

### Avoid unnecessary clones

```rust
// Good: borrow when possible
fn process(data: &str) { /* ... */ }

// Avoid: cloning when not needed
fn process(data: String) { /* ... */ }
```

## Visibility

### Minimize public exposure

```rust
// Good: expose only what's needed
pub struct Config {
    pub(crate) inner: ConfigInner,
}

impl Config {
    pub fn get(&self, key: &str) -> Option<&str> {
        self.inner.get(key)
    }
}

// Avoid: exposing implementation details
pub struct Config {
    pub data: HashMap<String, String>,  // Too exposed
}
```

### Use `pub(crate)` for internal APIs

```rust
pub(crate) fn internal_helper() { /* ... */ }
pub(super) fn module_helper() { /* ... */ }
```

## Clippy

Address all clippy warnings. Common ones:

- `clippy::unwrap_used` - Use `expect()` or proper error handling
- `clippy::clone_on_ref_ptr` - Be explicit about Arc/Rc clones
- `clippy::large_enum_variant` - Box large variants
