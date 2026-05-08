# Knowledge Reference Files Product Alignment Plan

## Status

- **Issue**: GitHub #41 — Knowledge reference files: templates, models, headers, footers, and style assets
- **Parent story**: GitHub #38 — Knowledge Repository: scoped source files, reference files, and memories
- **Depends on**: Knowledge core + memories and Knowledge source files work
- **PR split**: Ticket 3 of 3

---

## PO / BA Alignment Summary

This plan has been checked against the current app state before task creation.

Aligned decisions:

- Reference files are **Knowledge-managed files**, not required Artifacts.
- This intentionally supersedes the Artifact-required wording in GitHub #41 and follows the already implemented source-file direction.
- `artifact_id` is optional provenance only when an operator explicitly promotes an existing Artifact.
- Mutation is **operator-managed** under the current control-plane UI. There is no separate admin/auth role in the app today.
- Lemmings may search/read visible reference files through governed tools, but they may not create, edit, archive, or delete them.
- The existing `/knowledge` **Templates** placeholder should become **Reference Files**.
- The v1 lifecycle should require `active` and `archived`. Recover/restore and hard delete are not required unless the existing Knowledge lifecycle is deliberately extended.

---

## 1. Goal

Add reference-file Knowledge items that users can upload and manage as reusable fixed files for Lemmings.

Reference files are used as models, templates, layout assets, examples, headers, footers, styles, and other reusable inputs that help a Lemming generate better outputs. They are selected mostly by metadata and availability, not by semantic RAG search.

The feature should make it possible for a Lemming to understand which fixed files are available in its scope and then read or reference the appropriate file when producing an output such as an email, contract, quotation, proposal, or PDF-ready document.

---

## 2. Business Need

LemmingsOS needs more than one type of durable Knowledge.

Users may provide:

- large documents that should be searched for facts;
- short memories or notes that should guide future behavior;
- fixed reusable files that should be used as examples, templates, or layout assets.

Reference files cover the third case.

Examples:

- quotation model;
- contract model;
- email model;
- PDF header;
- PDF footer;
- brand stylesheet;
- proposal structure;
- example customer-facing document;
- reusable document section;
- any other fixed file that should guide generation.

Without reference files, Lemmings may know facts from memories or source files, but they do not have a safe and explicit way to follow reusable document structures, headers, footers, or style assets selected by the operator.

---

## 3. Knowledge Concept Boundaries

The tool catalog and user-facing documentation must clearly distinguish the Knowledge categories.

| Concept | Purpose | Created by | Used by Lemmings for | Retrieval behavior |
|---|---|---|---|---|
| **Artifact** | Important output generated during a runtime conversation, such as a generated document, quotation, contract, report, or file worth preserving. | Usually created by LLM output and promoted by a user. | Referencing or downloading generated outputs. | Not Knowledge by default. May later be promoted into Knowledge by user action. |
| **Memory** | Short durable fact, rule, preference, or decision. | User or governed LLM tool. | Remembering small reusable information. | Direct lookup/filtering and possible inclusion in context. |
| **Source file / RAG file** | Uploaded document used to answer factual/contextual questions from its contents. | User upload or explicit registration. | Searching and reading relevant chunks. | Extraction, chunking, embeddings, and vector/full-text search. |
| **Reference file** | Fixed reusable file used as a model, template, layout asset, header, footer, style, or example. | Operator upload or optional user-approved promotion from an Artifact. | Following a known structure, style, or reusable component. | Metadata-first lookup and scoped availability listing; not primary RAG. |

### Key Product Rule

Reference files are **Knowledge-managed fixed files**. They do **not** require an Artifact.

An Artifact may be promoted into a reference file when a user explicitly chooses that flow, but `artifact_id` is optional provenance only. Generated files must not become reference files automatically.

---

## 4. Current Architecture Alignment

The implementation should extend the existing Knowledge model and keep the same product boundaries used by the previous Knowledge tasks.

The application already has:

- Knowledge items with shared metadata such as `kind`, title/content, tags, source, status, optional Artifact provenance, and scope;
- scope hierarchy support across World, City, Department, and Lemming;
- memories as short Knowledge items;
- source files as searchable RAG Knowledge backed by extraction, chunking, and indexing;
- file extraction capabilities from the source-file work;
- Artifact storage as a separate domain for generated outputs;
- runtime tools such as `knowledge.store`, `knowledge.search`, and `knowledge.read`;
- a `/knowledge` UI with Memories, Source Files, and a placeholder Templates tab;
- safe observability expectations that avoid leaking file paths, secrets, raw storage details, or full content in logs/events.

