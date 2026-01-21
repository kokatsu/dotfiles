---
paths:
  - "**/*.rs"
---

# Rust Error Handling

## Core Principles

- Use `Result<T, E>` for recoverable errors
- Use `panic!` only for unrecoverable errors (bugs)
- Propagate errors with `?` operator
- Provide context when errors cross boundaries

## Defining Errors

### Using `thiserror`

```rust
use thiserror::Error;

#[derive(Debug, Error)]
pub enum AppError {
    #[error("failed to read config file: {0}")]
    ConfigRead(#[from] std::io::Error),

    #[error("invalid configuration: {0}")]
    ConfigParse(#[from] serde_json::Error),

    #[error("user '{id}' not found")]
    UserNotFound { id: String },

    #[error("validation failed: {0}")]
    Validation(String),
}
```

### Using `anyhow` (for applications)

```rust
use anyhow::{Context, Result, bail, ensure};

fn load_config(path: &str) -> Result<Config> {
    let content = std::fs::read_to_string(path)
        .context("failed to read config file")?;

    let config: Config = serde_json::from_str(&content)
        .context("failed to parse config")?;

    ensure!(!config.name.is_empty(), "config name cannot be empty");

    if config.version < 1 {
        bail!("unsupported config version: {}", config.version);
    }

    Ok(config)
}
```

## Error Propagation

### Basic propagation with `?`

```rust
fn process_file(path: &str) -> Result<Data, Error> {
    let content = std::fs::read_to_string(path)?;
    let data = parse(&content)?;
    Ok(data)
}
```

### Adding context

```rust
fn process_user(id: &str) -> Result<User> {
    let user = db::find_user(id)
        .with_context(|| format!("failed to find user '{id}'"))?;

    let profile = fetch_profile(&user)
        .context("failed to fetch user profile")?;

    Ok(user.with_profile(profile))
}
```

### Use `inspect_err` for logging

```rust
use tracing::error;

fn fetch_data(url: &str) -> Result<Data> {
    client.get(url)
        .send()
        .inspect_err(|e| error!(%e, %url, "request failed"))?
        .json()
        .inspect_err(|e| error!(%e, "failed to parse response"))
}
```

## Pattern: Result Type Alias

```rust
// src/error.rs
pub type Result<T> = std::result::Result<T, Error>;

// Usage
pub fn do_something() -> Result<()> {
    // ...
}
```

## Handling Option

### Convert to Result

```rust
let value = map.get("key")
    .ok_or_else(|| Error::KeyNotFound("key".into()))?;

// With anyhow
let value = map.get("key")
    .context("key not found")?;
```

### Provide defaults

```rust
let value = config.timeout.unwrap_or(Duration::from_secs(30));
let name = user.nickname.unwrap_or_else(|| user.email.clone());
```

## When to Panic

Panic is appropriate for:

- Invariant violations (bugs in code)
- Unrecoverable states during initialization
- Test assertions

```rust
// Bug in code - index should always be valid
let item = items.get(index).expect("index should be valid");

// Initialization failure
let config = Config::load().expect("failed to load required config");

// Tests
assert_eq!(result, expected);
```

## Avoid

```rust
// Avoid: unwrap without context
let data = parse(input).unwrap();

// Better: expect with message
let data = parse(input).expect("input was already validated");

// Best: proper error handling
let data = parse(input)?;
```

## Logging with tracing

### Log levels

```rust
use tracing::{error, warn, info, debug, trace};

// error: operation failures, unrecoverable errors
error!(error = %e, "database connection failed");

// warn: recoverable issues, deprecations
warn!(attempt = retries, "retrying failed request");

// info: significant events, state changes
info!(user_id = %id, "user logged in");

// debug: diagnostic information for debugging
debug!(query = %sql, "executing query");

// trace: very detailed, verbose logging
trace!(bytes = data.len(), "received data");
```

### Structured logging

```rust
use tracing::{error, info, instrument};

#[instrument(skip(password))]
fn login(username: &str, password: &str) -> Result<User> {
    let user = db::find_user(username)
        .inspect_err(|e| error!(%e, "user lookup failed"))?;

    info!(user_id = %user.id, "login successful");
    Ok(user)
}
```

### Error logging patterns

```rust
match operation() {
    Ok(result) => info!("operation succeeded"),
    Err(e) => {
        error!(error = %e, "operation failed");
        // or for full error chain with anyhow
        error!(error = ?e, "operation failed");
    }
}
```
