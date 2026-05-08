# Task 01: Reference File Test Scenarios

## Status

- **Status**: COMPLETE
- **Approved**: [X] Human sign-off

## Assigned Agent

`qa-test-scenarios` - Test scenario designer for acceptance criteria, edge cases, regressions, and coverage planning.

## Agent Invocation

Act as `qa-test-scenarios`. Build the full scenario matrix for reference-file Knowledge before implementation starts.

## Objective

Translate `plan.md` into a scenario matrix that covers schema, managed storage, optional Artifact promotion, operator mutation, scoped availability, metadata-first search, bounded read behavior, safe descriptors, UI, observability, regressions, no-RAG assertions, scope denial, and no-leak checks.

## Inputs Required

- `llms/constitution.md`
- `llms/project_context.md`
- `llms/coding_styles/elixir.md`
- `llms/coding_styles/elixir_tests.md`
- `llms/tasks/0015_knowledge_reference_file/plan.md`
- Existing Knowledge, Artifact, tool adapter, and Knowledge LiveView tests

## Scope And Assumptions

- Reference files are Knowledge-managed fixed files, not required Artifacts.
- `artifact_id` is optional provenance only when an operator explicitly promotes an Artifact.
- Lemmings may search/read visible reference files through governed tools, but may not create, edit, archive, delete, or promote them.
- Reference files do not use source-file chunks, embeddings, or vector indexes.
- This task defines what to test; it does not implement production code or automated tests.

## Priority And Layer Guidance

| Priority | Layer | Use For |
|---|---|---|
| P0 | Unit / Integration | Schema rules, scope enforcement, no-RAG assertions, no-leak checks, mutation boundaries, search/read correctness |
| P1 | LiveView / Observability | Operator UI, safe events, safe telemetry/logging, provenance messaging |
| P2 | Manual | Human comprehension of category boundaries and approval gate validation |

## Scenario Matrix

