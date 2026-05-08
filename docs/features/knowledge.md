# Knowledge

## Purpose

Knowledge has three implemented families:

- `memory`: durable notes for facts, preferences, and rules.
- `source_file`: operator-managed files indexed for scoped retrieval (RAG path).
- `reference_file`: operator-managed fixed files used as templates, examples, headers, footers, and style assets.

Knowledge is managed directly by the Knowledge domain. Source files and
reference files are not required Artifacts.

Primary operator surface: `/knowledge`.

## Who Uses It

- Operators use the Knowledge UI to create, edit, filter, and delete memories.
- Operators upload and manage source files and reference files in the same Knowledge surface.
- Lemmings use `knowledge.store` (memory-only), `knowledge.search`, and `knowledge.read` for scoped retrieval and reads.
- Developers use `LemmingsOs.Knowledge` for scoped CRUD/index/retrieval.

## Scope Model

Knowledge items are scoped to:

```text
World -> City -> Department -> Lemming
```

| Scope | Persisted IDs | Visible to |
|---|---|---|
| World | `world_id` | World + descendants |
| City | `world_id`, `city_id` | That City and descendants |
| Department | `world_id`, `city_id`, `department_id` | That Department and descendants |
| Lemming | `world_id`, `city_id`, `department_id`, `lemming_id` | That Lemming (plus same-department descendant views where applicable) |

Important rules:

- Cross-World visibility is not allowed.
- Sibling City/Department/Lemming data is excluded.
- Downward inheritance applies for effective visibility.
- `lemming_type` is only a tool-alias for `lemming`; there is no separate table.

## Operator UI

The same Knowledge LiveView is also embedded in scoped tabs:

- City detail Knowledge tab
- Department detail Knowledge tab
- Lemming detail Knowledge tab

Current UI behavior:

- The global `/knowledge` page lists all active memories across scopes.
- Source-file management appears on the same page with dedicated list/filter/actions.
- Reference-file management appears on the same page with dedicated list/filter/actions.
- Scoped embedded views list memories under the selected scope, including descendants for broader scopes.
- Operators can create a memory after selecting a valid scope.
- The global page can edit or delete any listed memory by resolving the memory's owning scope.
- Scoped embedded views can edit or delete only local memories for that selected scope; inherited and descendant rows render edit/delete controls disabled.
- Operators can edit `title`, `content`, and `tags`.
- Operators can filter by title/tag text, `source` (`user` or `llm`), and `status` (`active`).
- Pagination defaults to 25 rows per page.
- A direct deep link `/knowledge?memory_id=<uuid>` opens the memory form for that memory.

Rows show:

- title and truncated content
- owner scope label (`World`, `City`, `Department`, `Lemming`)
- source badge (`USER` or `LLM`)
- ownership relationship (`Local`, `Inherited`, or `Descendant`)
- timestamp and tags
- links back to owning City, Department, or Lemming when available

## Reference Files

Reference files are fixed reusable inputs for generation workflows. They are
selected by metadata and scope availability, not by chunk embeddings.

### Ingestion Paths

Implemented entry points:

- Upload from Knowledge UI (`create_reference_file_upload/3` stores managed bytes + metadata).
- Registration from existing managed references (`create_reference_file/2` with `storage_ref`).
- Explicit operator-approved Artifact promotion (`promote_artifact_to_reference_file/3`).

Reference-file rows are created as:

- `knowledge_items.kind = "reference_file"`
- `knowledge_items.source = "user"`
- `knowledge_items.status = "active"`
- `knowledge_reference_files.reference_ref` as stable safe identifier (`kref:<knowledge_item_id>` by default)

### Metadata and Lifecycle

Reference-file metadata includes:

- `title` and optional summary/description in `knowledge_items.content`
- flexible `reference_file_type` (not DB enum)
- optional `tags`
- scope ownership (`world/city/department/lemming`)
- optional `artifact_id` provenance when explicitly promoted from an Artifact

Lifecycle statuses:

- `active`
- `archived`

Archived reference files remain persisted but are excluded from normal Lemming
availability/search/read results.

### Retrieval Tools

- `knowledge.search`:
  - supports `kind: "reference_file"` for metadata-first lookup.
  - supports filters: `query`/`q`, `reference_file_type`/`type`, `tags`, `status`, `owner_scope`, `limit`, `offset`.
  - defaults to caller effective scope and enforces hierarchy visibility.
  - returns safe descriptor-oriented rows without storage refs/paths/checksums.
