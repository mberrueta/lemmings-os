# Task 01: Source File Test Scenarios

## Status
- **Status**: COMPLETE
- **Approved**: [X] Human sign-off

## Assigned Agent
`qa-test-scenarios` - Test scenario designer for acceptance criteria, edge cases, regressions, and coverage planning.

## Agent Invocation
Act as `qa-test-scenarios`. Build the full scenario matrix for source-file Knowledge before implementation tasks start.

## Objective
Translate `plan.md` into an ordered scenario matrix that covers schema, storage, extraction, chunking, embeddings, retrieval, tools, UI, observability, and regressions.

## Inputs Required
- [x] `llms/constitution.md`
- [x] `llms/project_context.md`
- [x] `llms/coding_styles/elixir.md`
- [x] `llms/coding_styles/elixir_tests.md`
- [x] `llms/tasks/0014_knowledge_source_files/plan.md`
- [x] Existing Knowledge/Artifact/tool runtime tests

## Expected Outputs
- [x] Scenario matrix with IDs, priorities, test layer, and expected outcomes.
- [x] Coverage mapping from FR/AC to future implementation tasks.
- [x] Explicit negative/security/privacy scenarios.

## Acceptance Criteria
- [x] All plan acceptance criteria are represented by one or more scenarios.
- [x] Scenario coverage includes ready-only retrieval and scope enforcement for `knowledge.search` and `knowledge.read`.
- [x] Scenario coverage includes MVP default limits and embedding defaults.
- [x] No implementation code changes are performed.

## Scope & Assumptions
- This task defines what to test; it does not implement production code or automated tests.
- Source files are Knowledge-managed documents, not Artifacts. `artifact_id` is optional provenance only after explicit user approval.
- Source files reuse existing Knowledge scope columns: `world_id`, `city_id`, `department_id`, and `lemming_id`.
- Product-facing "Lemming Type" scope is represented by existing `lemming_id` scope until a separate entity exists.
- Retrieval is ready-only: search/read must exclude non-ready, failed, archived, and deleted records.
- MVP defaults are part of testable behavior: provider is OpenAI-compatible, tests use fake embeddings, vector dimension is 1536, max file size is 10 MB, extraction timeout is 30 seconds, max extracted characters is 500,000, chunk size is 1,200 characters, overlap is 200 characters, and max chunks per file is 500.
- Background processing should be tested through deterministic boundaries; no sleeps longer than project guidelines and no external network.
- LiveView scenarios should use stable DOM IDs and selector assertions, not large raw HTML assertions.

## Risk Areas
- Scope leakage through vector search/read even when UI filters are correct.
- Ready-state bugs that expose pending, failed, archived, deleted, or partially indexed chunks.
- Path/content leakage in storage refs, UI, logs, events, telemetry, and tool outputs.
- Schema drift that breaks existing memory behavior or makes `knowledge.store` accept file semantics.
- Retry/reindex inconsistency that mixes stale chunks with fresh chunks.
- Tika and embedding provider failures causing request crashes or sensitive provider responses in errors.
- pgvector dimension/config mismatch causing runtime failures after chunks are persisted.
- Artifact ingestion ambiguity that silently promotes runtime-generated files into Knowledge.
- Long document limits causing slow tests, unbounded memory use, or unbounded DB writes.

## P0/P1/P2 Coverage Recommendations

| Subsystem | Priority | Recommendation |
|---|---|---|
| Schema and migrations | P0 | Validate discriminator/status/type constraints, source-file metadata, chunk constraints, pgvector dimension, and memory regressions. |
| Storage boundary | P0 | Validate opaque storage refs, size/checksum capture, filename normalization, traversal rejection, and no path leakage. |
| Scope and retrieval | P0 | Validate cross-world, sibling city, sibling department, and wrong lemming denial for search and read independently. |
| Ready-only lifecycle | P0 | Validate pending/extracting/chunking/embedding/failed/archived/deleted items never appear in retrieval. |
| Tool runtime | P0 | Validate `knowledge.search` and `knowledge.read` success/failure envelopes, max limits, and safe outputs. |
| Extraction/chunk/embed pipeline | P1 | Validate Tika success/failure, chunk ordering/overlap, fake embedding determinism, retries, and provider failures. |
| UI management | P1 | Validate upload/list/filter/status/detail/retry/archive/delete flows with stable selectors and safe failures. |
| Observability | P1 | Validate durable events/logs/telemetry include IDs/statuses and exclude raw content, paths, vectors, provider responses, and secrets. |
| Manual UX/ops | P2 | Validate Docker/Tika privacy posture, operator comprehension of statuses, and runbook-style recovery flow. |

## Scenario Matrix

