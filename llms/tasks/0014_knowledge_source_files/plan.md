# Knowledge Source Files Implementation Plan

## Status

- **Issue**: GitHub #40 — Knowledge source files: upload, extract, index, search, and read
- **Parent story**: GitHub #38 — Knowledge Repository: scoped source files, reference files, and memories
- **Depends on**: GitHub #39 — Knowledge core + memories
- **PR split**: Ticket 2 of 3

---

## 1. Goal

Add source-file Knowledge items that users can upload or explicitly register as durable source material for Lemmings.

This PR must deliver a working first retrieval loop:

```text
user adds source file
  -> app stores the original file through Knowledge-managed storage
  -> app extracts text through private Tika
  -> app chunks extracted text with overlap
  -> app embeds and indexes chunks in PostgreSQL with pgvector
  -> Lemmings use knowledge.search and knowledge.read inside allowed scope
```

Source files are not Artifacts. They are Knowledge-managed documents used for retrieval, such as policies, price lists, product catalogs, brand guidelines, books, client material, and example writing.

---

## 2. Business Need

LemmingsOS needs a safe way for operators to provide larger durable context than a memory can hold.

Memories are suitable for short reusable facts or rules. They are not suitable for multi-page documents, customer files, product lists, or reference books. Without source files, Lemmings can store small notes but cannot reliably search and read larger user-provided material.

---

## 3. Current Architecture Alignment

The repo already has:

- `LemmingsOs.Knowledge` as the memory-focused Knowledge context.
- `LemmingsOs.Knowledge.KnowledgeItem` backed by `knowledge_items`.
- `kind = "memory"`, `source = "user" | "llm"`, and `status = "active"` as the current persisted Knowledge contract.
- Scope columns: `world_id`, `city_id`, `department_id`, and `lemming_id`.
- Product-facing "Lemming Type" scope is currently represented by the existing `lemming_id` scope until/unless the codebase introduces a separate Lemming Type entity.
- `knowledge.store` as a memory-only tool.
- Artifact storage and promotion as a separate domain.
- Durable `LemmingsOs.Events` plus Logger/telemetry conventions for safe observability.
- `Req` for HTTP clients.

This task extends the existing Knowledge boundary. It must not create a parallel Knowledge domain, and it must not force source files through the Artifact domain.

---

## 4. Product Scope

### In Scope

This PR covers:

- Source file Knowledge items with `kind = "source_file"` or the closest existing discriminator naming chosen during implementation.
- User upload or registration from the Knowledge management surface.
- Optional user-approved ingestion from an existing Artifact.
- Knowledge-managed storage for original source files.
- Text extraction through Apache Tika.
- Chunk creation with ordering and overlap.
- Chunk embedding and PostgreSQL/pgvector indexing.
- Metadata, tag, scope, and status filters for source files.
- Lemming-facing `knowledge.search` for source file chunks.
- Lemming-facing `knowledge.read` for selected chunk content.
- UI visibility for indexing status, failures, retry, and archive/delete where supported by the Knowledge lifecycle.
- Safe durable events or telemetry according to existing project conventions.

### Out of Scope

This PR does **not** include:

- Reference file implementation.
- Template engine behavior.
- Automatic LLM promotion of generated files into Knowledge.
- Requiring source files to be Artifacts.
- External vector databases such as Qdrant.
- Redis as a retrieval backend.
- LangChain or LlamaIndex sidecars.
- OCR-heavy guarantees.
- Table-perfect extraction guarantees.
- Advanced reranking.
- Full document editing or annotation.
- Public file sharing or public source file download links.
- Adding Oban or another job dependency unless explicitly approved.

---

## 5. Decisions

### Source Files Are Knowledge, Not Artifacts

- A source file is a Knowledge item whose purpose is retrieval.
- Source files must not require `artifact_id`.
- A source file may record optional Artifact provenance only when a user explicitly chooses to ingest an existing Artifact.
- LLM-created runtime files must not become source file Knowledge automatically.