- `knowledge.read`:
  - supports reference identifiers by `reference_ref` or `knowledge_item_id`.
  - returns bounded text when directly readable.
  - uses existing safe extraction path for supported non-text formats (for example PDF/Office-like content).
  - returns descriptor-only safe output (`content_status`) when content is unavailable/unreadable.

Reference-file reads do not create source-file chunks, embeddings, or vector
records.

### Availability Guidance

Reference-file availability is metadata-only:

- use `search_reference_files/2` (or `list_available_reference_files/2`) to
  list what is currently in scope.
- prefer matching by `reference_file_type`, tags, and title before generating
  structure/style from scratch.

### Knowledge Boundary vs Artifacts

- Artifacts are durable generated outputs in the Artifacts domain.
- Reference files are Knowledge-managed reusable inputs.
- An Artifact becomes a reference file only through explicit operator-approved
  promotion.
- After promotion, reference-file reads/searches use Knowledge-managed storage.
  Optional Artifact provenance does not become the storage contract.

## Source Files

### Ingestion Paths

Implemented entry points:

- Upload from Knowledge UI (`create_source_file_upload/3` stores managed bytes + metadata).
- Registration from existing managed references (`create_source_file/2` with `storage_ref`).
- URL/HTML extraction helper exists (`ExtractionService.extract_url/1` via Trafilatura capability).

Source-file rows are created as:

- `knowledge_items.kind = "source_file"`
- `knowledge_items.source = "user"`
- `knowledge_items.status = "pending_index"`
- `knowledge_source_files.extraction_status = "pending"`
- `knowledge_source_files.indexing_status = "pending"`

### Lifecycle and Statuses

Indexing pipeline (`run_source_file_indexing/1`):

1. `extracting`
2. `chunking`
3. `embedding`
4. `ready`

Failure/status branches:

- PDF with insufficient extracted text becomes `needs_ocr`.
- Extraction/chunking/embedding failures become `failed` with safe `failure_reason`.
- Operator action can set `archived`.
- Retry action resets to `pending`, deletes previous chunks, and re-enqueues indexing.

Retrieval only uses ready rows/chunks:

- `knowledge_items.status == "ready"`
- `source_files.indexing_status == "ready"`
- `source_files.extraction_status == "ready"`
- chunk embedding present

### Retrieval Tools

- `knowledge.search`:
  - Scope-safe vector retrieval over ready source-file chunks.
  - Supports `query`, optional `source_file_type`, optional `tags`, optional `top_k` (default `5`, max `20`).
  - Returns safe metadata + snippet, never raw storage paths/refs.
- `knowledge.read`:
  - Scope-safe read of one chunk by `chunk_ref`.
  - Bounded content (`max_chars` default `4000`, max `8000`).
  - Safe not-found response on inaccessible/unknown refs.

`knowledge.store` remains memory-only and rejects source-file-specific fields.

## `knowledge.store` (Memory Only)

`knowledge.store` lets a Lemming persist one memory note from runtime execution.

Allowed input fields:

| Field | Required | Notes |
|---|---:|---|
| `title` | yes | Non-empty string, max 200 characters after persistence validation |
| `content` | yes | Non-empty string, max 10,000 characters after persistence validation |
| `tags` | no | List of strings or comma-separated string |
| `scope` | no | String scope name or explicit ancestry map |

Minimal call:

```json
{
  "title": "ACME - email summary language",
  "content": "Client ACME prefers short email summaries in Portuguese.",
  "tags": ["customer:ACME", "language:pt-BR"]
}
```

Default behavior:

- Stores a `kind = "memory"` item.
- Stores with `source = "llm"` and `status = "active"`.
- Defaults scope to the current Lemming.
- Records creator metadata when runtime instance data is available.
- Rejects fields for future Knowledge families, including `category`, `type`, `artifact_id`, and file paths.

Successful result shape:

```json
{
  "knowledge_item_id": "<uuid>",
  "status": "stored",
  "scope": "lemming"
}
```

The result intentionally excludes raw hierarchy IDs, WorkArea paths, runtime
state, and memory content beyond the normalized tool preview.

### Scope Hints

A Lemming may request a broader scope only within its current execution ancestry.
Supported string hints are:

- `world`
- `city`
- `department`
- `lemming`
- `lemming_type` as an alias for `lemming`

