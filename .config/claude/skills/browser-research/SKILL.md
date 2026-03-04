---
name: browser-research
description: Research web pages using agent-browser and summarize documentation or articles. Use when investigating URLs, checking page content, or summarizing documents.
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

### 0. Clean up existing session

Always close any lingering session before starting:

```bash
agent-browser close
```

Ignore errors if no session exists.

### 1. Open the page

```bash
agent-browser open "<URL>"
agent-browser wait --load networkidle
```

If `open` fails: verify the URL is well-formed, retry once. If it fails again, report the error to the user and stop.

### 2. Get page structure

```bash
agent-browser snapshot --compact
```

Use `--compact` to remove empty structural elements for cleaner output.

### 3. Get detailed content if needed

Get text from specific element:

```bash
agent-browser get text "@ref"
```

Get full page text:

```bash
agent-browser eval "document.body.innerText"
```

### 4. Handle long pages

Scroll to load more content:

```bash
agent-browser scroll down 500
agent-browser snapshot --compact
```

### 5. Navigate to linked pages

Click a link:

```bash
agent-browser click "@ref"
agent-browser snapshot --compact
```

Go back:

```bash
agent-browser back
```

### 6. Research additional URLs

For each additional URL, cycle through:

```bash
agent-browser close
agent-browser open "<next-URL>"
agent-browser wait --load networkidle
agent-browser snapshot --compact
```

Then repeat steps 3–5 as needed.

### 7. Close when done

```bash
agent-browser close
```

## Critical Rules

- **Always close the session** — every `open` must have a matching `close`.
- **Read-only** — never submit forms, click buttons that trigger writes, or enter data.
- **No guessing** — do not fabricate or assume page content; only report what `snapshot`/`get`/`eval` return.
- **Authentication pages** — if a page requires login, report it immediately and stop. Do not attempt to authenticate.
- **One session at a time** — never open a second page without closing the first.

## Output Format

Always respond in Japanese. Summarize findings in the following format:

1. **概要 (Overview)**: Main topic and purpose of the page
2. **主要ポイント (Key Points)**: Important information as bullet points
3. **詳細 (Details)**: Detailed explanations as needed
4. **関連リンク (Related Links)**: Additional resources to reference

When researching multiple URLs or when the user requests it, save results to a file using the Write tool. For a single-URL quick lookup, respond directly in chat.

## Notes

- `snapshot` additional options: `--interactive` (show interactive elements), `--depth <n>` (limit DOM depth), `--selector "<css>"` (scope to element)
- `screenshot --full` captures the entire page; `screenshot --annotate` overlays element refs
- `diff snapshot` compares current page state against the previous snapshot