### Divergence From Original Issue Text

The original issue described source files as requiring an Artifact reference. This plan intentionally changes that decision.

Source files are Knowledge-managed files and do not require `artifact_id`. `artifact_id` is optional provenance only when a user explicitly ingests an existing Artifact.

### Shared Knowledge Model

- Reuse the existing Knowledge context and scope validation patterns.
- Extend the current memory-only model deliberately; do not overload memory semantics.
- The existing `knowledge_items.content` field is memory-oriented and capped for short content. Full extracted document text should not be stored there by default.
- Source file metadata should live on `knowledge_items` where it fits and in source-file-specific tables where it does not.
- Chunk content belongs in a chunk/index table, not in the top-level Knowledge item row.

### Scope Model

Source files use the same scope hierarchy as memories:

- World
- City
- Department
- Lemming, which currently represents product-facing "Lemming Type" scope until/unless a separate Lemming Type entity exists

Visibility rules:

| Source file scope | Visible to |
|---|---|
| World | Allowed descendants in the same World |
| City | That City and descendants |
| Department | That Department and descendants |
| Lemming | That Lemming only |

Cross-World access is never allowed. Sibling City and sibling Department access is denied by default. Search and read must enforce scope server-side; UI filtering is not sufficient.

### Storage

- Source files use Knowledge-managed storage with opaque storage refs.
- Storage refs must not expose absolute paths, configured roots, raw upload temp paths, or workspace paths.
- The implementation may reuse storage safety ideas from Artifact local storage, but it should keep a Knowledge-named storage boundary so source files do not become Artifacts by accident.
- Original bytes stay outside the database.

### Extraction

- Apache Tika is the first extraction service.
- Tika must be private by default in Docker Compose.
- Extraction has bounded timeout and bounded output size.
- Extraction failures update status and emit safe observability; they must not crash the app.

### Indexing Backend

- PostgreSQL with pgvector is the v1 retrieval backend.
- Do not introduce an external vector database or RAG framework.
- Embedding generation must sit behind a small application boundary so tests can use deterministic fake embeddings and future providers can be swapped.
- Embedding provider configuration and vector dimensions must be explicit and validated before indexing.

### Ready-Only Retrieval

`knowledge.search` must only return source file chunks whose Knowledge item and source file index are ready.

Failed, pending, extracting, embedding, archived, or deleted items are excluded from retrieval.

### Background Processing

- Upload/registration must return quickly.
- Extraction, chunking, embedding, and indexing must run after the initial request.
- The first implementation may use the simplest supervised background mechanism already compatible with the app.
- A new durable job system is out of scope unless approved.
- Failed or interrupted indexing must leave a clear status and support retry where practical.

### Tool Surface

- `knowledge.store` remains memory-only.
- Add source-file retrieval through `knowledge.search` and `knowledge.read`.
- Tool outputs must use the existing runtime success/error envelope.
- Tools must not expose raw storage refs, filesystem paths, full documents by default, embedding vectors, raw provider responses, or unrelated runtime state.

---

## 6. Implementation Guidance

The following details are intended to guide the implementation phase. They are not a replacement for the later task breakdown and can be adjusted if the codebase requires it.

### Data Model Direction

Expected additions:

#### `knowledge_items`

Extend the existing table/schema enough to represent source file ownership and lifecycle.

Likely changes:

- Allow `kind = "source_file"`.
- Add or support source file lifecycle statuses, such as `pending_index`, `extracting`, `chunking`, `embedding`, `ready`, `failed`, and `archived`.
- Avoid requiring memory-style full `content` for source files. If the existing column remains required in this PR, use a safe short summary/description placeholder rather than extracted document content.
- Keep `artifact_id` nullable and optional provenance-only.

#### Source File Metadata Table

Add a source-file-specific table when metadata does not belong cleanly on `knowledge_items`.

Recommended fields:

