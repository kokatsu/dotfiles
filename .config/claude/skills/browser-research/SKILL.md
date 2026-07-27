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

### 2. Close when done

```bash
agent-browser close
```

## Deeper investigation

Most research finishes with the steps above. Read `${CLAUDE_SKILL_DIR}/reference.md` when you need any of these:

- Text from a specific element, page metadata, or finding elements by role/text/label
- Scrolling to load more content on long pages
- Watching network traffic to locate the JSON endpoint behind a SPA
- Following links, going back, or researching several URLs in tabs
- Saving the page as a PDF
- The full `snapshot` flag reference and other commands

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