| ID | Priority | Layer | Area | Scenario | Preconditions | Steps | Expected Result | Notes |
|---|---|---|---|---|---|---|---|---|
| SF-SCH-001 | P0 | Unit | Schema | Source file kind/status values are accepted without weakening memory constraints | Migration/schema supports source files | Build valid source-file Knowledge item and invalid kind/status permutations | `kind=source_file` and lifecycle statuses accepted; invalid values rejected | FR-1, AC-1, Task 02 |
| SF-SCH-002 | P0 | Unit | Schema | Memory behavior remains memory-only | Existing memory attrs include source-file fields | Create memory via existing context/tool paths | Memory keeps `kind=memory`; file-specific fields ignored/rejected according to boundary | AC-2, Task 04, Task 09, regression |
| SF-SCH-003 | P0 | Unit | Schema | Source file metadata requires original filename, content type, size, storage ref, and statuses | Missing/invalid metadata attrs | Build changeset permutations | Required fields and positive size enforced with safe errors | FR-1, Task 02 |
| SF-SCH-004 | P0 | Unit | Schema | Source file type is constrained to approved MVP values | Unsupported `source_file_type` | Validate metadata changeset | Unsupported type rejected; approved values accepted | FR-1, FR-8, Task 02 |
| SF-SCH-005 | P0 | Unit | DB | Source file metadata belongs to one Knowledge item | Existing source-file item | Insert duplicate metadata row for same item | Unique constraint prevents duplicate metadata | Data integrity, Task 02 |
| SF-SCH-006 | P0 | Unit | DB | Chunk ordering constraints prevent duplicate chunk indexes | Source file with chunks | Insert duplicate `(knowledge_source_file_id, chunk_index)` | Duplicate rejected | FR-4, Task 02, Task 06 |
| SF-SCH-007 | P0 | Unit | DB | Chunk refs are globally stable and unique | Two files with candidate same chunk ref | Insert chunks with duplicate `chunk_ref` | Duplicate rejected | FR-4, FR-7, Task 02 |
| SF-SCH-008 | P0 | Unit | DB | Embedding dimension is explicit and enforced | Configured dimension 1536 | Persist valid and wrong-size vectors | 1536 accepted; wrong dimensions fail before or at DB boundary with safe error | AC defaults, FR-5, Task 02, Task 07 |
| SF-SCH-009 | P1 | Unit | Schema | Top-level Knowledge item does not store full extracted document text | Large extracted sentinel document | Complete indexing pipeline | `knowledge_items.content` remains blank/summary-sized; chunks hold bounded content | FR-3, FR-4, privacy |
| SF-STO-001 | P0 | Unit | Storage | Upload stores original bytes through Knowledge storage boundary | Valid small file | Store file | Bytes persisted outside DB; opaque `storage_ref`, size, checksum returned | FR-1, AC-3, Task 03 |
| SF-STO-002 | P0 | Unit | Storage | Storage refs do not expose roots or absolute paths | Storage root contains sentinel path | Store and inspect returned metadata/UI/event payload | No root, temp path, workspace path, or absolute path is exposed | AC-4, privacy, Task 03 |
| SF-STO-003 | P0 | Unit | Storage | Unsafe filenames and traversal paths are normalized or rejected | Filename values include `../`, absolute paths, null-like segments, workspace paths | Attempt store/register | Unsafe names do not affect storage location and are not exposed | Security, Task 03 |
| SF-STO-004 | P0 | Integration | Validation | Max file size defaults to 10 MB | File over 10 MB and file at limit | Submit upload/register | At-limit accepted; over-limit rejected before indexing with no stored bytes or safe cleanup | AC defaults, FR-1, Task 03, Task 10 |
| SF-STO-005 | P1 | Unit | Storage | Checksum is deterministic and stored for the original bytes | Same content uploaded twice | Store files | Same checksum calculated; no path leakage; dedup only if explicitly implemented | Task 03 |
| SF-STO-006 | P1 | Integration | Storage | Storage write failure does not create searchable Knowledge | Simulated storage failure | Submit upload | Returns safe error; no ready item/chunks; no raw storage details exposed | Reliability, Task 03 |
| SF-CRT-001 | P0 | Integration | Create | User upload creates source file Knowledge item and metadata row quickly | Valid scope/type/tags/title/description and file | Submit create/upload | Item appears with non-ready status and background indexing requested | FR-1, AC-5, AC-6, Task 04 |
| SF-CRT-002 | P0 | Integration | Scope | Create rejects malformed or out-of-ancestry scope | User selects sibling/cross-world scope | Submit create | Safe validation error; no item/storage/chunks created or storage cleaned up | FR-1, security, Task 04 |
| SF-CRT-003 | P1 | Integration | Validation | Tags/title/description/source type validation preserves user input | Invalid type/tags/title | Submit create | Field-level errors; valid form values preserved | FR-1, Task 04, Task 10 |
| SF-ART-001 | P0 | Integration | Artifact | Artifact ingestion requires explicit user approval | Existing Artifact in allowed scope | Trigger approved ingest action with type/scope/tags | Knowledge source file created with optional provenance | FR-2, AC-15, Task 04 |
| SF-ART-002 | P0 | Integration | Artifact | Source files do not require `artifact_id` | Direct upload without Artifact | Create source file | Item persists without Artifact provenance | AC-1, Task 04 |
| SF-ART-003 | P0 | Integration | Artifact | LLM/runtime cannot silently promote generated files into source files | Lemming generated Artifact exists | Attempt source-file creation through tool/runtime-only path | Rejected or unavailable; only user-approved UI/context action can ingest | FR-2, AC-16, security |
| SF-ART-004 | P1 | Integration | Artifact | Artifact ingestion copies or references through Knowledge storage boundary | Approved Artifact ingest | Inspect source metadata | Storage is Knowledge-managed; raw Artifact workspace path not exposed | FR-2, Task 03, Task 04 |
| SF-EXT-001 | P0 | Integration | Extraction | Tika extraction success updates lifecycle | Private Tika fake returns text | Run extraction job/boundary | Status progresses from extracting to chunking/embedding path; extracted timestamp set | FR-3, Task 05 |
| SF-EXT-002 | P0 | Integration | Extraction | Tika call uses configured endpoint via `Req` and bounded timeout | Fake Tika endpoint records request | Run extraction | Request uses config; timeout set to 30 seconds or configured equivalent | FR-3, AC defaults, Task 05 |
| SF-EXT-003 | P0 | Integration | Extraction | Unsupported file marks safe failure | Fake Tika returns unsupported/415 | Run extraction | Item status failed/no-content per lifecycle; failure reason safe; no crash | FR-3, Task 05 |
| SF-EXT-004 | P0 | Integration | Extraction | Empty extraction marks safe failure or no-content | Fake Tika returns empty/whitespace | Run extraction | No chunks persisted; retrieval excludes item; safe status visible | FR-3, FR-6, Task 05 |
| SF-EXT-005 | P0 | Integration | Extraction | Timeout marks safe failure without raw exception leakage | Fake Tika times out | Run extraction | Failure status set; logs/events omit raw body/paths/stack dumps | FR-3, observability |
| SF-EXT-006 | P1 | Integration | Extraction | Extracted output is capped at 500,000 chars | Fake Tika returns over cap | Run extraction | Content truncated/rejected according to implementation; status and counts are deterministic | AC defaults, Task 05 |
| SF-EXT-007 | P1 | Manual | Ops | Tika is private by default in Docker Compose | Compose config available | Inspect service ports/network | Tika is not publicly exposed by default | FR-3, AC-7, Task 05 |
| SF-CHK-001 | P0 | Unit | Chunking | Chunking preserves document order | Deterministic text with section markers | Chunk text | `chunk_index` increases in source order; no reordering | FR-4, Task 06 |
| SF-CHK-002 | P0 | Unit | Chunking | Chunk size and overlap defaults are applied | Text longer than multiple chunks | Chunk text | Default chunk size 1,200 chars and overlap 200 chars are honored or centralized config value is asserted | AC defaults, FR-4 |
| SF-CHK-003 | P0 | Unit | Chunking | Empty chunks are not persisted | Text with whitespace/page breaks | Chunk text | No blank chunks inserted | FR-4, Task 06 |
| SF-CHK-004 | P0 | Integration | Chunking | Stable chunk refs survive deterministic reprocessing | Same file/content reindexed | Run indexing twice | Chunk refs stable for same item/index strategy | FR-4, FR-7, Task 06 |
| SF-CHK-005 | P0 | Integration | Chunking | Retry replaces stale chunks safely | Existing ready chunks then new extracted text | Retry reindex | Old chunks removed/replaced; search never returns mixed old/new set for ready index | FR-4, risk, Task 06 |
| SF-CHK-006 | P1 | Integration | Chunking | Max chunks defaults to 500 | Document would produce >500 chunks | Run chunking/indexing | Pipeline caps/rejects at 500 with safe status | AC defaults, Task 06 |
| SF-EMB-001 | P0 | Unit | Embeddings | Fake embedder is deterministic for tests | Same text input twice | Generate embeddings | Same 1536-dimensional vector returned | FR-5, AC defaults, Task 07 |
| SF-EMB-002 | P0 | Integration | Embeddings | Ready chunks have persisted content and embeddings | Successful extraction/chunking | Run embedding/indexing | Each searchable chunk has content and configured-dimension embedding | FR-5, AC-12, Task 07 |
| SF-EMB-003 | P0 | Integration | Embeddings | Provider failure updates status safely | Fake embedder returns error | Run indexing | Item status failed; failure reason safe; no raw provider response in logs/events | FR-5, privacy, Task 07 |
| SF-EMB-004 | P0 | Integration | Embeddings | Dimension mismatch fails before ready state | Embedder returns wrong vector length | Run indexing | Item not ready; no partially searchable chunks | FR-5, AC defaults, Task 07 |
| SF-EMB-005 | P1 | Integration | Config | Missing embedding provider config fails predictably | Runtime config absent/invalid | Start or execute indexing | Clear config validation error; no external call attempted | FR-5, Task 07 |
| SF-RET-001 | P0 | Integration | Retrieval | Vector search returns ranked ready chunks with snippets | Ready source files with deterministic embeddings | Call context search with query/top_k | Ranked allowed chunks returned with snippets and score | FR-6, AC-11, AC-12, Task 08 |
| SF-RET-002 | P0 | Integration | Retrieval | Search excludes non-ready lifecycle states | Items in pending/extracting/chunking/embedding/failed/archived/deleted | Search broad query | Only ready chunks returned | Ready-only AC, FR-6, Task 08 |
| SF-RET-003 | P0 | Integration | Scope | Search blocks cross-world content | Source files in two worlds | Search as lemming/world A | World B results absent; no count/title/id leak | FR-6, AC-14, security |
| SF-RET-004 | P0 | Integration | Scope | Search blocks sibling city content | Two cities in one world | Search as city/department/lemming A | Sibling city chunks absent | FR-6, AC-14 |
| SF-RET-005 | P0 | Integration | Scope | Search blocks sibling department content | Two departments in one city | Search as department/lemming A | Sibling department chunks absent | FR-6, AC-14 |
| SF-RET-006 | P0 | Integration | Scope | Search blocks wrong lemming content | Two lemmings in same department | Search as lemming A | Lemming B-only chunks absent | FR-6, AC-14 |
| SF-RET-007 | P0 | Integration | Filtering | Search supports source file type, tags, metadata, and status filters | Mixed ready chunks | Apply filters | Returned rows match all filters and scope | FR-6, FR-8, Task 08 |
| SF-RET-008 | P0 | Integration | Limits | Search `top_k` applies safe max | Call with omitted, valid, zero, negative, and excessive `top_k` | Execute search | Defaults applied; invalid rejected or normalized; excessive capped | FR-6, security, Task 08 |
| SF-RET-009 | P1 | Integration | Retrieval | Search returns snippets, not full chunk/document by default | Chunk contains sentinel beyond snippet range | Search | Output includes bounded snippet only; no full document | FR-6, privacy |
| SF-RET-010 | P1 | Integration | Retrieval | Empty result is safe and non-revealing | Query inaccessible or no-match content | Search | Empty result with standard success envelope; no inaccessible metadata | FR-6, security |
| SF-READ-001 | P0 | Integration | Read | Read returns bounded chunk content by chunk ref | Search result chunk ref accessible | Call read with default max | Bounded content and safe metadata returned | FR-7, AC-13, Task 08, Task 09 |
| SF-READ-002 | P0 | Integration | Scope | Read enforces scope independently from search | Caller has guessed valid inaccessible chunk ref | Call read directly | Not found/denied according to convention without existence leak | FR-7, AC-14, security |
| SF-READ-003 | P0 | Integration | Read | Read excludes archived/deleted/failed/non-ready chunks | Chunk ref exists under non-ready item | Call read | Safe not found/denied; no content | Ready-only, FR-7 |
| SF-READ-004 | P0 | Integration | Limits | Read `max_chars` is bounded and capped | Chunk content longer than requested | Call read with valid/excessive/invalid max values | Valid truncates; excessive capped; invalid safe error/default | FR-7, security |
| SF-READ-005 | P0 | Integration | Privacy | Read output omits storage refs, paths, vectors, provider payloads | Accessible chunk with metadata | Call read | Only safe metadata and bounded content returned | AC-13, privacy |
| SF-TOOL-001 | P0 | Integration | Tooling | `knowledge.search` tool returns standard success envelope | Runtime instance in valid hierarchy | Execute `knowledge.search` with kind/source type/tags/top_k | Tool result has expected envelope, result list, snippets, safe metadata | FR-6, Task 09 |
| SF-TOOL-002 | P0 | Integration | Tooling | `knowledge.search` rejects unsupported kind/fields safely | Tool payload has unsupported fields or invalid kind | Execute tool | Structured safe error; no DB mutation | FR-6, security |
| SF-TOOL-003 | P0 | Integration | Tooling | `knowledge.read` tool returns standard success envelope | Runtime instance and accessible chunk ref | Execute `knowledge.read` | Bounded content returned with safe metadata | FR-7, Task 09 |
| SF-TOOL-004 | P0 | Integration | Tooling | `knowledge.read` handles guessed/inaccessible refs safely | Runtime instance outside scope | Execute read with inaccessible ref | Safe not found/denied error; no content/title/id leak | FR-7, security |
| SF-TOOL-005 | P0 | Integration | Tooling | `knowledge.store` remains memory-only | Tool call attempts source-file upload/ref/chunk fields | Execute `knowledge.store` | Rejected as unsupported; no source file item created | AC-2, Task 09, regression |
| SF-TOOL-006 | P1 | Unit | Catalog | Tool catalog exposes `knowledge.search` and `knowledge.read` with safe descriptions | Tool catalog loaded | Inspect entries | Catalog includes retrieval tools; descriptions do not promise full docs/raw files | Task 09 |
| SF-UI-001 | P1 | LiveView | UI | Knowledge page shows source-file empty state and add action | No source files | Load Knowledge surface | Empty state and upload/register CTA visible with stable IDs | FR-1, FR-8, Task 10 |
| SF-UI-002 | P1 | LiveView | UI | Upload form accepts file, scope, source file type, title, description, tags | Valid test upload | Submit form | Row appears immediately with non-ready/indexing status | FR-1, Task 10 |
| SF-UI-003 | P1 | LiveView | UI | Upload validation errors are field-level and preserve form input | Invalid file/type/scope | Submit form | Errors shown; input preserved; no path leakage | FR-1, Task 10 |
| SF-UI-004 | P1 | LiveView | UI | List renders title, type, tags, scope, status, updated time | Seed source files across statuses | Load list | Rows render stable selectors and safe labels | FR-8, Task 10 |
| SF-UI-005 | P1 | LiveView | UI | List filters compose text, type, tags, and status | Seed mixed source files | Apply filters | Correct filtered rows and filtered empty state | FR-8, Task 10 |
| SF-UI-006 | P1 | LiveView | UI | Pagination is local Ecto and deterministic | More than one page of source files | Navigate pages | Stable page counts/order; no dependency-specific behavior | FR-8, Task 10 |
| SF-UI-007 | P1 | LiveView | UI | Detail page shows indexing/ready/failed states safely | Seed statuses | Open detail | Lifecycle status, metadata, index summary, and safe failure reason rendered | FR-8, Task 10 |
| SF-UI-008 | P1 | LiveView | UI | Retry failed indexing action transitions status and requests reindex | Failed source file | Click retry | Retry event/status visible; stale chunks handled by backend | FR-8, Task 10 |
| SF-UI-009 | P1 | LiveView | UI | Archive/delete removes item from future retrieval | Ready source file | Archive/delete from UI then search | UI updates and retrieval excludes item | FR-8, AC-17 |
| SF-UI-010 | P1 | LiveView | Scope | UI deep links cannot expose inaccessible source files | URL references sibling/cross-world source file | Load detail/list scope URL | Not found/redirect/empty without title/count leak | Security, Task 10 |
| SF-OBS-001 | P1 | Integration | Observability | Created/indexed/retry/archive/delete events include safe IDs/statuses | Event capture enabled | Execute lifecycle actions | Expected event names emitted with scope IDs and status metadata | Section 8, Task 04-10 |
| SF-OBS-002 | P0 | Integration | Observability | Failure events/logs exclude sensitive values | Sentinels in paths/content/provider errors | Force extraction/index failures | No absolute paths, storage refs, full content, vectors, provider responses, secrets, or stack dumps | Privacy, security |
| SF-OBS-003 | P1 | Integration | Telemetry | Search/read telemetry or events are safe and scoped | Execute search/read | Inspect emitted metadata | Includes IDs/counts/durations; excludes query content where considered sensitive or full chunk content | Section 8, Task 09 |
| SF-OBS-004 | P1 | Integration | Observability | Background processor errors do not crash request process | Processor failure injected | Upload/register then fail processor | Request succeeds/returns accepted; failure status visible and observable | Reliability |
| SF-REG-001 | P0 | Integration | Regression | Existing memory CRUD/list tests continue to pass | Current memory fixtures | Run memory context tests | Existing memory semantics unchanged | AC-2, Task 11 |
| SF-REG-002 | P0 | Integration | Regression | Existing `knowledge.store` runtime tests continue to pass | Runtime instance | Execute current store paths | Memory created; invalid scope/unsupported fields unchanged | AC-2, Task 11 |
| SF-REG-003 | P1 | LiveView | Regression | Existing Knowledge memory UI continues to pass | Current LiveView flows | Create/edit/delete/filter memories | Memory UI not broken by source-file UI additions | Task 12 |
| SF-REG-004 | P1 | Controller | Regression | Artifact download/path safety behavior remains unchanged | Existing Artifact controller cases | Run artifact controller tests | Artifact route still denies unsafe paths and leaks no refs | Artifact boundary regression |
| SF-MAN-001 | P2 | Manual | UX | Operator can understand indexing lifecycle and retry | Browser with Tika/embedding fake | Upload, observe indexing, force failure, retry | Status copy is understandable and retry outcome clear | Task 15, Task 17 |
| SF-MAN-002 | P2 | Manual | Ops | Release validation covers no external vector DB or RAG framework | Built release config | Inspect config/deps/runtime | PostgreSQL/pgvector used; no Qdrant/Redis/LangChain/LlamaIndex dependency introduced | Out-of-scope guard |