```text
knowledge_source_files
  id uuid primary key
  knowledge_item_id uuid not null
  source_file_type string not null
  original_filename string not null
  content_type string not null
  size_bytes bigint not null
  checksum string null
  storage_ref text not null
  extraction_status string not null
  indexing_status string not null
  failure_reason string null
  extracted_at utc_datetime null
  indexed_at utc_datetime null
  metadata jsonb not null default '{}'
  inserted_at utc_datetime not null
  updated_at utc_datetime not null
```

Suggested `source_file_type` values:

- `price_list`
- `contract`
- `policy`
- `branding`
- `product_catalog`
- `company_knowledge`
- `client_material`
- `example_email`
- `book`
- `other`

Keep the list small. Use tags for flexible metadata.

#### Chunk Table

Add a chunk/index table for retrieval.

Recommended fields:

```text
knowledge_source_file_chunks
  id uuid primary key
  knowledge_item_id uuid not null
  knowledge_source_file_id uuid not null
  chunk_index integer not null
  chunk_ref string not null
  content text not null
  content_hash string not null
  token_count integer null
  char_count integer not null
  embedding vector(<configured_dimension>) null
  metadata jsonb not null default '{}'
  inserted_at utc_datetime not null
  updated_at utc_datetime not null
```

Required constraints and indexes:

- Unique `(knowledge_source_file_id, chunk_index)`.
- Unique `chunk_ref`.
- Scope/filter indexes aligned with retrieval queries.
- pgvector index appropriate for the chosen operator class and dimensions.
- Metadata/tag filters must remain efficient enough for MVP usage.

### HTTP And pgvector Integration

- Use the existing `Req` library for Tika and embedding-provider HTTP calls unless the task breakdown identifies a repo-approved alternative.
- Prefer direct Ecto/PostgreSQL integration for pgvector over adding an Elixir dependency unless implementation proves a dependency is necessary and it is explicitly approved.
- Keep embedding generation behind a small behavior or boundary so tests can use deterministic fake embeddings.
- Keep vector dimensions and provider configuration centralized so migrations, indexing, and search cannot silently disagree.

### UI Implementation Guidance

When UI work is implemented, follow the existing Phoenix conventions unless the implementation task explicitly narrows the scope.

- Start LiveView pages with `<Layouts.app flash={@flash} ...>` where applicable.
- Use `to_form/2` and `<.form for={@form}>`.
- Use imported `<.input>` where practical.
- Add stable DOM IDs for upload forms, filters, retry buttons, and rows.
- Use `<.link navigate={...}>`, `<.link patch={...}>`, `push_navigate`, and `push_patch`.
- Preload associations before template access.
- Do not embed scripts in HEEx.

Expected UI states:

| Surface | State | Behavior |
|---|---|---|
| List | Empty | Explain no source files exist and show add action. |
| List | Populated | Show title, type, tags, scope, status, and updated time. |
| List | Filtered empty | Show no-results message and current filter summary. |
| Detail | Indexing | Show lifecycle status and explain search is unavailable until ready. |
| Detail | Ready | Show metadata, index summary, and management actions. |
| Detail | Failed | Show safe failure reason and retry action where practical. |
| Upload | Accepted | Confirm upload and show item as indexing. |
| Upload | Validation error | Preserve form input and show field-level errors. |

---

## 7. Functional Requirements

### FR-1 — Add Source Files

Users can add a source file from the Knowledge management surface.

Acceptance points:

- User selects a file.
- User selects an allowed scope.
- User selects a source file type.
- User may enter title, description, and tags.
- System creates a source file Knowledge item.
- System stores the original file through Knowledge-managed storage.
- System starts the indexing lifecycle without blocking the request.
- UI shows the item immediately with a non-ready status.

### FR-2 — Optional Artifact Ingestion

Users may add an existing Artifact to Knowledge only through an explicit action.

Acceptance points:

- UI requires user approval before ingestion.
- User selects source file type, scope, and tags.
- Source file storage receives its own Knowledge-managed copy or ref according to the storage boundary.
- Artifact provenance may be recorded, but source files do not require `artifact_id`.
- LLMs cannot directly add Artifacts to source file Knowledge.