Explicit map hints must match the current ancestry exactly for the requested
level:

```json
{
  "title": "City language policy",
  "content": "Use Portuguese for customer-facing summaries in this City.",
  "scope": {
    "world_id": "<current-world-id>",
    "city_id": "<current-city-id>"
  }
}
```

Invalid or cross-scope hints return `tool.knowledge.invalid_scope` and do not
create a memory.

## Configuration

Source-file defaults and runtime controls:

| Config | Default |
|---|---|
| `:knowledge_source_file_storage.root_path` | `priv/runtime/knowledge_storage` (runtime override: `LEMMINGS_KNOWLEDGE_SOURCE_FILE_STORAGE_ROOT`) |
| `:knowledge_source_file_storage.max_file_size_bytes` | `10 MB` in `config/config.exs`, `100 MB` runtime fallback |
| `:knowledge_chunking.chunk_size` | `1200` (`LEMMINGS_KNOWLEDGE_CHUNK_SIZE`) |
| `:knowledge_chunking.overlap` | `200` (`LEMMINGS_KNOWLEDGE_CHUNK_OVERLAP`) |
| `:knowledge_chunking.max_chunks` | `500` (`LEMMINGS_KNOWLEDGE_MAX_CHUNKS`) |
| `:knowledge_tools_runner.timeout_ms` | `30000` (`LEMMINGS_KNOWLEDGE_EXTRACTION_TIMEOUT_MS`) |
| `:knowledge_tools_runner.max_extracted_chars` | `500000` (`LEMMINGS_KNOWLEDGE_MAX_EXTRACTED_CHARS`) |
| `:knowledge_embeddings.provider` | `ollama` (`LEMMINGS_KNOWLEDGE_EMBEDDING_PROVIDER`) |
| `:knowledge_embeddings.base_url` | `http://127.0.0.1:11434/v1` (`LEMMINGS_KNOWLEDGE_EMBEDDING_BASE_URL`) |
| `:knowledge_embeddings.model` | `nomic-embed-text` (`LEMMINGS_KNOWLEDGE_EMBEDDING_MODEL`) |
| `:knowledge_embeddings.dimensions` | `1536` (`LEMMINGS_KNOWLEDGE_EMBEDDING_DIMENSIONS`) |
| `:knowledge_embeddings.timeout_ms` | `30000` (`LEMMINGS_KNOWLEDGE_EMBEDDING_TIMEOUT_MS`) |
| `:knowledge_embeddings.api_key_env` | `OPENAI_API_KEY` (`LEMMINGS_KNOWLEDGE_EMBEDDING_API_KEY_ENV`) |
| `:knowledge_embeddings.api_key` | unset by default (`LEMMINGS_KNOWLEDGE_EMBEDDING_API_KEY`) |

The OpenAI-compatible embedder sends an authorization header only when an API
key value is configured. Local Ollama can run without one; hosted providers
usually require one through environment configuration.

When `:knowledge_embeddings.provider` is `ollama`, vectors are auto-aligned to
the configured `:dimensions` (padding/truncating as needed) so indexing remains
compatible with the fixed pgvector column size.

Oban queue:

- Worker: `LemmingsOs.Knowledge.SourceFiles.Workers.SourceFilesIndexingWorker`
- Queue: `:knowledge_indexing`
- Default concurrency: `1` (configured in `config/config.exs`)

### Tools Runner Sidecar

The repository ships a lightweight sidecar image at
`docker/images/tools-runner/Dockerfile`:

- Base: `python:3.12-slim`
- Installed: MarkItDown CLI (`markitdown`), Trafilatura CLI (`trafilatura`), Poppler `pdftotext`
- Purpose: capability-only extraction runtime

Safety model:

- Only named allowlisted capabilities are callable (`markitdown_extract_file`, `trafilatura_extract_url`, `pdftotext_extract_file`).
- Commands execute as structured `System.cmd(command, argv)`; no shell command strings.
- Arguments must be non-empty strings.
- Enforced timeout (`timeout_ms`) and extracted output clamp (`max_extracted_chars`).
- No arbitrary shell execution path in Knowledge extraction.

### Why Apache Tika Is Not Included In v1

- Current v1 extraction coverage is intentionally narrow and deterministic around
  three CLI capabilities above.
- This avoids a heavier JVM/Tika dependency surface in the first release.
- Existing tests validate current extraction behavior without Tika.