## FR/AC Traceability

| Plan Requirement | Scenario IDs |
|---|---|
| FR-1 Add Source Files | SF-SCH-001, SF-SCH-003, SF-SCH-004, SF-STO-001, SF-STO-004, SF-CRT-001, SF-CRT-002, SF-CRT-003, SF-UI-001, SF-UI-002, SF-UI-003 |
| FR-2 Optional Artifact Ingestion | SF-ART-001, SF-ART-002, SF-ART-003, SF-ART-004, SF-REG-004 |
| FR-3 Extract Text | SF-EXT-001, SF-EXT-002, SF-EXT-003, SF-EXT-004, SF-EXT-005, SF-EXT-006, SF-EXT-007 |
| FR-4 Chunk Extracted Text | SF-SCH-006, SF-SCH-007, SF-CHK-001, SF-CHK-002, SF-CHK-003, SF-CHK-004, SF-CHK-005, SF-CHK-006 |
| FR-5 Embed And Index Chunks | SF-SCH-008, SF-EMB-001, SF-EMB-002, SF-EMB-003, SF-EMB-004, SF-EMB-005, SF-RET-001 |
| FR-6 Search Source File Knowledge | SF-RET-001, SF-RET-002, SF-RET-003, SF-RET-004, SF-RET-005, SF-RET-006, SF-RET-007, SF-RET-008, SF-RET-009, SF-RET-010, SF-TOOL-001, SF-TOOL-002 |
| FR-7 Read Source File Chunks | SF-READ-001, SF-READ-002, SF-READ-003, SF-READ-004, SF-READ-005, SF-TOOL-003, SF-TOOL-004 |
| FR-8 Manage Source Files | SF-UI-004, SF-UI-005, SF-UI-006, SF-UI-007, SF-UI-008, SF-UI-009, SF-UI-010, SF-MAN-001 |
| Events And Observability | SF-OBS-001, SF-OBS-002, SF-OBS-003, SF-OBS-004 |
| AC: Source files are Knowledge, not required Artifacts | SF-SCH-001, SF-ART-002, SF-ART-004 |
| AC: Memories and `knowledge.store` remain memory-only | SF-SCH-002, SF-TOOL-005, SF-REG-001, SF-REG-002, SF-REG-003 |
| AC: Original bytes stored outside DB with opaque refs | SF-STO-001, SF-STO-002, SF-STO-003, SF-STO-005 |
| AC: No raw path/storage/temp/workspace path exposure | SF-STO-002, SF-STO-003, SF-ART-004, SF-READ-005, SF-OBS-002 |
| AC: Add file with scope/type/title/description/tags | SF-CRT-001, SF-CRT-003, SF-UI-002 |
| AC: Upload returns quickly and indexing continues | SF-CRT-001, SF-OBS-004 |
| AC: Tika private by default | SF-EXT-007 |
| AC: Lifecycle statuses visible | SF-UI-004, SF-UI-007 |
| AC: Failed indexing visible/safe/retryable/excluded | SF-EXT-003, SF-EXT-005, SF-EMB-003, SF-RET-002, SF-UI-008 |
| AC: Chunks ordered/bounded/overlapped/stable refs | SF-CHK-001, SF-CHK-002, SF-CHK-003, SF-CHK-004, SF-CHK-006 |
| AC: pgvector search in PostgreSQL, no external vector DB | SF-SCH-008, SF-RET-001, SF-MAN-002 |
| AC: `knowledge.search` ranked allowed chunks with snippets | SF-RET-001, SF-RET-007, SF-RET-009, SF-TOOL-001 |
| AC: `knowledge.read` bounded allowed chunk content | SF-READ-001, SF-READ-004, SF-READ-005, SF-TOOL-003 |
| AC: Search/read enforce scope independently | SF-RET-003, SF-RET-004, SF-RET-005, SF-RET-006, SF-READ-002, SF-TOOL-004 |
| AC: Artifact ingestion explicit and provenance optional | SF-ART-001, SF-ART-002, SF-ART-003 |
| AC: LLMs cannot silently promote files | SF-ART-003, SF-TOOL-005 |
| AC: UI supports filters/status/pagination/failure/retry | SF-UI-004, SF-UI-005, SF-UI-006, SF-UI-007, SF-UI-008, SF-UI-009 |
| AC: Events and telemetry safe metadata only | SF-OBS-001, SF-OBS-002, SF-OBS-003 |
| AC: Targeted tests, format, precommit pass | SF-REG-001, SF-REG-002, SF-REG-003, Task 11, Task 12, Task 17 |