### FR-3 — Extract Text

The system extracts text from supported files through private Tika.

Acceptance points:

- Extraction uses `Req` and configured Tika endpoint.
- Tika is not publicly exposed by default in Docker Compose.
- Extraction timeout is bounded.
- Extracted output size is bounded.
- Unsupported, empty, timed-out, or failed extraction marks the item failed or no-content according to the chosen lifecycle.
- Raw extracted full text is not logged or emitted in events.

### FR-4 — Chunk Extracted Text

Extracted text is split into retrieval-friendly chunks.

Acceptance points:

- Chunks preserve document order.
- Chunks include stable `chunk_ref` values.
- Chunks use overlap to reduce boundary loss.
- Chunk size and overlap defaults are configurable or centralized constants.
- Empty chunks are not persisted.
- Re-indexing replaces stale chunks safely.

### FR-5 — Embed And Index Chunks

Chunks are embedded and indexed in PostgreSQL.

Acceptance points:

- Each ready searchable chunk has persisted content.
- Each ready searchable chunk has an embedding with the configured dimension.
- pgvector is enabled through a migration.
- Search can use vector similarity plus metadata, tag, status, and scope filters.
- Failed embedding/indexing updates status without exposing provider responses.

### FR-6 — Search Source File Knowledge

`knowledge.search` supports source file chunks.

Conceptual input:

```json
{
  "query": "payment terms for ACME quotes",
  "kind": "source_file",
  "source_file_type": "price_list",
  "tags": ["customer:ACME"],
  "scope": "department",
  "top_k": 5
}
```

Conceptual output:

```json
{
  "results": [
    {
      "knowledge_item_id": "...",
      "chunk_ref": "...",
      "title": "ACME price list",
      "source_file_type": "price_list",
      "tags": ["customer:ACME"],
      "score": 0.82,
      "snippet": "...",
      "scope": {"type": "department"}
    }
  ]
}
```

Acceptance points:

- Only ready source file chunks are searchable.
- Results are scoped to the caller's allowed hierarchy.
- Search supports `top_k` with a safe max.
- Search supports type, tag, and metadata filters where practical.
- Search returns snippets, not full documents.
- Search does not reveal inaccessible content by count, id, title, or error detail.

### FR-7 — Read Source File Chunks

`knowledge.read` returns bounded chunk content selected from search results.

Conceptual input:

```json
{
  "chunk_ref": "...",
  "max_chars": 4000
}
```

Acceptance points:

- Read enforces scope independently from search.
- Read accepts a chunk ref or an allowed knowledge item/chunk selector.
- Read returns bounded content with safe metadata.
- Read does not expose raw storage refs or paths.
- Read returns not found or denied according to existing project conventions without confirming inaccessible content exists.

### FR-8 — Manage Source Files

Users can manage source file Knowledge from the Knowledge surface.

Acceptance points:

- List source files by accessible scope.
- Filter by text, source file type, tags, and status.
- Paginate with local Ecto queries; do not add a pagination dependency.
- View lifecycle status and safe failure reason.
- Edit title, description, source file type, and tags.
- Retry failed indexing where practical.
- Archive/delete removes the item from future retrieval.

---

## 8. Events And Observability

Use existing project conventions. Durable events through `LemmingsOs.Events` are appropriate for lifecycle actions that matter to users/operators. Logger and telemetry are appropriate for internal processing metrics.

Suggested durable event types:

- `knowledge.source_file.created`
- `knowledge.source_file.extraction_failed`
- `knowledge.source_file.indexed`
- `knowledge.source_file.index_failed`
- `knowledge.source_file.retry_requested`
- `knowledge.source_file.archived`
- `knowledge.source_file.deleted`
- `knowledge.source_file.searched`
- `knowledge.source_file.read`

Safe payload fields may include:

- `world_id`
- `city_id`
- `department_id`
- `lemming_id`
- `lemming_instance_id`
- `knowledge_item_id`
- `source_file_type`
- `status`
- `failure_reason`
- `chunk_count`
- `size_bytes`

Payloads, logs, telemetry metadata, and tool outputs must not include:

- absolute paths
- storage roots
- upload temp paths
- raw workspace paths
- full extracted content
- full chunk content except the intended bounded `knowledge.read` response
- embedding vectors
- raw embedding provider responses
- secrets
- exception dumps with sensitive runtime state

---

## 9. Test Plan

Run narrow tests first, then `mix format`, then `mix precommit` when implementation is complete.

Minimum coverage:

- Schema/changeset: source file kind/status/type validation and memory behavior remains intact.
- Storage: safe storage refs, unsafe filename/path rejection, no path leakage, checksum and size calculation.
- Upload/create: source file Knowledge item and metadata row are created at allowed scope.
- Artifact ingestion: explicit user action required, optional provenance recorded, no Artifact requirement.
- Tika extraction: success, timeout, unsupported/empty content, safe failure handling.
- Chunking: ordering, overlap, stable chunk refs, stale chunk replacement on retry.
- Embeddings: deterministic fake embedder in tests, dimension validation, provider failure handling.
- pgvector retrieval: vector search returns relevant ready chunks with filters.
- Scope: search/read deny cross-World, sibling City, sibling Department, and wrong Lemming access.
- Tools: `knowledge.search` and `knowledge.read` use the standard runtime envelope and safe errors.
- UI: LiveView upload/list/filter/status/retry behavior with stable selectors.
- Observability: durable events/logs/telemetry exclude paths, full content, vectors, provider responses, and secrets.
- Regression: existing memory tests and `knowledge.store` behavior remain unchanged.

---

## 10. Acceptance Criteria

- [ ] Source files are represented as Knowledge items, not required Artifacts.
- [ ] Existing memories and `knowledge.store` remain memory-only and continue to pass current tests.
- [ ] Source file storage persists original bytes outside the database with opaque Knowledge storage refs.
- [ ] Raw paths, storage roots, upload temp paths, and workspace paths are not exposed in UI, logs, events, or tool outputs.
- [ ] Users can add a source file with allowed scope, type, title, description, and tags.
- [ ] Upload/registration returns quickly and indexing continues after the request.
- [ ] Tika extraction is configured as a private service by default.
- [ ] Extraction, chunking, embedding, and indexing statuses are visible to users.
- [ ] Failed indexing is visible, safe, retryable where practical, and excluded from retrieval.
- [ ] Chunks are ordered, bounded, overlapped, and associated with stable chunk refs.
- [ ] pgvector-backed search works in PostgreSQL without requiring an external vector database.
- [ ] `knowledge.search` returns ranked allowed chunks with snippets and safe metadata.
- [ ] `knowledge.read` returns bounded allowed chunk content and safe metadata.
- [ ] Search and read independently enforce World/City/Department/Lemming scope rules server-side.
- [ ] Optional Artifact ingestion requires explicit user approval and records only optional provenance.
- [ ] LLMs cannot silently promote generated files into Knowledge.
- [ ] Source file list/detail UI supports status, filters, pagination, failure display, and retry where practical.
- [ ] Events and telemetry use safe metadata only.
- [ ] Relevant targeted tests, `mix format`, and `mix precommit` pass.

---

## 11. Risks And Guardrails