This task must not create a parallel Knowledge subsystem. It should extend the same Knowledge boundary with `reference_file` behavior.

---

## 5. Product Decisions

### Reference Files Are Knowledge, Not Artifacts

- Reference files do not require `artifact_id`.
- Direct operator upload creates a Knowledge-managed reference file.
- A generated Artifact may be promoted into a reference file only through explicit user action.
- When an Artifact is deleted, any optional provenance relation may be cleared or marked unavailable without deleting the reference file itself.
- Search and read behavior must depend on the Knowledge-managed reference file, not on the optional Artifact provenance.

### Reference Files Are Not RAG Files

- Reference files do not use source-file chunks or vector indexes.
- They are not retrieved primarily by semantic similarity.
- They are selected by scope, type, title, tags, status, source, and intended use.

### Reference File Read Behavior

Reference files are read for generation guidance, not for RAG indexing.

When `knowledge.read` is used on a reference file:

- If the stored file is directly text-readable, the system returns bounded text content.
- If the stored file is a supported binary or structured document, the system uses the existing safe extraction/conversion tooling from the source-file implementation to produce bounded text.
- MarkItDown is the preferred converter for uploaded Office/PDF/document-like files where supported.
- Trafilatura is used for URL/HTML/web-content references where that reference source mode is supported.
- Existing PDF fallback tooling may be reused where already available.
- Conversion must not create source-file chunks, embeddings, vector indexes, or RAG records.
- If content cannot be safely converted, `knowledge.read` returns a safe descriptor and a non-leaking explanation instead of raw bytes or paths.

### Types Stay Flexible

Reference file type should be flexible text rather than a strict database enum.

Suggested values may be documented for consistency, but the system should allow operators to create practical project-specific types such as:

- `quote_template`
- `contract_template`
- `email_template`
- `header`
- `footer`
- `style`
- `example`
- `proposal_structure`
- `brand_asset`
- `other`

Tags should carry additional classification such as customer, brand, default status, language, format, or workflow.

### Lifecycle

Reference files use a simple lifecycle:

- `active`
- `archived`

Archived reference files are excluded from normal Lemming availability and search.

### Operator-Managed Creation

Only operators may upload, register, edit, or archive reference files in v1.

Recover/restore and hard-delete flows are not part of the required product scope unless the implementation explicitly extends the existing Knowledge lifecycle.

### Tool Boundary

- `knowledge.store` remains memory-oriented.
- Lemmings may search and read reference files through governed tools.
- Lemmings must not create, edit, archive, delete, or promote reference files.

### Scope Model

Reference files use the same Knowledge scope hierarchy as the previous Knowledge tasks:

- World
- City
- Department
- Lemming, representing the current product-facing Lemming Type scope until a separate Lemming Type model exists

Visibility rules:

| Reference file scope | Visible to |
|---|---|
| World | Allowed descendants in the same World |
| City | That City and descendants |
| Department | That Department and descendants |
| Lemming | That Lemming only |

Cross-World access is never allowed. Sibling City and sibling Department access is denied by default.

---

## 6. Product Scope

### In Scope

This PR covers:

- Reference file Knowledge items with `kind = "reference_file"` or the closest existing discriminator naming used by the codebase.
- Operator upload or registration of fixed reference files into Knowledge.
- Optional user-approved promotion from an existing Artifact into a reference file.
- Knowledge-managed storage for reference files.
- Optional Artifact provenance, when applicable.
- Flexible reference file type, tags, title, description, source, status, and scope metadata.
- Reference file listing, filtering, detail view, metadata editing, and archive behavior where consistent with existing Knowledge management.
- `knowledge.search` support for metadata-first reference-file lookup.
- `knowledge.read` support for bounded reference content or safe descriptors.
- A scoped availability summary so Lemmings can know which fixed files are available before trying to search for an exact name.
- Safe descriptors for future document/PDF tools.
- Safe lifecycle and access events.
- Tests covering scope enforcement, lookup behavior, read behavior, descriptor safety, and operator-managed mutation.

### Out of Scope

This PR does **not** include:

- A new template engine.
- PDF rendering changes.
- Document generation changes.
- Automatic LLM promotion of generated files into Knowledge.
- Source-file chunking or vector indexing for reference files.
- Advanced RAG behavior for reference files.
- Complex versioning for templates.
- Recover/restore workflow for archived reference files.
- Hard-delete workflow for reference files, unless explicitly chosen later.
- Public file sharing.
- Raw filesystem path exposure.
- A new permission model beyond the current control-plane access behavior.

---

## 7. Functional Requirements

### FR-1 — Add Reference Files

Operators can add fixed reference files from the Knowledge management surface.

Acceptance points:

- Operator selects or uploads a file.
- Operator selects an allowed scope.
- Operator provides title and optional description.
- Operator provides a flexible reference file type.
- Operator may add tags.
- System stores the file through Knowledge-managed storage.
- System creates a reference-file Knowledge item.
- System does not require an Artifact.
- System never exposes raw storage paths in UI, tools, logs, or events.

### FR-2 — Promote Artifact To Reference File

Operators can promote an existing Artifact into a Knowledge-managed reference file through explicit action.

Acceptance points:

- Operator approval is required.
- The generated file is not added automatically.
- Operator selects type, scope, title, description, and tags.
- System records optional Artifact provenance when available.
- Artifact provenance remains optional and does not become the storage contract for reference files.
- If the Artifact later becomes unavailable, the reference file remains manageable and the provenance link may be cleared or marked unavailable.
- Search/read behavior must not depend on the Artifact after reference-file creation.

### FR-3 — Manage Reference Files

Operators can manage reference files from the Knowledge surface.

Acceptance points:

- List reference files by accessible scope.
- Filter by text, type, tags, status, and scope.
- View reference file metadata and safe descriptor information.
- Edit title, description, type, tags, and metadata.
- Archive active reference files.
- Archived reference files are not provided to Lemmings as available references.
- Recover/restore and hard delete are deferred unless the existing Knowledge lifecycle is intentionally expanded.

### FR-4 — Provide Scoped Reference Availability To Lemmings

Lemmings need to know which fixed reference files are available in their effective scope without guessing exact file names.

Acceptance points:

- Runtime context or tool catalog guidance provides a compact list or summary of available reference files for the current scope.
- This may be implemented as tool catalog metadata, a lightweight availability call, or runtime context injection.
- The summary includes safe metadata such as title, type, tags, status, scope, and descriptor ID.
- The summary excludes archived, inaccessible, or cross-scope files.
- The summary does not include raw file paths, storage refs, or full file content.
- Lemmings can use the summary to decide which reference file to read or pass to a future generation tool.

Suggested wording for tool guidance:

```text
Knowledge contains four related concepts:
- memories: short reusable facts or rules;
- source files: searchable documents used for RAG retrieval;
- reference files: fixed templates, examples, headers, footers, and style assets selected by metadata;
- artifacts: generated outputs, not Knowledge unless explicitly promoted by a user.

When generating documents, emails, quotations, contracts, or PDFs, first inspect the available reference files in scope. Prefer matching reference files by type, tags, and title before generating structure or style from scratch.
```

### FR-5 — Search Reference Files

`knowledge.search` supports metadata-first reference-file lookup.

Conceptual input:

```json
{
  "kind": "reference_file",
  "type": "quote_template",
  "tags": ["default"],
  "query": "quotation",
  "scope": "current"
}
```

Conceptual output:

```json
{
  "results": [
    {
      "knowledge_item_id": "...",
      "reference_ref": "...",
      "title": "Default quotation model",
      "type": "quote_template",
      "tags": ["default"],
      "status": "active",
      "scope": {"type": "department"},
      "descriptor": {
        "kind": "reference_file",
        "content_type": "text/markdown",
        "safe_to_read": true
      }
    }
  ]
}
```

Acceptance points:

- Search supports kind/category filter for `reference_file`.
- Search supports type, tags, status, text query, and scope filters.
- Search defaults to the caller's effective scope.
- Search returns metadata and safe descriptors, not raw file paths.
- Search respects hierarchy inheritance and rejects sibling/cross-World access.
- Search can return multiple matches when several valid reference files exist.
- Search sorts results predictably, preferring nearest scope and stronger metadata matches.

### FR-6 — Read Reference Files

`knowledge.read` supports reference files.

Conceptual input:

```json
{
  "knowledge_item_id": "...",
  "max_chars": 4000
}
```