## Future Task Coverage Mapping

| Future Task | Primary Scenario IDs |
|---|---|
| 02 Source File Schema And pgvector Migration | SF-SCH-001 through SF-SCH-009 |
| 03 Source File Storage Boundary | SF-STO-001 through SF-STO-006, SF-ART-004 |
| 04 Source File Domain Context And Lifecycle | SF-CRT-001 through SF-CRT-003, SF-ART-001 through SF-ART-003, SF-OBS-001 |
| 05 Tika Extraction Integration | SF-EXT-001 through SF-EXT-007, SF-OBS-002 |
| 06 Chunking Pipeline And Reindex Replacement | SF-CHK-001 through SF-CHK-006 |
| 07 Embedding Boundary And Provider Configuration | SF-EMB-001 through SF-EMB-005 |
| 08 Vector Retrieval Queries And Filtering | SF-RET-001 through SF-RET-010, SF-READ-001 through SF-READ-005 |
| 09 Knowledge Search And Read Tool Integration | SF-TOOL-001 through SF-TOOL-006, SF-READ-002 |
| 10 Source File Knowledge LiveView Surface | SF-UI-001 through SF-UI-010 |
| 11 Source File Backend Test Coverage | SF-SCH, SF-STO, SF-CRT, SF-ART, SF-EXT, SF-CHK, SF-EMB, SF-RET, SF-READ, SF-REG-001, SF-REG-002 |
| 12 Source File LiveView And Tool Runtime Tests | SF-TOOL, SF-UI, SF-REG-003 |
| 13 Source File Feature Documentation | User-facing behavior implied by SF-UI, SF-TOOL, SF-MAN |
| 14 Source File Security Audit | SF-STO-002, SF-STO-003, SF-CRT-002, SF-RET-003 through SF-RET-010, SF-READ-002, SF-READ-005, SF-OBS-002 |
| 15 Source File Accessibility Audit | SF-UI-001 through SF-UI-010, SF-MAN-001 |
| 16 Source File Final PR Audit | Full matrix plus regression checklist |
| 17 Source File Release Validation | SF-MAN-001, SF-MAN-002, full regression checklist |

