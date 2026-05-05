# Tools Catalog

## Purpose

This page is a human-readable catalog of first-party runtime tools currently
available to Lemmings.

Catalog scope:

- Tool IDs and purpose
- Supported inputs/outputs
- Safety and boundary expectations
- Runtime and deployment notes where relevant

## Current Runtime Tools

| Tool ID | Domain | Purpose | Typical Output |
|---|---|---|---|
| `fs.read_text_file` | Filesystem | Read UTF-8 text files from the instance WorkArea | Text content + metadata |
| `fs.write_text_file` | Filesystem | Write UTF-8 text files into the instance WorkArea | Write confirmation + metadata |
| `web.search` | Web | Search the web and return short snippets | Search snippets |
| `web.fetch` | Web | Fetch one HTTP(S) URL | Response content/summary |
| `knowledge.store` | Knowledge | Store a scoped memory note for future use | Stored memory ID + scope |
| `documents.markdown_to_html` | Documents | Convert WorkArea Markdown file to WorkArea HTML file | `text/html` file + byte size |
| `documents.print_to_pdf` | Documents | Print supported WorkArea source file to WorkArea PDF via Gotenberg | `application/pdf` file + byte size |

## Global Tool Boundaries

- Agent-controlled file paths must be WorkArea-relative.
- Absolute paths and traversal attempts are rejected.
- Tool results return normalized success/error envelopes.
- Runtime/deployment config is operator controlled (not agent controlled).

## Filesystem Tools

### `fs.read_text_file`

- Reads UTF-8 text files inside WorkArea.
- Rejects paths outside WorkArea boundaries.

### `fs.write_text_file`

- Writes UTF-8 text files inside WorkArea.
- Rejects paths outside WorkArea boundaries.

## Web Tools

### `web.search`

- Executes controlled web search queries.
- Returns concise search snippets for model consumption.

### `web.fetch`

- Fetches one HTTP(S) URL via `Req`.
- Rejects invalid URL shapes.

## Knowledge

### `knowledge.store`

Stores one Knowledge memory note. This tool is memory-only in the current MVP.

Required inputs:

- `title`: non-empty memory title
- `content`: non-empty memory body

Optional inputs:

- `tags`: list of strings or comma-separated string
- `scope`: one of `world`, `city`, `department`, `lemming`, `lemming_type`, or an explicit scope map matching the current runtime ancestry

Minimal call:

```json
{
  "title": "ACME - email summary language",
  "content": "Client ACME prefers short email summaries in Portuguese.",
  "tags": ["customer:ACME", "language:pt-BR"]
}
```

Result details include:

- `knowledge_item_id`
- `status` (`stored`)
- `scope`

Safety notes:

- Defaults to the current Lemming scope.
- Rejects cross-ancestry scope hints.
- Rejects file/future-family fields such as `category`, `type`, `artifact_id`, and `source_path`.
- Persists `source = "llm"` and `status = "active"`.
- Chat notification is best effort; notification failure does not roll back the stored memory.

See [Knowledge Memories](knowledge.md) for scope semantics and operator behavior.

## Documents

### `documents.markdown_to_html`

Converts a Markdown WorkArea file to HTML.

Required inputs:

- `source_path`: WorkArea-relative `.md` file

Optional input:

- `markdown_path`: Compatibility alias for `source_path` (use `source_path` for new calls)
- `output_path`: WorkArea-relative `.html` or `.htm` file (default: `source_path` with `.html` extension)
- `overwrite` (`true` default)

Minimal call:

```json
{"source_path":"notes/triage_document.md"}
```

Result details include:

- `source_path`
- `output_path`
- `content_type` (`text/html`)
- `bytes`

### `documents.print_to_pdf`

Prints a supported WorkArea source file to a WorkArea `.pdf` using Gotenberg.

Required inputs:

- `source_path`: WorkArea-relative source file

Optional inputs:

- `output_path`: WorkArea-relative `.pdf` file (default: `source_path` with `.pdf` extension)
- `overwrite` (`true` default)
- `print_raw_file` (`false` default)
- `header_path`, `footer_path` (WorkArea-relative `.html` / `.htm`)
- `style_paths` (list of WorkArea-relative `.css`)
- `paper_size` (`A4`, `A3`, `A5`, `LETTER`, `LEGAL`, `TABLOID`)
- `landscape` (`false` default)
- `margin_top`, `margin_bottom`, `margin_left`, `margin_right`

Minimal call:

```json
{"source_path":"notes/report.html"}
```

Supported source formats:

- `.html`, `.htm`
- `.md`
- `.txt`
- `.png`, `.jpg`, `.jpeg`, `.webp`

Result details include:

- `source_path`
- `output_path`
- `content_type` (`application/pdf`)
- `bytes`

### Documents asset resolution order

For print assets (`header`, `footer`, `styles`):

1. Explicit tool arguments
2. Conventional sibling files in WorkArea (`*_pdf_header.html`, `*_pdf_footer.html`, `*_pdf.css`)
3. Operator fallback assets from env config

Fallback constraints:

- Must resolve under `priv/documents/`
- Must be regular files
- Symlinks are rejected
- Extension checks are enforced (`.html`/`.htm` for header/footer, `.css` for style)
- Size checks are enforced via documents limits

### Documents configuration

Runtime config lives in `config/runtime.exs` under `:lemmings_os, :documents`.

| Env var | Default |
|---|---|
| `LEMMINGS_GOTENBERG_URL` | `http://gotenberg:3000` |
| `LEMMINGS_DOCUMENTS_PDF_TIMEOUT_MS` | `30000` |
| `LEMMINGS_DOCUMENTS_PDF_CONNECT_TIMEOUT_MS` | `5000` |
| `LEMMINGS_DOCUMENTS_PDF_RETRIES` | `1` |
| `LEMMINGS_DOCUMENTS_MAX_SOURCE_BYTES` | `10485760` |
| `LEMMINGS_DOCUMENTS_MAX_PDF_BYTES` | `52428800` |
| `LEMMINGS_DOCUMENTS_MAX_FALLBACK_BYTES` | `1048576` |
| `LEMMINGS_DOCUMENTS_DEFAULT_HEADER_PATH` | unset |
| `LEMMINGS_DOCUMENTS_DEFAULT_FOOTER_PATH` | unset |
| `LEMMINGS_DOCUMENTS_DEFAULT_CSS_PATH` | unset |

### Documents safety notes

- Gotenberg should remain private/internal in default deployment.
- Remote/unsafe asset references are blocked before backend conversion.
- Outputs are written atomically (temp file + rename).
- `overwrite: false` enables conflict protection, but not a strict race-free lock.

### Documents non-goals (MVP)

- No artifact persistence/promotion
- No remote asset support or network allowlist
- No templates (`EEx`, `HEEx`, `Liquid`)
- No email/e-signature/legal validation flow
- No advanced image layout engine