| ID | Priority | Layer | Area | Scenario | Preconditions | Steps | Expected Result | Notes |
|---|---|---|---|---|---|---|---|---|
| RF-SCH-001 | P0 | Unit | Schema | Reference-file kind, status, and flexible type validation are enforced | Schema supports `reference_file` rows | Build valid and invalid changesets for kind/status/type permutations | Valid `reference_file` rows are accepted; invalid kind/status/type values are rejected safely | FR-1, FR-3, FR-8 |
| RF-SCH-002 | P0 | Unit | Schema | `artifact_id` is optional provenance, not a requirement | Minimal valid reference-file attrs | Insert a reference file with and without `artifact_id` | Both paths persist; missing `artifact_id` does not block creation | FR-1, FR-2 |
| RF-SCH-003 | P0 | Unit | Schema | Metadata fields for title, description, tags, and scope validate independently | Invalid title/tag/scope permutations | Build changeset permutations | Field-level errors are returned without weakening other fields | FR-1, FR-3, NFR-5 |
| RF-MIG-001 | P0 | Migration / Schema | DB policy | Reference-file DB changes use one migration and no DB business-rule constraints | Reference-file persistence is implemented | Inspect migration and schema validations | DB constraints are limited to references, unique guarantees, and indexes; business rules are enforced in Ecto changesets/context; no DB CHECK constraints or DB enums are added | DB policy |
| RF-CRT-001 | P0 | Integration | Create | Operator upload/register creates a Knowledge-managed reference file without requiring an Artifact | Valid file, title, type, scope, tags | Submit create/register flow | Reference-file item is created and stored through Knowledge-managed storage | FR-1 |
| RF-CRT-002 | P0 | Integration | Scope | Create rejects malformed, sibling, and cross-World scopes safely | Seed accessible and inaccessible scopes | Attempt create with forbidden scope targets | Safe validation error; no item or storage side effect; no scope leak | FR-1, NFR-1 |
| RF-CRT-003 | P1 | Integration | Validation | Form errors preserve user input and do not expose storage internals | Invalid file/type/scope combination | Submit create/register form | Errors are field-level; entered values remain; no raw path or storage ref is shown | FR-1, NFR-3 |
| RF-PROM-001 | P0 | Integration | Promotion | Artifact promotion requires explicit operator approval | Existing Artifact in allowed scope | Trigger promotion without approval, then with approval | Unapproved path is denied; approved path creates a reference file | FR-2 |
| RF-PROM-002 | P0 | Integration | Promotion | Optional Artifact provenance is recorded but not the storage contract | Approved Artifact promotion | Inspect resulting reference file details | Reference file persists as Knowledge-managed; provenance is present only as optional linkage | FR-2 |
| RF-PROM-003 | P1 | Integration | Promotion | Later-unavailable Artifact does not break the reference file | Promoted reference file whose Artifact is later deleted or unavailable | Re-open list/detail/read/search paths | Reference file remains manageable; provenance may be cleared or marked unavailable safely | FR-2, NFR-1 |
| RF-MAN-001 | P0 | Integration | Management | Operators can list, filter, edit, and archive reference files by accessible scope | Seed active and archived reference files across scopes | Open list, filter, edit metadata, archive one active row | Accessible items render and mutate; archived item leaves active flow | FR-3 |
| RF-MAN-002 | P0 | Integration | Management | Archived reference files are excluded from normal Lemming availability | Archived reference file exists in scope | Archive item, then inspect availability/search surfaces | Archived file is no longer offered as an available reference | FR-3, FR-4 |
| RF-AVAIL-001 | P0 | Integration | Availability | Effective-scope availability summary exposes safe metadata only | Active reference files in a caller's scope | Fetch availability summary for current scope | Summary includes title, type, tags, status, scope, and descriptor ID only | FR-4, FR-7 |
| RF-AVAIL-002 | P0 | Integration | Availability | Cross-World, sibling scope, and archived files are excluded from availability | Reference files in multiple worlds/cities/departments | Fetch availability as each scope target | Inaccessible and archived files are omitted without existence leaks | FR-4, NFR-1 |
| RF-AVAIL-003 | P1 | Integration | Availability | Multiple matching variants coexist and sort predictably | Several active variants with similar type/tags | Fetch availability repeatedly and compare order | Multiple matches are preserved; order is deterministic and favors nearer scope / stronger metadata match | FR-4, FR-8 |
| RF-SRCH-001 | P0 | Integration | Search | `knowledge.search` supports kind, type, tags, query, status, and scope for reference files | Mixed reference-file fixtures | Search with metadata-first filters | Returned rows match filters and include safe descriptors only | FR-5 |
| RF-SRCH-002 | P0 | Integration | Search | Search defaults to the caller's effective scope and denies inaccessible scope guesses safely | Visible and invisible reference files seeded | Search without scope overrides and with forged scope attempts | Only allowed results are returned; no count/title/id leak from denied scopes | FR-5, NFR-1 |
| RF-SRCH-003 | P0 | Integration | Search | Reference-file search is metadata-first and never depends on chunks, embeddings, or vector indexes | Reference files exist without RAG records | Search by type/tags/query | Results come from Knowledge metadata; no chunk refs, embeddings, or vector-only behavior are required | FR-5, NFR-4 |
| RF-SRCH-004 | P1 | Integration | Search | Duplicate and variant reference files can coexist and sort predictably | Multiple active variants share the same type or tags | Search and compare ranking order | Multiple matches are returned; sorting makes the most likely match visible first | FR-5, FR-8 |
| RF-READ-001 | P0 | Integration | Read | `knowledge.read` returns bounded direct text for directly readable reference files | Text reference file accessible in scope | Read with default and capped `max_chars` | Bounded content and safe metadata are returned | FR-6 |
| RF-READ-002 | P0 | Integration | Read | Supported binary or structured files use safe conversion and bounded text | Office/PDF/document-like reference file fixture | Read via the safe conversion boundary | Converted text is bounded; conversion metadata remains safe | FR-6, NFR-4 |
| RF-READ-006 | P0 | Integration | Read | Supported non-text reference files route through the existing safe conversion boundary | PDF/Office/HTML-like reference files exist and fake converters are configured | Read supported non-text files | MarkItDown/Trafilatura/PDF fallback boundaries are invoked where applicable; output is bounded converted text; no chunks, embeddings, vector indexes, or raw paths are created | FR-6 |
| RF-READ-003 | P0 | Integration | Read | Unsupported or unreadable reference files return a safe descriptor only | Binary/unreadable reference file fixture | Call read on the item | No raw bytes or paths are returned; safe descriptor explains unreadability | FR-6, NFR-3 |
| RF-READ-004 | P0 | Integration | Scope | Read enforces scope independently from search and does not reveal inaccessible existence | Guessed inaccessible reference-file ID | Call read directly without prior allowed search result | Safe not-found/denied response without existence leak | FR-6, NFR-1 |
| RF-READ-005 | P0 | Integration | Privacy | Read output omits raw paths, storage refs, provider payloads, and unbounded content | Accessible file with sentinel path/content values | Read and inspect returned payload | Only safe metadata and bounded content are visible | FR-6, NFR-3 |
| RF-DESC-001 | P0 | Unit | Descriptor | Stable safe descriptor shape includes only tool-safe metadata | Reference-file descriptor struct or map | Build descriptor from a persisted item | Descriptor exposes `reference_ref`, `knowledge_item_id`, `kind`, `type`, `title`, `tags`, `content_type`, and safe flags only | FR-7 |
| RF-DESC-002 | P1 | Integration | Descriptor | Future document/PDF tools can accept a descriptor without needing raw filesystem paths | Safe descriptor available | Pass descriptor through the intended tool boundary | Descriptor remains usable without raw path or storage-root dependence | FR-7, NFR-2 |
| RF-TOOL-001 | P0 | Integration | Tooling | `knowledge.search` supports reference files with a standard safe envelope | Runtime instance in valid hierarchy | Execute search for `kind: "reference_file"` with supported filters | Tool result is shaped safely and does not expose raw storage details | FR-5, FR-7 |
| RF-TOOL-002 | P0 | Integration | Tooling | `knowledge.read` supports reference files with bounded content or a safe descriptor | Runtime instance and accessible reference file | Execute read on a reference file | Tool returns bounded text or safe descriptor only | FR-6, FR-7 |
| RF-TOOL-003 | P0 | Integration | Tooling | `knowledge.store` remains memory-only and rejects reference-file mutation fields | Tool payload includes reference-file fields | Execute `knowledge.store` | Unsupported fields are rejected; no reference-file item is created | NFR-2, regression |
| RF-TOOL-004 | P0 | Integration | Tooling | Lemmings can search/read governed availability but cannot create, edit, archive, delete, or promote reference files | Runtime instance with Lemming privileges | Attempt mutation-style tool calls | Mutation is denied; read/search remains available only through governed scope | FR-4, FR-5, FR-6, NFR-1 |
| RF-OBS-001 | P1 | Integration | Observability | Lifecycle and access events include safe IDs and statuses only | Event capture enabled | Create, update, archive, search, and read reference files | Events include safe identifiers and scope metadata; no full content or path leakage | NFR-3 |
| RF-OBS-002 | P1 | Integration | Observability | Failure logs and telemetry omit sensitive values and internal runtime state | Sentinel values in content, paths, and provenance | Force unreadable conversion, denied scope, and unavailable provenance cases | Logs/events omit raw content, filesystem paths, storage roots, and provider payloads | NFR-3 |
| RF-NORAG-001 | P0 | Integration | Regression | Creating, updating, or reading reference files does not create source-file chunks, embeddings, or vector indexes | Reference file created and read through the full flow | Inspect related source-file tables and indexes | No source-file chunking or embedding side effects occur | FR-6, NFR-4 |
| RF-NORAG-002 | P0 | Integration | Regression | Existing source-file chunk/search/read behavior remains unchanged | Existing source-file fixtures and searches | Run the current source-file search/read tests alongside reference-file coverage | Source-file retrieval still behaves as before; reference-file changes do not alter it | NFR-5 |
| RF-REG-001 | P0 | Integration | Regression | Existing memories remain memory-only and `knowledge.store` continues to store memories | Current memory fixtures | Run memory create/store paths with reference-file coverage loaded | Memory semantics remain unchanged; file semantics are not accepted by `knowledge.store` | NFR-5 |
| RF-REG-002 | P0 | Integration | Regression | Existing source-file and memory UI flows continue to work | Existing Knowledge LiveView flows | Exercise memory/source-file pages after reference-file changes | Existing tabs and stable selectors continue to render correctly | NFR-5 |
| RF-UI-001 | P1 | LiveView | UI | `/knowledge` placeholder becomes Reference Files with a safe empty state | No reference files in scope | Open the Knowledge surface | Reference Files tab, empty state, and operator-managed CTA render with stable IDs | FR-3, FR-4 |
| RF-UI-002 | P1 | LiveView | UI | List and detail render title, type, tags, scope, status, safe descriptor, and provenance-unavailable messaging | Seed active, archived, and orphaned-provenance items | Open list and detail views | Metadata renders clearly; provenance-unavailable state is shown safely | FR-3, FR-7 |
| RF-UI-003 | P1 | LiveView | UI | Upload/register, edit, and archive actions work with field-level validation | Valid and invalid reference-file form inputs | Submit create/edit/archive flows | Form errors are specific; successful actions re-render the correct state | FR-1, FR-3 |
| RF-SEC-001 | P0 | Integration | Security | Cross-world and sibling-scope denial does not leak existence, counts, titles, or IDs | Reference files exist in forbidden scopes | Attempt search/read/list against disallowed scopes | Requests are denied or return safe empty results without scope leakage | FR-4, FR-5, FR-6, NFR-1 |
| RF-SEC-002 | P0 | Integration | Security | Raw filesystem paths, temp paths, storage roots, raw storage refs, and bytes never leak through outputs | Sentinel path/content values available in fixtures | Inspect UI, tool results, logs, and events | No raw storage implementation details are exposed anywhere | FR-1, FR-2, FR-6, NFR-1, NFR-3 |
| RF-MANUAL-001 | P2 | Manual | UX | Human reviewer can distinguish Memories, Source Files, Reference Files, and Artifacts from the docs/tool guidance | Documentation/tool text is available | Read the guidance and review reference-file actions in the UI | The category boundaries are clear and the approval gate is understandable | NFR-2 |