### OCR Boundary

- OCR is not implemented in v1.
- Image-only/scanned PDFs that fail both MarkItDown and `pdftotext` text
  extraction transition to `needs_ocr`.
- `needs_ocr` rows are excluded from retrieval until future OCR work exists.

## Observability and Safe Data Handling

- Indexing status/failure fields are persisted for operator troubleshooting.
- Tool outputs and retrieval responses avoid leaking raw storage paths/refs.
- `knowledge.read` is the only tool path returning chunk content, and it is bounded.
- Memory audit events intentionally omit memory content.

## Backup and Operations

Source-file data spans filesystem + Postgres:

- Bytes: configured `knowledge_source_file_storage.root_path` tree.
- Metadata/status: `knowledge_items` and `knowledge_source_files`.
- Retrieval chunks/embeddings: `knowledge_source_file_chunks`.

Reference-file data spans filesystem + Postgres:

- Bytes: configured `knowledge_reference_file_storage.root_path` tree.
- Metadata: `knowledge_items` and `knowledge_reference_files`.
- No retrieval chunk/embedding table is created for reference files.

Operational guidance:

- Back up storage bytes and DB metadata/chunks together.
- Restore consistency by keeping DB rows and storage tree from compatible backup points.
- Treat storage roots and DB backups as sensitive operator data.

## Developer Notes

Primary modules:

- `LemmingsOs.Knowledge` owns memory CRUD, effective listing, exact-scope validation, and lifecycle events.
- `LemmingsOs.Knowledge` also owns source-file lifecycle, chunk retrieval, retry/archive actions.
- `LemmingsOs.Knowledge` also owns reference-file create/upload/edit/archive, availability/search/read, and Artifact promotion.
- `LemmingsOs.Knowledge.KnowledgeItem` defines the shared `knowledge_items` schema for memory rows.
- `LemmingsOs.Tools.Adapters.Knowledge` validates model-provided `knowledge.store` arguments and delegates persistence to `LemmingsOs.Knowledge`.
- `LemmingsOsWeb.KnowledgeLive` renders global and embedded memories/source-files/reference-files management surfaces.

Context APIs:

- `create_memory/3` creates a memory at an exact scope and assigns runtime-owned fields.
- `update_memory/3` changes only `title`, `content`, and `tags` at exact ownership scope.
- `delete_memory/2` hard deletes a memory at exact ownership scope.
- `list_effective_memories/2` returns inherited effective visibility rows.
- `list_scope_memories/2` returns rows under a concrete scope and descendants for broader scopes.
- `list_all_memories/1` supports the global operator inventory.
- `get_memory/3` supports visible or local read mode.

Safe boundary details:

- User-supplied hierarchy IDs in create attrs are rejected unless they exactly match the scope object.
- Unsupported `knowledge.store` fields fail closed before persistence.
- Audit payloads omit memory `content`, WorkArea paths, and runtime internals.
- Event-write failures are logged and do not roll back an otherwise successful memory write.

## Deletion and Events

Deletion is a hard delete in this MVP. There is no archive, unarchive, trash,
soft-delete, or restore workflow.

Memory lifecycle actions emit audit-family events when event recording succeeds:

- `knowledge.memory.created`
- `knowledge.memory.updated`
- `knowledge.memory.deleted`
- `knowledge.memory.created_by_llm`

Event payloads include safe identifiers and metadata such as scope IDs, source,
status, and creator references. They intentionally do not include memory content.

## Chat Notification

When `knowledge.store` succeeds and the runtime provides an actor instance ID,
the adapter attempts to persist an assistant message in the instance transcript
and broadcast it to the LiveView.

Notification content follows this shape:

```text
Memory added:
<title>
<content preview>
View or edit: /knowledge?memory_id=<uuid>
```

The instance chat UI detects the `/knowledge?memory_id=<uuid>` path and renders a
`View/Edit memory` link.

Notification is best effort. If the message insert or PubSub broadcast fails,
the stored memory remains committed and the tool still returns success.

## Known Limits and Future Work

- Source-file OCR is not implemented (`needs_ocr` is terminal in v1).
- No Apache Tika integration in v1.
- No source-file soft-delete restore flow (`archived` exists; hard delete flow is limited).
- No reference-file hard-delete or restore/recover workflow in v1.
- Memory list filters remain title/tag oriented (no semantic memory retrieval path).
