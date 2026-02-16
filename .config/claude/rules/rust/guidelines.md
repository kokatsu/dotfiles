---
paths:
  - "**/*.rs"
  - "**/Cargo.toml"
---

# Rust Guidelines

## Error Handling

- `thiserror` for libraries, `anyhow` for applications
- `unwrap()` 禁止 → `expect("reason")` or `?`
- `inspect_err` for logging errors inline
- `tracing` + `#[instrument]` for structured logging (not `log` crate)

## Style Preferences

- `let-else` for early returns (prefer over `if let` + else return)
- Iterators over imperative loops
- `pub(crate)` to minimize internal visibility

## API Design

- Accept generic inputs (`impl AsRef<str>`, `impl Into<String>`)
- Return concrete types (`Vec<T>`, not `impl Iterator`)
- `#[non_exhaustive]` on public structs and enums
- `Cow<str>` when ownership flexibility is needed

## Type Safety

- Newtype pattern for domain primitives (`UserId(i64)`, `Email(String)`)
- Redact secrets in `Debug`/`Display` impls