## Negative, Security, And Privacy Scenarios

| Risk | Scenario IDs | Required Assertion |
|---|---|---|
| Cross-world leakage | SF-CRT-002, SF-RET-003, SF-READ-002, SF-TOOL-004, SF-UI-010 | No content, title, id, count, or existence confirmation leaks across worlds. |
| Sibling city/department leakage | SF-RET-004, SF-RET-005, SF-UI-010 | Server-side query excludes siblings independent of UI filters. |
| Wrong lemming leakage | SF-RET-006, SF-READ-002 | Lemming-scoped source files are visible only to that lemming. |
| Ready-only retrieval bypass | SF-RET-002, SF-READ-003, SF-UI-009 | Non-ready/failed/archived/deleted chunks never return from search/read. |
| Path/storage leakage | SF-STO-002, SF-STO-003, SF-ART-004, SF-READ-005, SF-OBS-002 | Outputs exclude absolute paths, roots, temp paths, workspace paths, and storage refs. |
| Full content leakage | SF-SCH-009, SF-RET-009, SF-READ-004, SF-OBS-002, SF-OBS-003 | Full extracted text appears only as bounded read content after scope checks. |
| Vector/provider leakage | SF-EMB-003, SF-READ-005, SF-OBS-002 | Embedding vectors and raw provider responses never appear in UI/tool/log/event payloads. |
| Unsafe filename traversal | SF-STO-003 | Traversal strings cannot influence storage path or response output. |
| Silent artifact promotion | SF-ART-003, SF-TOOL-005 | LLM/tool runtime cannot create source-file Knowledge from generated Artifacts. |
| Unbounded resource use | SF-STO-004, SF-EXT-006, SF-CHK-006, SF-RET-008, SF-READ-004 | File, extraction, chunk, search, and read limits are enforced deterministically. |