Conceptual output:

```json
{
  "knowledge_item_id": "...",
  "reference_ref": "...",
  "title": "Default quotation model",
  "type": "quote_template",
  "tags": ["default"],
  "content": "...bounded content when available...",
  "descriptor": {
    "kind": "reference_file",
    "content_type": "text/markdown",
    "safe_to_pass_to_tools": true
  }
}
```

Acceptance points:

- Read enforces scope independently from search.
- Read returns bounded text content when the file is directly readable.
- Read uses the safe conversion/extraction capability from source-file work for supported files such as PDF or office documents.
- Read returns a safe descriptor when full content is not appropriate or not available.
- Read does not expose raw storage paths, raw provider responses, secret values, or internal runtime state.
- Read errors must not reveal whether inaccessible files exist.

### FR-7 — Safe Descriptors For Future Document/PDF Tools

Reference files should expose safe descriptors that future generation tools can consume.

Acceptance points:

- Each active reference file has a stable safe reference identifier.
- The descriptor includes enough metadata for future tools to decide whether it can be used.
- Descriptor shape remains generic instead of forcing separate fields for every future tool.
- Future document/PDF tools should be able to accept a reference descriptor without needing raw filesystem paths.

Recommended conceptual descriptor:

```json
{
  "reference_ref": "...",
  "knowledge_item_id": "...",
  "kind": "reference_file",
  "type": "header",
  "title": "Default PDF header",
  "tags": ["default", "brand"],
  "content_type": "text/html",
  "safe_to_read": true,
  "safe_to_pass_to_tools": true
}
```

### FR-8 — Duplicate And Variant Handling

The system allows multiple active reference files with similar type or tags.

Acceptance points:

- Multiple templates or examples may coexist.
- Search/list returns multiple matches rather than enforcing premature uniqueness.
- Sorting should make the most likely match visible first.
- Operators can use tags such as `default`, customer name, language, or workflow to distinguish variants.

---

## 8. Non-Functional Requirements

### NFR-1 — Security And Scope Safety

- All reference file operations enforce World, City, Department, and Lemming scope rules server-side.
- Cross-World access is never allowed.
- Sibling City and sibling Department access is denied by default.
- Reference file mutation remains operator-managed and unavailable to Lemmings.
- Lemming read/search access is governed by runtime tool policy and effective scope.
- Raw filesystem paths, configured storage roots, upload temp paths, workspace paths, and internal storage refs are never exposed.

### NFR-2 — Clear Knowledge Semantics

- The UI and tool catalog must make the difference between Artifacts, Memories, Source Files, and Reference Files clear.
- Reference files must not be described as RAG documents.
- Source files must not be described as templates or fixed generation assets.
- Artifacts must not be described as Knowledge unless the user explicitly promotes them.

### NFR-3 — Observability Without Content Leakage

- Emit safe events for lifecycle and access operations.
- Event payloads include safe hierarchy metadata and Knowledge identifiers.
- Events do not include full file content, raw storage paths, storage roots, secrets, credentials, or unsafe runtime state.
- Search/read events may record operation metadata, but not user-provided full content or extracted file bodies.

### NFR-4 — Simple Operation

- Do not add a new background processing architecture for reference files unless already required by the reused extraction path.
- Do not add a new external vector database or RAG framework.
- Do not introduce a new template engine.
- Keep the implementation aligned with the existing Knowledge and file-storage patterns.

### NFR-5 — Testability

- Tests must cover operator-managed mutation, Lemming no-mutation behavior, scope inheritance, sibling denial, cross-World denial, metadata lookup, read behavior, archive behavior, optional Artifact provenance, and descriptor safety.
- Tests must verify that raw paths and unsafe storage details are not exposed in tool outputs or events.

---

## 9. UX Requirements

### Knowledge Reference Files List

| State | Behavior |
|---|---|
| Empty | Explain that no reference files exist and show an operator-managed add action. |
| Populated | Show title, type, tags, scope, status, source, and updated time. |
| Filtered empty | Show a no-results message and keep current filters visible. |
| Archived filter | Show archived files separately or through a status filter. |

### Reference File Detail

| State | Behavior |
|---|---|
| Active | Show metadata, safe descriptor, optional preview, and management actions. |
| Archived | Show archived state and explain that archived files are hidden from Lemming availability. |
| Unreadable content | Show metadata and descriptor, with a safe explanation that content preview is unavailable. |
| Provenance unavailable | Show that optional Artifact provenance is unavailable without breaking the reference file record. |

