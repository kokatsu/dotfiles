---
paths:
  - "**/*.rs"
  - "**/Cargo.toml"
---

# Rust Security Guidelines

## Input Validation

### Validate at boundaries

```rust
pub fn create_user(input: CreateUserInput) -> Result<User> {
    // Validate all input at the entry point
    let email = Email::parse(&input.email)?;
    let username = Username::parse(&input.username)?;

    // Internal code can trust validated types
    db::insert_user(&email, &username)
}
```

### Use newtypes for validated data

```rust
pub struct Email(String);

impl Email {
    pub fn parse(s: &str) -> Result<Self, ValidationError> {
        if s.contains('@') && s.len() <= 254 {
            Ok(Self(s.to_lowercase()))
        } else {
            Err(ValidationError::InvalidEmail)
        }
    }
}
```

## Secrets Management

### Never log secrets

```rust
pub struct ApiKey(String);

impl std::fmt::Debug for ApiKey {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "ApiKey([REDACTED])")
    }
}

impl std::fmt::Display for ApiKey {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "[REDACTED]")
    }
}
```

### Use `secrecy` crate

```rust
use secrecy::{Secret, ExposeSecret};

struct Config {
    api_key: Secret<String>,
}

fn use_api_key(config: &Config) {
    // Explicit exposure required
    let key = config.api_key.expose_secret();
    client.authenticate(key);
}
```

## SQL Injection Prevention

### Use parameterized queries

```rust
// Good: parameterized
sqlx::query("SELECT * FROM users WHERE id = $1")
    .bind(user_id)
    .fetch_one(&pool)
    .await?;

// NEVER: string interpolation
let query = format!("SELECT * FROM users WHERE id = {}", user_id);
```

## Command Injection Prevention

```rust
use std::process::Command;

// Good: arguments are separate
Command::new("git")
    .args(["clone", "--depth", "1", &url])
    .output()?;

// NEVER: shell execution with user input
Command::new("sh")
    .arg("-c")
    .arg(format!("git clone {}", url))  // Dangerous!
    .output()?;
```

## Path Traversal Prevention

```rust
use std::path::{Path, PathBuf};

fn safe_join(base: &Path, user_path: &str) -> Result<PathBuf> {
    let path = base.join(user_path);
    let canonical = path.canonicalize()?;

    // Ensure resolved path is under base
    if !canonical.starts_with(base.canonicalize()?) {
        return Err(Error::PathTraversal);
    }

    Ok(canonical)
}
```

## Cryptography

### Use well-audited crates

- Hashing: `argon2`, `bcrypt` (passwords), `sha2` (general)
- Encryption: `aes-gcm`, `chacha20poly1305`
- Random: `rand` with `OsRng`

```rust
use argon2::{Argon2, PasswordHasher, PasswordVerifier};
use argon2::password_hash::{SaltString, rand_core::OsRng};

fn hash_password(password: &str) -> Result<String> {
    let salt = SaltString::generate(&mut OsRng);
    let hash = Argon2::default()
        .hash_password(password.as_bytes(), &salt)?
        .to_string();
    Ok(hash)
}
```

## Dependency Security

```bash
# Audit dependencies for vulnerabilities
cargo audit

# Check for outdated dependencies
cargo outdated

# Minimal dependency versions in CI
cargo +nightly -Z minimal-versions check
```

### Cargo.toml best practices

```toml
[dependencies]
# Pin major versions to avoid unexpected breaking changes
serde = "1"
tokio = { version = "1", features = ["rt-multi-thread"] }

# Avoid wildcard versions
# bad: serde = "*"
```

## Unsafe Code

- Minimize `unsafe` usage
- Document safety invariants
- Isolate in dedicated modules
- Review carefully in PRs

```rust
/// # Safety
///
/// - `ptr` must be valid and properly aligned
/// - `ptr` must point to an initialized `T`
/// - The pointed value must not be accessed through any other pointer
unsafe fn deref_raw<T>(ptr: *const T) -> &T {
    &*ptr
}
```
