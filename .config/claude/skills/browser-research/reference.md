# Browser Research Reference

Deeper agent-browser operations. Read this only when the quick path in `SKILL.md`
(read → fall back to open → extract → close) is not enough.

Commands below that act on a page assume a session opened in `SKILL.md` step 2 —
do not re-open it, and end it with a matching `agent-browser close`. The `read`
options in the next section need no session.

## Read options

`read` fetches without launching Chrome, in this order: `Accept: text/markdown`
→ the same URL with `.md` appended → the nearest ancestor `llms.txt` → readable
text extracted from the HTML.

```bash
agent-browser read "<URL>" --raw          # response body as-is, no HTML extraction
agent-browser read "<URL>" --require-md   # fail unless the server returns text/markdown
agent-browser read "<URL>" --llms full    # read the nearest ancestor llms-full.txt
agent-browser read "<URL>" --timeout 15000
agent-browser read "<URL>" --json
```

Omit the URL to read the rendered DOM of the active tab instead — this is the
cheapest way to get markdown out of a page that needed a browser to render.
`--llms` and `--require-md` with no URL use the active tab's URL.

## Get detailed content

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

## Handle long pages

Scroll to load more content:

```bash
agent-browser scroll down 500 && agent-browser snapshot -c
```

Scroll a specific element into view:

```bash
agent-browser scrollintoview "@ref" && agent-browser snapshot -c
```

## Observe network traffic (SPAs / API-heavy pages)

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

## Navigate to linked pages

Click a link:

```bash
agent-browser click "@ref" && agent-browser wait --load networkidle --timeout 15000 && agent-browser snapshot -c
```

Go back:

```bash
agent-browser back && agent-browser snapshot -c
```

## Research additional URLs

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

## Save page as PDF

When the user requests a saved copy:

```bash
agent-browser pdf "/path/to/output.pdf"
```

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