### Upload / Registration

| State | Behavior |
|---|---|
| Accepted | Create the reference file and show it in the list. |
| Validation error | Preserve form input and show field-level errors. |
| Unauthorized | Deny mutation and do not reveal inaccessible scopes. |

---

## 10. Events And Observability

Suggested safe event types:

- `knowledge.reference_file.created`
- `knowledge.reference_file.updated`
- `knowledge.reference_file.archived`
- `knowledge.reference_file.search_performed`
- `knowledge.reference_file.read`
- `knowledge.reference_file.artifact_promoted`

Recover, delete, or provenance-clearing events should only be added if those deferred lifecycle flows are explicitly implemented later.

Safe payload fields may include:

- `world_id`
- `city_id`
- `department_id`
- `lemming_id`
- `lemming_instance_id`
- `knowledge_item_id`
- `reference_ref`
- `type`
- `status`
- `source`
- `actor_user_id` when future auth provides one
- result count for search, when safe

Do not include:

- full file content;
- raw filesystem paths;
- storage roots;
- raw storage refs if they reveal implementation details;
- secrets or connection material;
- raw extraction output;
- unsafe runtime state.

---

## 11. Acceptance Criteria

- [ ] Operators can upload/register reference files into Knowledge.
- [ ] Reference files do not require `artifact_id`.
- [ ] Existing Artifacts can be promoted into reference files only through explicit user action.
- [ ] Optional Artifact provenance does not control whether the reference file remains valid.
- [ ] Reference files support title, description, flexible type, tags, status, source, and scope metadata.
- [ ] Reference files use the same scope inheritance rules as other Knowledge items.
- [ ] Reference file mutation is operator-managed.
- [ ] Lemmings can discover available reference files in their effective scope without guessing exact names.
- [ ] `knowledge.search` can find reference files by type, tags, query, status, and scope.
- [ ] `knowledge.read` can return authorized bounded content or a safe descriptor.
- [ ] PDF/office/text conversion uses the source-file extraction capability when the file type is supported.
- [ ] Reference files do not create source-file chunks or vector embeddings.
- [ ] Multiple matching reference files may coexist.
- [ ] Archived reference files are excluded from normal Lemming availability.
- [ ] Search/read prevents sibling-scope and cross-World access.
- [ ] Tool outputs never expose raw file paths or unsafe storage details.
- [ ] Events are emitted for lifecycle and access operations with safe payloads.
- [ ] Tests cover scope enforcement, operator-managed mutation, Lemming no-mutation behavior, metadata lookup, read behavior, optional Artifact provenance, archive behavior, and descriptor safety.
- [ ] Documentation/tool guidance clearly distinguishes Artifacts, Memories, Source Files/RAG, and Reference Files.

---

## 12. Proposed Task Sequence

This grouped sequence was used for product planning only.
The authoritative implementation sequence is Section 14: Generated Implementation Task Plan.

### Task 01 — QA scenarios and acceptance coverage

**Suggested agent**: `qa-test-scenarios`

Define test scenarios for:

- operator upload and management;
- optional Artifact promotion;
- scoped availability listing;
- metadata search;
- read behavior;
- archive behavior;
- Lemming no-mutation behavior;
- sibling/cross-World denial;
- safe descriptor and no-path-leak guarantees.

### Task 02 — Data model and Knowledge contract alignment

**Suggested agents**: `dev-db-performance-architect`, `dev-backend-elixir-engineer`

Extend the Knowledge model to support reference files without making Artifacts mandatory.

Expected outcome:

- Reference files fit the existing Knowledge context.
- Flexible type, tags, status, source, and scope are supported.
- Optional Artifact provenance is nullable and safe.
- Archive behavior follows existing Knowledge conventions.

### Task 03 — Backend behavior and tool support

**Suggested agent**: `dev-backend-elixir-engineer`

Implement reference-file behavior in Knowledge APIs and runtime tools.

Expected outcome:

- Operator-managed create/update/archive behavior.
- Scoped list/search/read behavior.
- Safe descriptors.
- Scoped reference availability for Lemmings.
- Optional reuse of safe content conversion for readable previews.

### Task 04 — UI management surface

**Suggested agent**: `dev-frontend-ui-engineer`

