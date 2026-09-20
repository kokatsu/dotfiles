---
name: browser-research
description: Research web pages with agent-browser when normal fetching is insufficient or rendered content and browser navigation are needed.
allowed-tools:
  - Bash(agent-browser:*)
  - Read
  - Write
---

# Browser Research Skill

Research web pages using agent-browser CLI and summarize content. A supplied URL alone does not require this skill when ordinary fetching already answers the question. Explicit user instructions take precedence over workflow preferences.

## Usage

```text
/browser-research <URL> [research topic or question]
```

## Workflow

### 1. Read the page (default — no browser)

```bash
agent-browser read "<URL>" --max-output 20000
```

`read` never launches Chrome. It negotiates `Accept: text/markdown`, tries the `.md` variant,
looks for the nearest `llms.txt`, and falls back to readable text extracted from the HTML.
The markdown it returns keeps headings, bullet lists, and code blocks, so it is both cheaper
and more faithful than scraping rendered text.

Useful variants:

| Purpose | Command |
|---------|---------|
| Read one section only | `agent-browser read "<URL>" --filter "<heading text>"` |
| See the page structure first | `agent-browser read "<URL>" --outline` |
| List a docs site's `llms.txt` links | `agent-browser read "<URL>" --llms index` |

**Go to step 2 when** `read` exits non-zero (e.g. `Read failed with HTTP 403` — some sites
block non-browser clients), returns nothing useful, or the content only appears after
JavaScript runs. Interaction (clicking, dismissing banners, following links, tabs) always
requires step 2.

### 2. Fall back to a browser session

Use a session owned by this task; do not close an unrelated existing session. Consult `agent-browser --help` for session selection when isolation is needed. Open the page:

```bash
agent-browser open "<URL>" && agent-browser wait --load networkidle --timeout 15000
```

If `open` fails, verify the URL and retry once when useful. If it still fails, report the inaccessible source and continue with other relevant sources when they can answer the question.

If `wait` times out: proceed anyway — the page may still be usable.

**Next, choose the extraction method based on your purpose:**

| Purpose | Command | When to use |
|---------|---------|-------------|
| Read the rendered page as markdown | `agent-browser read` | No URL argument: reads the active tab's rendered DOM, including client-side updates and auth state |
| Read article/docs text | `agent-browser eval "document.body.innerText"` | Plain text of the rendered page. Includes navigation chrome and loses structure |
| Understand page structure | `agent-browser snapshot -c` | Need to see layout, navigation, or element refs for interaction |
| Find interactive elements | `agent-browser snapshot -i -c` | Need to click links, buttons, or fill forms |
| List links with URLs | `agent-browser snapshot -i -c -u` | Need link destinations (href) without an extra `get attribute` round-trip |

Use `snapshot` only when you need structure or element refs.

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

### 3. Close when done

Only needed when step 2 opened a session:

```bash
agent-browser close
```

## Deeper investigation

Most research finishes with the steps above. Read [reference.md](reference.md) when you need any of these:

- The full `read` option reference (`--raw`, `--require-md`, `--llms full`, `--timeout`)
- Text from a specific element, page metadata, or finding elements by role/text/label
- Scrolling to load more content on long pages
- Watching network traffic to locate the JSON endpoint behind a SPA
- Following links, going back, or researching several URLs in tabs
- Saving the page as a PDF
- The full `snapshot` flag reference and other commands

## Critical Rules

- **Prefer `read` for text retrieval**. Open a browser directly when interaction or JavaScript rendering is already known to be necessary.
- **Always close a session you opened** — every `open` must have a matching `close`.
- **Read-only by default** — never submit forms or enter data. Clicking is allowed only for passive navigation: dismissing cookie/consent banners, following links, expanding collapsed sections, or switching tabs. Do not click buttons that trigger writes, purchases, or state changes.
- **No guessing** — do not fabricate or assume page content; only report what `read`/`snapshot`/`get`/`eval` return.
- **Authentication pages** — do not attempt to authenticate as part of research. Report the inaccessible source and use relevant public sources if sufficient; ask for accessible source material when the answer depends on the protected page.
- **Minimize tokens** — prefer `read` (or `read --filter`) over full-page extraction, and use `--max-output` for large pages.

## Output

Lead with the answer to the research question, then the supporting points and the source URLs the reader may want to follow. Respond directly in chat unless the user requested a saved artifact.