- **Schema drift**: The current Knowledge schema is memory-only. Extend it intentionally and keep memory validations narrow so source files do not break memory behavior.
- **Content leakage**: Extracted text and chunks can contain sensitive data. Keep full content out of logs/events and return content only through bounded `knowledge.read` after scope checks.
- **Path leakage**: Storage refs and path resolution must stay behind trusted storage boundaries. Test path leakage explicitly.
- **Scope bugs**: Retrieval can leak data even when UI filters look correct. Scope must be part of every search/read query.
- **Index inconsistency**: Retrying indexing can leave stale chunks. Re-indexing must replace chunks atomically enough that search never mixes old and new chunks as one ready index.
- **Provider coupling**: Embedding provider details should not spread through the Knowledge context. Keep an embedding boundary with fakeable tests.
- **Operational fragility**: Tika, embedding providers, and pgvector can fail independently. Fail visibly and safely without crashing request handling.
- **Dependency creep**: Do not add RAG frameworks, vector databases, job systems, or HTTP clients for this PR unless explicitly approved.

---

## 12. Task Sequence

Execution tasks for this plan are tracked in numbered task files in this directory.

| # | Task | Agent | Status | Approved |
|---|---|---|---|---|
| 01 | Source File Test Scenarios | `qa-test-scenarios` | ⏳ PENDING | [ ] |
| 02 | Source File Schema And pgvector Migration | `dev-db-performance-architect` | ⏳ PENDING | [ ] |
| 03 | Source File Storage Boundary | `dev-backend-elixir-engineer` | ⏳ PENDING | [ ] |
| 04 | Source File Domain Context And Lifecycle | `dev-backend-elixir-engineer` | ⏳ PENDING | [ ] |
| 05 | Tika Extraction Integration | `dev-backend-elixir-engineer` | ⏳ PENDING | [ ] |
| 06 | Chunking Pipeline And Reindex Replacement | `dev-backend-elixir-engineer` | ⏳ PENDING | [ ] |
| 07 | Embedding Boundary And Provider Configuration | `dev-backend-elixir-engineer` | ⏳ PENDING | [ ] |
| 08 | Vector Retrieval Queries And Filtering | `dev-db-performance-architect` | ⏳ PENDING | [ ] |
| 09 | Knowledge Search And Read Tool Integration | `dev-backend-elixir-engineer` | ⏳ PENDING | [ ] |
| 10 | Source File Knowledge LiveView Surface | `dev-frontend-ui-engineer` | ⏳ PENDING | [ ] |
| 11 | Source File Backend Test Coverage | `qa-elixir-test-author` | ⏳ PENDING | [ ] |
| 12 | Source File LiveView And Tool Runtime Tests | `qa-elixir-test-author` | ⏳ PENDING | [ ] |
| 13 | Source File Feature Documentation | `docs-feature-documentation-author` | ⏳ PENDING | [ ] |
| 14 | Source File Security Audit | `audit-security` | ⏳ PENDING | [ ] |
| 15 | Source File Accessibility Audit | `audit-accessibility` | ⏳ PENDING | [ ] |
| 16 | Source File Final PR Audit | `audit-pr-elixir` | ⏳ PENDING | [ ] |
| 17 | Source File Release Validation | `rm-release-manager` | ⏳ PENDING | [ ] |

Each task requires human approval before the next task begins.

Human reviewers own all git operations and final sign-off.

---

## 13. Defaults And Open Questions

The task blockers for embedding provider, vector dimension, and file/chunk limits are resolved with the following MVP defaults.

Initial MVP defaults:

- Embedding provider: configurable OpenAI-compatible provider, fake provider in tests.
- Vector dimension: 1536.
- Max file size: 10 MB.
- Extraction timeout: 30 seconds.
- Max extracted characters: 500,000.
- Chunk size: 1,200 characters.
- Chunk overlap: 200 characters.
- Max chunks per file: 500.

Embedding implementation should use a small internal boundary with a configurable provider. Dev/test should use deterministic fake embeddings. Real environments should use an OpenAI-compatible embedding endpoint configured through environment variables.

Remaining open questions can be decided during implementation planning:

1. Should retry be available from the UI in the first implementation task, or only through an internal action until the UI is complete?
2. Should source file deletion physically remove stored bytes immediately, or archive first and leave physical cleanup to a later retention task?
3. Should v1 combine PostgreSQL full-text search with vector ranking, or start with vector ranking plus metadata/tag filters?