Add the reference-file management flow to the existing Knowledge surface.

Expected outcome:

- List, filter, detail, upload/register, edit, and archive flows.
- Clear distinction between Memories, Source Files, Reference Files, and Artifacts.
- Accessible and responsive UI states.

### Task 05 — Tests

**Suggested agent**: `qa-elixir-test-author`

Add tests for backend, tool, and UI behavior.

Expected outcome:

- Scope and access-boundary tests.
- Tool output safety tests.
- Operator-managed mutation tests.
- Lemming no-mutation tests.
- Metadata search and read tests.
- Archive tests.
- Optional Artifact provenance tests.

### Task 06 — Documentation and tool catalog wording

**Suggested agent**: `docs-feature-documentation-author`

Document the product behavior and update tool guidance.

Expected outcome:

- Operators understand when to use Memories, Source Files, Reference Files, and Artifacts.
- Lemmings receive clear guidance on checking available reference files before generating outputs.
- The docs avoid implying that reference files are RAG-indexed or Artifact-required.

### Task 07 — Security and accessibility audit

**Suggested agents**: `audit-security`, `audit-accessibility`, `audit-pr-elixir`

Review the completed work before release.

Expected outcome:

- No unsafe path, secret, or content leakage.
- Scope enforcement is consistent.
- Tool outputs are safe.
- UI is accessible and consistent with the rest of the app.
- Code and tests are ready for PR review.

### Task 08 — Release notes and rollout

**Suggested agent**: `rm-release-manager`

Prepare release notes and operational notes.

Expected outcome:

- Clear description of the new Knowledge category.
- Migration and rollback notes.
- Validation checklist.
- Known limitations and follow-up items.

---

## 13. Follow-Up Items Outside This PR

The following can be handled after this issue:

- Document/PDF tools consuming `reference_ref` directly.
- Template rendering engine, if later needed.
- Version history for reference files.
- Default reference selection rules per workflow.
- Bulk import/export of reference files.
- Advanced preview support beyond the reused extraction/conversion capability.

---

## 14. Generated Implementation Task Plan

### Metadata

- **Source plan**: `llms/tasks/0015_knowledge_reference_file/plan.md`
- **Generated**: 2026-05-08
- **Status**: PLANNING
- **Operating role**: `tl-architect`

This generated sequence converts the product alignment plan into sequential, human-approved implementation tasks. The source plan is considered ready for task decomposition because it includes PO/BA alignment, scope, functional requirements, non-functional requirements, UX states, acceptance criteria, and an initial task sequence.

### Codebase Findings

- `LemmingsOs.Knowledge.KnowledgeItem` currently supports `kind = "memory" | "source_file"` and does not yet include `reference_file`.
- Source files already have a separate metadata table, managed storage service, chunk table, indexing lifecycle, `knowledge.search`, and `knowledge.read` support.
- Reference files must not reuse source-file chunking/vector behavior and should have their own metadata/storage contract or an explicit shared storage abstraction that preserves reference-file semantics.
- `/knowledge` already has Memories and Source Files tabs plus a Templates placeholder. The placeholder should become Reference Files.
- `LemmingsOs.Tools.Adapters.Knowledge` currently keeps `knowledge.store` memory-only and routes search/read to ready source-file chunks.
- `LemmingsOs.ModelRuntime` includes tool guidance that must be updated so Lemmings distinguish memories, source files, reference files, and artifacts.
- `LemmingsOs.Events` provides a durable safe-event boundary that can record reference-file lifecycle and access events without leaking content or paths.

### Technical Summary

- **New files anticipated**: migration, reference-file schema, reference-file storage/read support, factories/tests, and generated docs/runbook artifacts.
- **Modified files anticipated**: `KnowledgeItem`, `Knowledge`, tool adapter, runtime tool catalog/guidance, `/knowledge` LiveView/template, factory/test support, config/docs as needed.
- **Database migrations**: Yes. All DB changes for this PR should be consolidated into one migration file.
- **External dependencies**: None.
- **Background jobs**: Not expected for v1. Supported reference-file conversion happens through the existing safe extraction/conversion boundary at read/preview time and must not create source-file chunks, embeddings, vector indexes, or RAG records.

### Assumptions For Human Review