## Required Fixtures And Sentinel Patterns
- Hierarchy fixtures: two worlds; two cities in one world; two departments in one city; two lemmings in one department; lemmings in sibling departments.
- Source-file fixtures: ready, pending_index, extracting, chunking, embedding, failed, archived, and deleted items.
- File fixtures: small text file, unsupported file, empty file, 10 MB boundary file, oversized file, document producing more than 500 chunks.
- Chunk fixtures: ordered chunks with deterministic `chunk_ref`, overlapping boundary text, sentinel chunk text, and wrong-dimension embedding vector.
- Runtime fixtures: lemming instance with valid hierarchy for `knowledge.search` and `knowledge.read`, plus sibling/cross-world instances.
- External-service fakes: private Tika fake using `Req` boundary and deterministic fake embedder returning 1536-dimensional vectors.
- Sentinel values for leak checks:
  - `SENTINEL_SOURCE_FILE_SECRET_001`
  - `SENTINEL_FULL_EXTRACTED_TEXT_SHOULD_NOT_LEAK`
  - `SENTINEL_ABS_PATH_/var/lib/lemmings_os/knowledge/private.pdf`
  - `SENTINEL_UPLOAD_TMP_/tmp/plug-upload/source.pdf`
  - `SENTINEL_WORKSPACE_/mnt/data4/matt/code/personal_stuffs/lemmings-os/private/source.pdf`
  - `SENTINEL_STORAGE_REF_knowledge://local/private/ref`
  - `SENTINEL_EMBEDDING_VECTOR_[0.123,0.456]`
  - `SENTINEL_PROVIDER_RESPONSE_{"api_key":"secret"}`

