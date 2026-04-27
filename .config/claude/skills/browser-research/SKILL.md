---
name: browser-research
description: Research web pages using agent-browser — a headless browser CLI that renders JavaScript and handles dynamic content. Use this skill as a fallback when WebSearch or WebFetch fails, returns insufficient results, or when the target page requires JS rendering (SPAs, dynamic docs). Also use when the user provides a specific URL to investigate, when you need to navigate multi-page documentation, or when summarizing web content that WebFetch cannot parse properly.
allowed-tools:
  - Bash(agent-browser:*)
  - Read
  - Write
---

# Browser Research Skill

Research web pages using agent-browser CLI and summarize content.

## Usage

```text
/browser-research <URL> [research topic or question]
```

## Workflow

### 0. Clean up existing session (if needed)

A previous session may still be open. Close it before starting to avoid conflicts:

```bash
agent-browser close 2>/dev/null || true
```

### 1. Open the page

```bash
agent-browser open "<URL>" && agent-browser wait --load networkidle --timeout 15000
```

If `open` fails: verify the URL is well-formed, retry once. If it fails again, report the error to the user and stop.

If `wait` times out: proceed anyway — the page may still be usable.

**Next, choose the extraction method based on your purpose:**

| Purpose | Command | When to use |
|---------|---------|-------------|
| Read article/docs text | `agent-browser eval "document.body.innerText"` | Blog posts, documentation, text-heavy pages. Most token-efficient |
| Understand page structure | `agent-browser snapshot -c` | Need to see layout, navigation, or element refs for interaction |
| Find interactive elements | `agent-browser snapshot -i -c` | Need to click links, buttons, or fill forms |
| List links with URLs | `agent-browser snapshot -i -c -u` | Need link destinations (href) without an extra `get attribute` round-trip |

For a typical single-article research, `eval "document.body.innerText"` is often sufficient. Use `snapshot` only when you need structure or element refs.

**For large pages**, append `--max-output 10000` to prevent token explosion:

```bash
agent-browser eval "document.body.innerText" --max-output 10000
```

**If a cookie consent banner or overlay blocks content**, dismiss it first:

```bash
agent-browser snapshot -i -c   # find the accept/close button ref
agent-browser click "@ref"     # dismiss the banner
```

Then proceed with the chosen extraction method.

**Stop here if you have enough information.** Steps 2–8 below are only needed for deeper investigation.

### 2. Get detailed content (if needed)

Get text from specific element:

```bash
agent-browser get text "@ref"
```

Get page metadata:

```bash
agent-browser get title && agent-browser get url
```

Find elements by role, text, or label:

```bash
agent-browser find role heading
agent-browser find text "keyword"
```

### 3. Handle long pages

Scroll to load more content:

```bash
agent-browser scroll down 500 && agent-browser snapshot -c
```

Scroll a specific element into view:

```bash
agent-browser scrollintoview "@ref" && agent-browser snapshot -c
```

### 4. Observe network traffic (SPAs / API-heavy pages)

When `eval` and `snapshot` cannot reveal dynamically loaded data, watch the underlying network calls to identify the real data source.

Capture HAR while interacting with the page:

```bash
agent-browser network har start
# perform navigation / scroll / clicks here
agent-browser network har stop "/tmp/page.har"
```

Inspect requests inline (no HAR file needed):

```bash
agent-browser network requests --type xhr,fetch --status 2xx
agent-browser network request <requestId>   # full request/response detail
```

Filter flags: `--type` (e.g. `xhr,fetch`, `document`, `script`), `--method` (e.g. `POST`), `--status` (e.g. `2xx`, `400-499`).

Use this to locate the JSON endpoint behind a SPA list, then `WebFetch` the endpoint directly for the cleanest data extraction.

### 5. Navigate to linked pages

Click a link:

```bash
agent-browser click "@ref" && agent-browser wait --load networkidle --timeout 15000 && agent-browser snapshot -c
```

Go back:

```bash
agent-browser back && agent-browser snapshot -c
```

### 6. Research additional URLs

Use tabs to research multiple pages without losing previous context:

```bash
agent-browser tab new && agent-browser open "<next-URL>" && agent-browser wait --load networkidle --timeout 15000 && agent-browser snapshot -c
```

Switch between tabs or close current tab:

```bash
agent-browser tab list
agent-browser tab <n>
agent-browser tab close
```

### 7. Save page as PDF (optional)

When the user requests a saved copy:

```bash
agent-browser pdf "/path/to/output.pdf"
```

### 8. Close when done

```bash
agent-browser close
```

## Critical Rules

- **Always close the session** — every `open` must have a matching `close`.
- **Read-only by default** — never submit forms or enter data. Clicking is allowed only for passive navigation: dismissing cookie/consent banners, following links, expanding collapsed sections, or switching tabs. Do not click buttons that trigger writes, purchases, or state changes.
- **No guessing** — do not fabricate or assume page content; only report what `snapshot`/`get`/`eval` return.
- **Authentication pages** — if a page requires login, report it immediately and stop. Do not attempt to authenticate.
- **Prefer command chaining** — use `&&` to combine related commands in a single bash call for efficiency.
- **Minimize tokens** — prefer `eval "document.body.innerText"` over `snapshot` when you only need text content. Use `--max-output` for large pages.

## Output Format

Respond in the same language the user used. Summarize findings in this structure:

1. **Overview**: Main topic and purpose of the page
2. **Key Points**: Important information as bullet points
3. **Details**: Detailed explanations as needed
4. **Related Links**: Additional resources to reference

When researching multiple URLs or when the user requests it, save results to a file using the Write tool. For a single-URL quick lookup, respond directly in chat.

## Snapshot Options

| Flag | Description |
|------|-------------|
| `-i`, `--interactive` | Show only interactive elements |
| `-c`, `--compact` | Remove empty structural elements |
| `-u`, `--urls` | Include `href` URLs for link elements |
| `-d <n>`, `--depth <n>` | Limit DOM tree depth |
| `-s <sel>`, `--selector <sel>` | Scope to CSS selector |

## Additional Useful Commands

- `screenshot --full` — Capture full page screenshot
- `screenshot --annotate` — Screenshot with numbered element labels
- `diff snapshot` — Compare current page state against previous snapshot
- `console` — View browser console logs (useful for debugging)
- `errors` — View page errors
- `get count "<sel>"` — Count matching elements
- `--max-output <chars>` — Truncate output for large pages