- Operator-managed means the existing control-plane UI and context boundaries, not a new auth/admin role system.
- Existing `lemming_id` scope continues to represent the current product-facing Lemming Type scope until a separate model exists.
- `knowledge_items.content` may continue to hold a short description/summary for reference files if required by the existing schema; original bytes and extracted bodies must not be stored there as full content.
- Reference file type is flexible text. Suggested values may be shown in UI, but database/context validation must not enforce a closed enum for type.
- `artifact_id` remains optional provenance only. Reference-file storage/read/search must not depend on an Artifact remaining available.
- Reference files do not create source-file chunks, embeddings, or vector indexes.
- Database-level constraints should be minimal. Prefer Ecto schema/changeset validation for business rules such as kind/status/type/content-type bounds.
- Database constraints are allowed only for referential integrity, unique guarantees, and required indexes.
- Do not add DB `CHECK` constraints for reference-file type, status, content type, descriptor flags, or lifecycle business rules unless explicitly approved.
- All database changes for this PR should be delivered in a single migration file, even if multiple tasks add DB-related behavior.

#### Database Constraint Policy

For this PR, database migrations should define structure, references, unique guarantees, and indexes only.

Business rules belong in Ecto schemas, changesets, and Knowledge context validation. This includes reference-file type validation, status validation, content-type validation, lifecycle rules, descriptor safety flags, and bounded text rules.

Do not add DB `CHECK` constraints or database-enforced enums unless explicitly approved.

All DB changes for this PR must be consolidated into a single migration file.

### Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Reference files accidentally inherit RAG/source-file behavior | Medium | High | Separate task boundaries for data contract, search/read, and tool integration; tests assert no chunks/embeddings. |
| Scope leakage through availability/search/read | Medium | High | Backend task must enforce scope independently in every API; tests include cross-World and sibling denial. |
| Path or storage ref leakage in UI/tools/events | Medium | High | Descriptor contract is explicit; security audit includes sentinel path/content checks. |
| Artifact provenance becomes a hidden storage dependency | Low | Medium | Artifact promotion task must copy/register into Knowledge-managed storage and tests must simulate unavailable provenance. |
| UI placeholder conversion breaks existing memory/source-file flows | Medium | Medium | Split UI task and LiveView/tool tests; keep existing stable IDs where possible and add reference-file IDs. |

### Roles

#### Human Reviewer

- Approves each task before the next begins.
- Executes all git operations.
- Can reject a task and request revisions before the sequence continues.
- Performs final sign-off after audits and release validation.

#### Executing Agents

Each task names exactly one assigned agent from `llms/agents/agent_catalog.md`.

### Task Sequence

1. `01_reference_file_test_scenarios.md` - `qa-test-scenarios`
2. `02_reference_file_schema_and_migration.md` - `dev-db-performance-architect`
3. `03_reference_file_storage_boundary.md` - `dev-backend-elixir-engineer`
4. `04_reference_file_domain_context_and_lifecycle.md` - `dev-backend-elixir-engineer`
5. `05_reference_file_search_read_and_availability.md` - `dev-backend-elixir-engineer`
6. `06_artifact_promotion_to_reference_file.md` - `dev-backend-elixir-engineer`
7. `07_reference_file_runtime_tool_integration.md` - `dev-backend-elixir-engineer`
8. `08_reference_file_knowledge_liveview_surface.md` - `dev-frontend-ui-engineer`
9. `09_reference_file_detail_and_promotion_ui.md` - `dev-frontend-ui-engineer`
10. `10_reference_file_observability.md` - `dev-logging-daily-guardian`
11. `11_reference_file_backend_tests.md` - `qa-elixir-test-author`
12. `12_reference_file_liveview_and_tool_tests.md` - `qa-elixir-test-author`
13. `13_reference_file_documentation_and_tool_guidance.md` - `docs-feature-documentation-author`
14. `14_reference_file_elixir_style_audit.md` - `audit-pr-elixir`
15. `15_reference_file_test_style_audit.md` - `qa-elixir-test-author`
16. `16_reference_file_security_audit.md` - `audit-security`
17. `17_reference_file_accessibility_audit.md` - `audit-accessibility`
18. `18_reference_file_final_pr_audit.md` - `audit-pr-elixir`
19. `19_reference_file_release_validation.md` - `rm-release-manager`

### Human Approval Gates

After each task, the human reviewer must verify the task file acceptance criteria and approve before the next task starts. If a task changes implementation code, the executing agent should run the narrowest relevant checks first and `mix precommit` when the implementation is complete.