## Acceptance Criteria
- Given a user uploads a valid source file with allowed scope, type, title, description, and tags, when create completes, then a Knowledge source-file item and metadata row exist, original bytes are stored outside the DB, and the UI shows a non-ready lifecycle status.
- Given a source file is indexed successfully, when search runs in an allowed scope, then only ready chunks are ranked and returned with snippets and safe metadata.
- Given a caller has a guessed chunk ref outside its scope, when `knowledge.read` is called, then the response is a safe not-found/denied result and does not reveal whether the chunk exists.
- Given source files are pending, extracting, chunking, embedding, failed, archived, or deleted, when search/read runs, then those chunks are excluded.
- Given Tika, storage, or embedding provider failures occur, when lifecycle processing handles the failure, then the app updates safe failure status and does not log or emit raw paths, extracted text, vectors, or provider responses.
- Given existing memory and `knowledge.store` behavior, when source-file functionality is added, then memory CRUD/list/tool tests continue to pass and source-file fields remain unsupported in `knowledge.store`.
- Given the MVP defaults, when limits are exercised, then 10 MB file size, 30 second extraction timeout, 500,000 extracted characters, 1,200 character chunks, 200 character overlap, 500 max chunks, 1536 vector dimensions, safe `top_k`, and bounded `max_chars` are enforced.

