# Logging Guidelines

## 1. What to Include: 5W1H

Every meaningful log entry should answer the relevant subset of these questions:

| Element | What to Record | Example |
|---|---|---|
| **When** | Timestamp in ISO 8601 with timezone | `2025-08-01T12:34:56+09:00` |
| **Where** | Source — module, file, function, line | `auth.service:validateToken:42` |
| **Who** | Actor — user ID, session ID, IP, request ID | `user_id=u-123 request_id=req-abc` |
| **What** | Operation, data entity, result | `User login attempt` |
| **Why** | Reason, error code, status | `error_code=AUTH_EXPIRED reason="token expired"` |
| **How** | Method, trigger, path | `via=OAuth2 provider=Google` |

Not every log needs all six elements. Use judgment:

- **Error logs**: prioritize When, Where, What, Why
- **Access/audit logs**: prioritize When, Who, What
- **Debug logs**: prioritize Where, What, How

## 2. Log Levels

Use levels consistently. Each level has a specific purpose:

| Level | Purpose | Example |
|---|---|---|
| **FATAL** | System cannot continue. Requires immediate human intervention. | Database connection pool exhausted, out of disk space |
| **ERROR** | Operation failed. Needs attention but system still runs. | Payment processing failed, external API 500 |
| **WARN** | Potential problem or degraded state. System auto-recovered. | Retry succeeded after timeout, cache miss rate high, deprecated API called |
| **INFO** | Normal operational milestones. Useful for understanding flow. | Server started, user logged in, order created |
| **DEBUG** | Developer diagnostics. Disabled in production by default. | SQL query text, request/response bodies, variable state |

### Level Selection Heuristics

- **ERROR vs WARN**: Can the system handle it automatically? → WARN. Needs human action? → ERROR.
- **INFO vs DEBUG**: Would an operator in production need this? → INFO. Only developers debugging? → DEBUG.
- **Expected conditions** (e.g., 404 on user search, validation failure on user input) should not be ERROR.

### Environment-Specific Verbosity

| Environment | Recommended Minimum Level |
|---|---|
| Development | DEBUG |
| Staging / QA | INFO |
| Production | WARN (or INFO for critical services) |

Make the log level configurable without code changes (environment variable, config file).

## 3. What NOT to Log

### Absolutely Forbidden

These must never appear in any log, at any level, in any environment:

- Passwords, password hashes
- Secret keys, API tokens, JWTs (log the claim/subject ID only)
- Credit card numbers, CVV, bank account numbers
- Database connection strings with credentials

### Require Masking

When partially needed for debugging, mask the identifying portion:

| Data Type | Masking Example |
|---|---|
| Email | `u***@example.com` |
| Phone | `***-****-1234` |
| Name | `田***` or omit entirely |
| IP address | Consider jurisdiction (GDPR) — hash or truncate |
| Credit card | Never log — not even masked |

### Development-Only Data

Allow these in DEBUG level but ensure they are disabled in production:

- Full request/response bodies
- SQL queries with parameter values
- Internal system state dumps
- Detailed stack traces (include in ERROR, omit in INFO/WARN)

## 4. Structured Logging

Prefer structured logging over plain text for machine-parseable, searchable output.

### Good — Structured (JSON)

```json
{
  "timestamp": "2025-08-01T12:34:56.789+09:00",
  "level": "ERROR",
  "logger": "payment.service",
  "message": "Payment processing failed",
  "request_id": "req-abc-123",
  "user_id": "u-456",
  "error_code": "PAYMENT_DECLINED",
  "amount": 1500,
  "currency": "JPY"
}
```

### Bad — Unstructured

```text
2025-08-01 12:34:56 ERROR Payment processing failed for user u-456, amount 1500 JPY, error: PAYMENT_DECLINED
```

### Key Practices

- Use **key-value pairs** for variable data, not string interpolation
- Keep the `message` field human-readable; put structured data in separate fields
- Include a **correlation/request ID** for distributed tracing
- Use **consistent key naming** across the codebase (snake_case recommended)
- Use the project's established structured logging library — avoid `print()`, `console.log()`, `fmt.Println()` and similar unstructured output in production code

## 5. Error Logging Best Practices

Error logs are the most critical for troubleshooting. Every error log should include:

1. **What failed** — Clear description of the operation that failed
2. **Context** — Input parameters (sanitized), relevant state, request ID
3. **Error details** — Error code, exception type, error message
4. **Stack trace** — For unexpected/unhandled errors
5. **Recovery status** — What the system did or what needs to happen next

### Good Error Log

```python
logger.error(
    "Failed to process payment",
    extra={
        "request_id": request_id,
        "user_id": user_id,
        "error_code": "GATEWAY_TIMEOUT",
        "retry_count": 3,
        "action": "queued_for_retry",
    },
    exc_info=True,
)
```

### Bad Error Log

```python
logger.error("Error occurred")           # No context at all
logger.error(str(e))                      # No description of what failed
logger.error(f"Failed for {card_number}") # Leaks sensitive data
```

### Common Anti-Patterns

- **Catch-and-log at multiple layers** — Log at the boundary once; duplicate entries across layers create noise
- **Logging inside tight loops without rate limiting** — Causes performance degradation and log flooding

## 6. Production Practices

### Log Separation

Separate log destinations by purpose:

- **Access log** — HTTP requests, API calls (who accessed what)
- **Application log** — Business logic events, state transitions
- **Error log** — Errors and exceptions
- **Audit log** — Security-relevant operations (login, permission changes, data access)

### Operational Considerations

- **Rotation**: Configure log rotation by size or time (logrotate, framework built-in)
- **Retention**: Define retention period based on compliance and operational needs
- **Compression**: Compress archived logs to save storage
- **Performance**: Avoid string concatenation in hot paths when log level is disabled; use lazy evaluation
- **Async output**: Ensure log writes don't block the main application thread in high-throughput systems

## 7. Logging for Observability

### Correlation IDs

In distributed systems, propagate a correlation/request ID across all services:

```text
request_id=req-abc-123
```

This enables tracing a single user request across multiple service logs.

### Key Operational Events to Log

| Event | Level | What to Include |
|---|---|---|
| Application start/stop | INFO | Version, config summary, port |
| Incoming request | INFO/DEBUG | Method, path, request ID |
| Outgoing request to external service | DEBUG | Target, timeout, request ID |
| Authentication success/failure | INFO/WARN | User ID (no credentials), IP, method |
| Authorization failure | WARN | User ID, resource, required permission |
| Data mutation (create/update/delete) | INFO | Entity type, ID, actor |
| Scheduled job start/end | INFO | Job name, duration, result |
| Resource threshold exceeded | WARN | Metric name, current value, threshold |
| Unhandled exception | ERROR | Full context + stack trace |
| Service dependency failure | ERROR | Target service, error, circuit breaker state |
