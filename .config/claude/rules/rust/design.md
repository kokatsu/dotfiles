---
paths:
  - "**/*.rs"
---

# Rust Design Patterns

## Type System

### Newtype pattern

```rust
// Wrap primitives for type safety
pub struct UserId(pub i64);
pub struct Email(String);

impl Email {
    pub fn new(s: &str) -> Result<Self, ValidationError> {
        if s.contains('@') {
            Ok(Self(s.to_lowercase()))
        } else {
            Err(ValidationError::InvalidEmail)
        }
    }
}
```

### Typestate pattern

```rust
// Compile-time state enforcement
pub struct Request<S> {
    inner: RequestInner,
    _state: PhantomData<S>,
}

pub struct Draft;
pub struct Ready;

impl Request<Draft> {
    pub fn new() -> Self { /* ... */ }

    pub fn set_body(self, body: &str) -> Request<Ready> {
        Request {
            inner: self.inner.with_body(body),
            _state: PhantomData,
        }
    }
}

impl Request<Ready> {
    pub fn send(self) -> Response { /* ... */ }
}

// Usage: can only send Ready requests
let req = Request::new().set_body("data").send();
```

## Trait Implementation

### From trait usage

```rust
// Use From for simple 1:1 conversions only
impl From<i64> for UserId {
    fn from(id: i64) -> Self {
        Self(id)
    }
}

// For complex conversions, use explicit methods
impl User {
    // Not From<UserDto> - conversion is complex
    pub fn from_dto(dto: UserDto, context: &Context) -> Result<Self> {
        // Complex validation and transformation
    }
}
```

### Default trait

```rust
#[derive(Default)]
pub struct Config {
    pub timeout: Duration,
    pub retries: u32,
}

impl Default for Config {
    fn default() -> Self {
        Self {
            timeout: Duration::from_secs(30),
            retries: 3,
        }
    }
}
```

## Struct Design

### Non-exhaustive for public APIs

```rust
// Allow future field additions without breaking changes
#[non_exhaustive]
pub struct Config {
    pub name: String,
    pub version: u32,
}

#[non_exhaustive]
pub enum Error {
    NotFound,
    InvalidInput(String),
}
```

### Builder pattern

```rust
#[derive(Default)]
pub struct RequestBuilder {
    url: Option<String>,
    timeout: Option<Duration>,
    headers: HashMap<String, String>,
}

impl RequestBuilder {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn url(mut self, url: impl Into<String>) -> Self {
        self.url = Some(url.into());
        self
    }

    pub fn timeout(mut self, timeout: Duration) -> Self {
        self.timeout = Some(timeout);
        self
    }

    pub fn header(mut self, key: &str, value: &str) -> Self {
        self.headers.insert(key.into(), value.into());
        self
    }

    pub fn build(self) -> Result<Request, BuilderError> {
        let url = self.url.ok_or(BuilderError::MissingUrl)?;
        Ok(Request {
            url,
            timeout: self.timeout.unwrap_or(Duration::from_secs(30)),
            headers: self.headers,
        })
    }
}

// Usage
let req = RequestBuilder::new()
    .url("https://api.example.com")
    .timeout(Duration::from_secs(10))
    .header("Authorization", "Bearer token")
    .build()?;
```

## Ownership Patterns

### Cow for flexible ownership

```rust
use std::borrow::Cow;

// Avoid allocation when not needed
fn process(input: Cow<str>) -> Cow<str> {
    if input.contains("error") {
        Cow::Owned(input.replace("error", "warning"))
    } else {
        input  // No allocation if no modification
    }
}

// Usage
process(Cow::Borrowed("hello"));       // No allocation
process(Cow::Owned(dynamic_string));   // Takes ownership
```

### Interior mutability

```rust
use std::cell::RefCell;
use std::sync::{Arc, Mutex, RwLock};

// Single-threaded: RefCell
struct Cache {
    data: RefCell<HashMap<String, String>>,
}

// Multi-threaded: Mutex or RwLock
struct SharedCache {
    data: Arc<RwLock<HashMap<String, String>>>,
}
```

## API Design

### Accept generic inputs

```rust
// Good: accepts &str, String, Cow<str>, etc.
pub fn greet(name: impl AsRef<str>) {
    println!("Hello, {}!", name.as_ref());
}

// Good: accepts anything iterable
pub fn sum<I>(items: I) -> i32
where
    I: IntoIterator<Item = i32>,
{
    items.into_iter().sum()
}
```

### Return concrete types

```rust
// Good: return concrete type
pub fn get_users() -> Vec<User> { /* ... */ }

// Avoid: returning impl Trait for public APIs (unless necessary)
pub fn get_users() -> impl Iterator<Item = User> { /* ... */ }
```