## Regression Checklist
- [ ] Existing `test/lemmings_os/knowledge_test.exs` memory tests pass unchanged or with deliberate source-file additions only.
- [ ] Existing `test/lemmings_os/tools/runtime_test.exs` `knowledge.store` tests pass and reject source-file/file-ref fields.
- [ ] Existing `test/lemmings_os_web/live/knowledge_live_test.exs` memory UI tests pass after source-file UI additions.
- [ ] Existing Artifact storage/download/path safety tests pass; source files do not become Artifacts by accident.
- [ ] Search and read deny cross-world, sibling city, sibling department, and wrong-lemming access at the backend/tool layer.
- [ ] Ready-only retrieval excludes pending/extracting/chunking/embedding/failed/archived/deleted items.
- [ ] Storage refs remain opaque and raw paths never appear in UI, logs, events, telemetry, or tool outputs.
- [ ] Full extracted text is absent from Knowledge item rows, search snippets, events, logs, and telemetry.
- [ ] `knowledge.read` is the only path returning chunk content and it is bounded after scope checks.
- [ ] Reindex retry replaces stale chunks without mixing old and new ready results.
- [ ] Tika and embedding provider failures are safe, deterministic in tests, and do not crash request handling.
- [ ] MVP limits and embedding dimension defaults are explicitly covered.
- [ ] LiveView source-file tests use stable DOM IDs for forms, buttons, rows, filters, retry actions, and detail sections.

## Out-of-scope
- Implementing automated tests or production code in this task.
- Reference files, template engine behavior, automatic LLM promotion of generated files, OCR-heavy guarantees, table-perfect extraction, advanced reranking, public file sharing, external vector databases, Redis retrieval, LangChain/LlamaIndex sidecars, and new durable job dependencies.
- Final decisions on physical deletion retention, hybrid full-text/vector ranking, and whether retry is UI-first or internal-only beyond the scenarios that must cover whichever implementation is chosen.

## Execution Summary
### Work Performed
- Converted the source-file Knowledge plan into an implementation-ready scenario matrix with risk-ranked P0/P1/P2 coverage.
- Added explicit coverage for schema, storage, Artifact ingestion, Tika extraction, chunking, embeddings, pgvector retrieval, `knowledge.search`, `knowledge.read`, UI management, observability, privacy, and regressions.
- Added traceability from FR/AC requirements to scenario IDs and future implementation tasks.
- Added explicit negative/security/privacy scenarios and sentinel data guidance.

### Outputs Created
- Updated `llms/tasks/0014_knowledge_source_files/01_source_file_test_scenarios.md` with completed scenario planning content.

### Assumptions Made
- Source file implementation will use a fakeable extraction/embedding boundary for deterministic tests.
- UI will extend the existing Knowledge LiveView surface rather than introducing an unrelated management surface.
- Event verification can use durable events, logs, and telemetry depending on which implementation task wires each lifecycle action.

### Blockers
- None.

### Ready for Next Task
- [x] Yes
- [ ] No

## Human Review
*[Filled by human reviewer]*