## Coverage Mapping

| Plan Requirement | Scenario IDs |
|---|---|
| FR-1 Add reference files | RF-SCH-001, RF-SCH-002, RF-SCH-003, RF-CRT-001, RF-CRT-002, RF-CRT-003, RF-UI-001, RF-UI-003, RF-SEC-002 |
| FR-2 Promote Artifact to reference file | RF-PROM-001, RF-PROM-002, RF-PROM-003, RF-SEC-002 |
| FR-3 Manage reference files | RF-MAN-001, RF-MAN-002, RF-UI-002, RF-UI-003, RF-OBS-001 |
| FR-4 Scoped availability to Lemmings | RF-AVAIL-001, RF-AVAIL-002, RF-AVAIL-003, RF-TOOL-004, RF-SEC-001 |
| FR-5 Search reference files | RF-SRCH-001, RF-SRCH-002, RF-SRCH-003, RF-SRCH-004, RF-TOOL-001, RF-SEC-001 |
| FR-6 Read reference files | RF-READ-001, RF-READ-002, RF-READ-003, RF-READ-004, RF-READ-005, RF-READ-006, RF-TOOL-002, RF-SEC-001 |
| FR-7 Safe descriptors for future tools | RF-DESC-001, RF-DESC-002, RF-AVAIL-001, RF-TOOL-001, RF-TOOL-002 |
| FR-8 Duplicate and variant handling | RF-AVAIL-003, RF-SRCH-004, RF-MAN-001 |
| DB policy | RF-MIG-001 |
| NFR-1 Security and scope safety | RF-CRT-002, RF-PROM-003, RF-AVAIL-002, RF-READ-004, RF-TOOL-004, RF-SEC-001, RF-SEC-002 |
| NFR-2 Clear Knowledge semantics | RF-TOOL-003, RF-MANUAL-001, RF-UI-001, RF-UI-002 |
| NFR-3 Observability without content leakage | RF-CRT-003, RF-READ-003, RF-READ-005, RF-OBS-001, RF-OBS-002, RF-SEC-002 |
| NFR-4 Simple operation / no new RAG | RF-SRCH-003, RF-READ-002, RF-NORAG-001 |
| NFR-5 Testability and regressions | RF-NORAG-002, RF-REG-001, RF-REG-002, RF-UI-001, RF-UI-002, RF-UI-003 |
| Acceptance: upload/register reference files | RF-CRT-001, RF-UI-003 |
| Acceptance: no `artifact_id` requirement | RF-SCH-002, RF-PROM-002 |
| Acceptance: explicit Artifact promotion only | RF-PROM-001, RF-PROM-002 |
| Acceptance: optional provenance remains optional | RF-PROM-002, RF-PROM-003 |
| Acceptance: flexible metadata and status support | RF-SCH-001, RF-SCH-003, RF-MAN-001 |
| Acceptance: effective-scope availability | RF-AVAIL-001, RF-AVAIL-002 |
| Acceptance: metadata-first search | RF-SRCH-001, RF-SRCH-002, RF-SRCH-004 |
| Acceptance: bounded read or safe descriptor | RF-READ-001, RF-READ-002, RF-READ-003, RF-READ-005 |
| Acceptance: supported conversion reuse | RF-READ-002 |
| Acceptance: explicit converter routing for supported non-text files | RF-READ-006 |
| Acceptance: no chunks, embeddings, or vector indexes | RF-NORAG-001, RF-SRCH-003 |
| Acceptance: multiple matching files may coexist | RF-AVAIL-003, RF-SRCH-004 |
| Acceptance: archived files excluded from normal availability | RF-MAN-002, RF-AVAIL-002 |
| Acceptance: sibling-scope and cross-World denial | RF-CRT-002, RF-READ-004, RF-SEC-001 |
| Acceptance: no raw paths or unsafe storage details | RF-CRT-003, RF-READ-005, RF-SEC-002, RF-OBS-002 |
| Acceptance: safe lifecycle and access events | RF-OBS-001, RF-OBS-002 |
| Acceptance: tests cover mutation, no-mutation, metadata lookup, read, provenance, archive, descriptor safety | RF-SCH-001 through RF-SEC-002 |
| Acceptance: docs/tool guidance distinguish Knowledge categories | RF-MANUAL-001 |

## Human Approval Criteria

- Every FR in `plan.md` has at least one P0 or P1 scenario.
- Every acceptance bullet in `plan.md` is represented by at least one scenario.
- Scope denial is covered for cross-World, sibling City, sibling Department, and guessed inaccessible refs.
- No-RAG assertions are explicit: reference files must not create source-file chunks, embeddings, or vector indexes.
- No-leak assertions are explicit: no raw paths, temp paths, storage roots, storage refs, full content, or provider payloads in UI, tools, logs, or events.
- Regression scenarios protect existing memories, source files, source-file chunks, and `knowledge.store` behavior.
- The matrix is complete enough to approve Task 02 and begin implementation planning.
