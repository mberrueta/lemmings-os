# Knowledge Core + Memories Implementation Plan

## Status

- **Issue**: GitHub #39 — Knowledge core + memories
- **Parent story**: GitHub #38 — Knowledge Repository: scoped source files, reference files, and memories
- **PR split**: Ticket 1 of 3

---

## 1. Goal

Implement the shared Knowledge Repository foundation and the first supported Knowledge item: **memories / notes**.

This PR establishes the product model, scope rules, user management behavior, Lemming-created memory path, and event visibility needed before adding file-based Knowledge in later PRs.

The feature should let users and Lemmings store small, reusable facts or rules that help future executions without requiring an uploaded file or Artifact.

Examples:

- `Client ACME prefers short email summaries in Portuguese.`
- `Use Entremundos tone: premium, warm, concise.`
- `For quotes, always include payment terms.`
- `This Department prefers proposals in Spanish.`

---

## 2. Business Need

LemmingsOS needs a durable and scoped way to preserve operational knowledge that is useful across future agent executions.

Today, useful details may be lost inside individual chats or generated files. Users need a way to keep stable knowledge at the correct hierarchy level so Lemmings can reuse it safely and predictably.

This first slice intentionally starts with memories because they are the smallest Knowledge item type and do not require file upload, Artifact storage, extraction, chunking, Tika, pgvector, or semantic search.

---

## 3. Product Scope

### In scope

This PR covers:

- Shared Knowledge item foundation.
- Memory/note Knowledge items.
- Manual user CRUD for memories.
- Hard delete for memories.
- Lemming-created memories through `knowledge.store`.
- Lemming memory scope. Product language may call this "Lemming Type", but in this repo it maps to the existing persisted `lemmings.id` / `lemming_id` scope.
- Downward scope inheritance for memory visibility.
- Safe scope validation.
- Basic tags, status, source, and creator metadata.
- Events for memory lifecycle actions.
- Best-effort chat notification when a Lemming creates a memory.
- One Knowledge surface with internal memory management.

### Out of scope

This PR does **not** include:

- Source files.
- Reference files.
- File uploads.
- Artifact promotion into Knowledge.
- Tika integration.
- Chunking.
- pgvector.
- Semantic search.
- Advanced RAG.
- Archive / unarchive behavior.
- Soft delete lifecycle.
- Activity/timeline notification UI.
- Lemming-facing file Knowledge tools.
- `knowledge.search` and `knowledge.read` as full Lemming tools, unless a minimal internal read/list API is needed for UI behavior.

---

## 4. Knowledge Model Direction

The Knowledge Repository should use one shared internal model that can later support three Knowledge families:

1. memories
2. source files
3. reference files

For this PR, only **memories** are implemented.

The product and Lemming-facing API should stay memory-first and avoid asking the LLM to choose between future file categories that are not implemented yet.

### Category / kind decision

The plan should avoid exposing `category` as a required Lemming input in this PR.

Reason:

- `knowledge.store` is memory-only in this PR.
- Asking the LLM to send `category = memory` adds no real value.
- Future file-based Knowledge can add explicit operations or safe filters when those categories exist.

Implementation may still keep an internal discriminator such as `kind = memory` or `category = memory` if useful for future schema compatibility, but it should be runtime-owned/defaulted, not something the Lemming must choose.

### Type decision

The plan should avoid requiring a memory `type` enum in this PR.

Reason:

- `type` and `tags` overlap for MVP usage.
- A fixed memory type list such as `client_preference`, `business_rule`, or `style_note` may confuse LLMs and users.
- Tags are more flexible and enough for the first version.

If the UI needs a later grouping field, it can be added after observing real usage.

### Conceptual fields

A memory should conceptually support:

| Field | Requirement for memories |
|---|---|
| `id` | Required |
| `world_id` | Required |
| `city_id` | Nullable depending on scope, but populated when the memory belongs under a City path |
| `department_id` | Nullable depending on scope, but populated when the memory belongs under a Department path |
| `lemming_id` | Nullable; required for Lemming-scoped memories. This is the persisted field for the product concept currently called Lemming Type. |
| internal `kind` / `category` | Runtime-owned/defaulted to `memory`; not exposed as required Lemming input |
| `title` | Required |
| `content` | Required |
| `artifact_id` | Nullable and always null for memories |
| `tags` | Optional lightweight string list |
| `source` | Required: `user` or `llm` |
| `status` | Required; defaulted to `active`; active memory only in this PR |
| `creator metadata` | Required where available |
| `inserted_at` / `updated_at` | Required |

### Tags

Tags should be optional and lightweight.

Recommended tag examples:

- `customer:ACME`
- `language:pt-BR`
- `proposal`
- `legal_document`
- `tone`
- `payment_terms`

The system should not require the Lemming to select from a large taxonomy. A small amount of free-form tagging is preferable to many structured options in the tool input.

---

## 5. Scope Model

Memories can be scoped to:

- World
- City
- Department
- Lemming

### Scope rules

- Cross-World access is never allowed.
- Sibling City access is not allowed by default.
- Sibling Department access is not allowed by default.
- Downward inheritance applies by default.
- A Lemming-scoped memory belongs to that Lemming (`lemming_id`), but should also carry its parent `department_id`, `city_id`, and `world_id` for validation and listing.
- Product-facing copy may use "Lemming Type" when that is clearer to users, but implementation should not introduce a new Lemming Type table or field in this PR.

### Visibility rules

| Memory scope | Visible to |
|---|---|
| World | Allowed descendants in the same World |
| City | That City and descendants |
| Department | That Department and descendants |
| Lemming | That Lemming |

### Department memory listing behavior

When a user is viewing a Department Knowledge surface, the UI should be able to show:

- World memories inherited by that Department.
- City memories inherited by that Department.
- Department memories directly owned by that Department.
- Lemming memories for Lemmings that belong to that Department.

This allows a Department-level operator to understand the effective memory context available inside that Department while preserving the narrower ownership of Lemming memories.

---

## 6. User Management Experience

The control-plane UI should expose memories through one **Knowledge** surface.

Recommended placement:

- Add one repo-compatible Knowledge surface.
- Default implementation: add a global `/knowledge` LiveView linked from the main navigation, with scope filters and deep links for viewing/editing one memory.
- If implementation later embeds Knowledge into existing `/world`, `/cities`, `/departments`, or `/lemmings/:id` surfaces, it should preserve the same scope validation and listing behavior.
- The Knowledge surface may internally organize content by Knowledge family later. In this PR, it only needs to show memories.
- Future PRs can add internal sections or sub-tabs for `Source files` and `Reference files`.

### User actions

Users should be able to:

- Create a memory.
- Edit memory title.
- Edit memory content.
- Edit tags.
- View memory source: `user` or `llm`.
- View the memory scope.
- List memories relevant to the current scope.
- Filter by tag, source, or status where practical.
- Hard delete a memory.

### Delete behavior

For this MVP, deleting a memory means **hard delete**.

Archive / unarchive / final deletion workflows are intentionally out of scope because they require a larger lifecycle model and extra UX that is not necessary for the first version.

---

## 7. LLM-Created Memories

Lemmings may create memories through a governed `knowledge.store` tool.

### Product rules

- LLM-created memories are stored automatically.
- The user does not approve each memory before storage in this PR.
- The memory must use `source = llm`.
- The memory must include creator Lemming / instance metadata where available.
- The memory must be scoped to the current execution context.
- The default scope for LLM-created memories is the current **Lemming** (`lemming_id`), matching the product concept currently called Lemming Type.
- The Lemming cannot create memories outside the allowed World / City / Department / Lemming ancestry.
- Memory creation must emit a safe event.
- The user must be informed in chat when a memory is created.

### Chat notification

The notification is best-effort.

If PubSub delivery or LiveView state update fails, the memory creation itself should still succeed if the store operation completed successfully.

Example notification:

```text
Memory added:
ACME — email summary language
Client ACME prefers short email summaries in Portuguese.
[View / Edit memory]
```

The preferred notification includes a button or link that opens the created memory in the Knowledge UI for view/edit. Delete may be available from that destination page; it does not need to be a chat action in MVP.

MVP default for the current repo: because persisted chat messages are plain role/content transcript entries, the implementation may append or render a visible assistant/system-style chat message containing the memory title, a short summary, and a plain Knowledge path to the created memory.

The exact UI styling may be simplified in the first implementation, but the user must receive a visible indication in chat when possible.

---

## 8. Lemming Tool Surface

### `knowledge.store`

This PR implements the first Lemming-facing Knowledge tool:

```text
knowledge.store
```

For this PR, the tool stores memories only. The Lemming should not be asked to choose a category.

### Supported input

Conceptual input:

```json
{
  "title": "ACME — email summary language",
  "content": "Client ACME prefers short email summaries in Portuguese.",
  "tags": ["customer:ACME", "email", "language:pt-BR"],
  "scope": "lemming_type"
}
```

### Title guidance for the tool catalog

The tool catalog description should suggest a simple title format so Lemmings create searchable, mostly uniform memories.

Recommended format:

```text
<Subject> — <specific preference/rule/fact>
```

Examples:

- `ACME — email summary language`
- `Entremundos — proposal tone`
- `Quotes — payment terms`
- `Department proposals — preferred language`

Rules for Lemmings:

- Keep the title short.
- Put the main subject first.
- Use tags for extra metadata, not a long title.
- Avoid generic titles like `Important note`, `Memory`, or `Client preference`.

### Expected output

Conceptual output:

```json
{
  "knowledge_item_id": "...",
  "status": "stored",
  "scope": "lemming_type"
}
```

### Tool constraints

- The tool stores memories only in this PR.
- The Lemming should not provide `category`, `type`, or `artifact_id`.
- File-based Knowledge is rejected.
- The tool cannot expose raw database internals or file paths.
- Invalid scope requests are rejected safely.
- The tool result should summarize what was stored without leaking unrelated runtime state.

---

## 9. Functional Requirements

### FR-1 — Shared Knowledge item foundation

The system must define a shared Knowledge item foundation that can support future Knowledge families while implementing only memories in this PR.

Acceptance points:

- Knowledge items can represent memories.
- Memory items require title and content.
- Memory items cannot reference an Artifact.
- The model includes scope, tags, status, source, and creator metadata.
- Any internal category/kind discriminator is runtime-owned/defaulted, not selected by the Lemming.

### FR-2 — Manual memory creation

A user must be able to create a memory from the Knowledge surface.

Acceptance points:

- User selects or inherits a scope from the current page.
- User enters title, content, and optional tags.
- Created memory appears in the relevant Knowledge list.
- Created memory uses `source = user`.

### FR-3 — Manual memory editing

A user must be able to edit existing memory metadata and content.

Acceptance points:

- User can edit title, content, and tags.
- Scope changes may be restricted or omitted in MVP to avoid accidental cross-scope movement.
- Update events are emitted.
- Invalid edits show clear validation errors.

### FR-4 — Manual memory deletion

A user must be able to hard delete a memory.

Acceptance points:

- Deleting removes the memory from active lists.
- Delete emits a safe event.
- Delete does not require archive / unarchive behavior.
- Delete cannot affect memories outside the user’s allowed scope.

### FR-5 — Memory listing by effective scope

A user must be able to list memories relevant to the current hierarchy page, with simple filtering and pagination.

Acceptance points:

- World page can show World memories.
- City page can show City memories and inherited World memories.
- Department page can show Department memories, inherited City/World memories, and Lemming memories belonging to that Department.
- Lemming page can show its own memories and inherited parent memories where useful.
- Cross-World and sibling-scope memories do not appear.
- The list includes a single text search box that searches memory title and tags.
- The list supports filtering by tag through the same search box or a simple tag filter where practical.
- The list is paginated with a default page size of 25 memories per page.
- Pagination should use local Ecto queries with stable ordering, `limit`, `offset`, and a count query. Do not add a pagination dependency for this MVP.

### FR-6 — Filtering

The Knowledge surface should support basic filters without creating a complex search UI.

Acceptance points:

- A single text box searches title and tags.
- Filter by source: user / llm where practical.
- Filter by status if status is visible in UI.
- Pagination defaults to 25 memories per page.
- Pagination should use the project's existing Ecto/Repo conventions rather than adding a new dependency.

Filtering may be basic in MVP. Advanced search, semantic search, ranking, and complex query syntax are not required.

### FR-7 — `knowledge.store` for memories

A Lemming must be able to create a memory through `knowledge.store`.

Acceptance points:

- Tool stores memories only.
- Tool validates title, content, tags, and scope.
- Tool does not require the Lemming to choose `category` or `type`.
- Tool defaults to the current Lemming scope when scope is omitted or when current execution context implies that scope.
- Tool stores `source = llm`.
- Tool records creator Lemming / instance metadata when available.
- Tool returns a safe success payload.

### FR-8 — Chat notification for LLM-created memory

When a Lemming creates a memory, the user should be informed in chat.

Acceptance points:

- Chat receives a best-effort notification after successful memory creation.
- Notification includes title/content summary and, where the UI supports it, a button or link to view/edit the created memory. MVP may use a plain Knowledge path in the chat message.
- Failure to publish the notification does not roll back the stored memory.

### FR-9 — Events

The system must emit safe events for memory lifecycle actions.

Acceptance points:

- Memory created by user emits an event.
- Memory created by LLM emits an event.
- Memory updated emits an event.
- Memory deleted emits an event.
- Event payloads include safe hierarchy and creator metadata.
- Event payloads do not include secrets, raw runtime state, or unrelated data.

---

## 10. Non-Functional Requirements

### NFR-1 — Scope safety

Scope validation is required for all create, list, update, delete, and Lemming store flows.

The system must prevent:

- Cross-World access.
- Sibling City access.
- Sibling Department access.
- Lemming-created memories escaping their current execution ancestry.

### NFR-2 — Observability

Memory lifecycle actions should be observable through lightweight structured events.

This PR does not require persistent audit events or durable audit-log rows. PubSub notifications, logs, telemetry-style signals, or existing non-durable runtime events are enough for MVP.

Events should be useful for operational diagnosis and UI notification without exposing sensitive content unnecessarily.

### NFR-3 — Privacy and data minimization

Memory content may contain user or business information. The system should avoid copying full memory content into logs/events unless explicitly needed for user-facing display.

At minimum:

- No secrets in events.
- No unrelated runtime state in events.
- No raw internal paths or artifact storage refs.

### NFR-4 — Simplicity for MVP

This PR must avoid building a generalized RAG system.

The design should stay compatible with future source/reference file categories, but this PR should not implement extraction, chunking, semantic indexing, or external vector services.

### NFR-5 — UI clarity

Users should be able to distinguish:

- Memory scope.
- Memory source: user or llm.
- Memory tags.
- Whether the memory is directly owned by the current scope or inherited.

### NFR-6 — Best-effort notification resilience

Chat notification is not part of the persistence transaction.

If memory storage succeeds and notification fails, the system should keep the stored memory and rely on events/logs for diagnosis.

### NFR-7 — Extensibility

The Knowledge item model should leave room for future Knowledge families:

- source files
- reference files

This includes reserving `artifact_id` for file-backed Knowledge while keeping it null for memories.

Ecto schema/context defaults and validations should keep the MVP narrow:

- `kind` or `category`, if present, is defaulted to `memory` by the schema/context layer.
- `status` is defaulted to `active` by the schema/context layer.
- `source` is validated as `user` or `llm` by changesets/context APIs.
- `tags` are stored as a lightweight list of strings.
- `artifact_id` stays nullable and must be null for memories through context validation.
- Creator fields should capture user or LLM provenance where available without requiring unavailable metadata.

---

## 11. User Stories

### US-1 — Create a memory manually

As an operator, I want to create a memory in the Knowledge surface, so that future Lemmings can reuse small durable knowledge without needing a file.

### US-2 — Edit a memory manually

As an operator, I want to update a memory’s title, content, and tags, so that stored knowledge remains accurate.

### US-3 — Delete a memory manually

As an operator, I want to delete an obsolete memory, so that future Lemmings do not use outdated information.

### US-4 — View effective memories for a scope

As an operator, I want to view memories relevant to a World, City, Department, or Lemming, so that I understand what knowledge is available in that context.

### US-5 — Store memory from a Lemming

As a Lemming, I want to store a useful small fact through `knowledge.store`, so that future executions of this Lemming can reuse it.

### US-6 — Be informed when a Lemming stores memory

As a user, I want to see when a Lemming adds a memory, so that I can review or remove knowledge that was created automatically.

---

## 12. Acceptance Criteria

### AC-1 — Knowledge item foundation supports memories

- **Given** the Knowledge Repository foundation exists
- **When** a memory is created
- **Then** it is persisted as a memory
- **And** it has required scope, title, content, source, status, and creator metadata
- **And** `artifact_id` is null
- **And** any internal kind/category is defaulted by the runtime

### AC-2 — User can create memory

- **Given** a user is on a Knowledge surface for an allowed scope
- **When** the user creates a memory with valid title, content, and optional tags
- **Then** the memory is stored
- **And** it appears in the relevant memory list
- **And** it has `source = user`
- **And** a create event is emitted

### AC-3 — User can edit memory

- **Given** a user can access an existing memory
- **When** the user edits title, content, or tags
- **Then** the updated memory is saved
- **And** the updated data appears in the UI
- **And** an update event is emitted

### AC-4 — User can hard delete memory

- **Given** a user can access an existing memory
- **When** the user deletes it
- **Then** the memory is removed from active storage/listing
- **And** a delete event is emitted
- **And** no archive / unarchive behavior is required

### AC-5 — Scope validation prevents boundary escape

- **Given** a memory belongs to one World, City, Department, or Lemming
- **When** another unrelated scope attempts to list, edit, delete, or create against it
- **Then** the system rejects or hides the action
- **And** cross-World access is never allowed
- **And** sibling City / Department access is not allowed by default

### AC-6 — Department effective list includes Lemming memories

- **Given** a Department has multiple Lemmings
- **And** those Lemmings have their own memories
- **When** the user views the Department Knowledge surface
- **Then** the user can see Department-relevant inherited memories
- **And** the user can see Lemming memories belonging to that Department
- **And** the UI distinguishes the owning scope where practical
- **And** the list can be searched by title/tags
- **And** the list is paginated with 25 memories per page by default

### AC-7 — Lemming can create memory through `knowledge.store`

- **Given** a Lemming is executing inside a valid World / City / Department / Lemming context
- **When** it calls `knowledge.store` with valid memory content
- **Then** a memory is stored with `source = llm`
- **And** creator Lemming / instance metadata is captured where available
- **And** the default scope is the current Lemming
- **And** a safe result is returned to the Lemming

### AC-8 — Invalid `knowledge.store` calls are rejected

- **Given** a Lemming calls `knowledge.store`
- **When** it requests file-based Knowledge, provides unsupported fields, missing content, invalid scope, or cross-boundary scope
- **Then** the call fails with a safe structured error
- **And** no memory is created

### AC-9 — User is informed when Lemming stores memory

- **Given** a Lemming successfully stores a memory
- **When** the execution chat is active
- **Then** the user receives a best-effort chat notification
- **And** the notification includes a button/link when supported, or a plain Knowledge path in the MVP chat message, to view/edit the created memory
- **And** notification failure does not roll back the memory

### AC-10 — Events are safe

- **Given** memory lifecycle events are emitted
- **When** event payloads are inspected
- **Then** they include safe hierarchy and creator metadata
- **And** they do not include secrets, unrelated raw runtime state, or unsafe file paths

---

## 13. Edge Cases

### Empty states

- No memories exist for current scope → show an empty Knowledge state with a create-memory action.
- No inherited memories exist → show only directly owned memories.
- Department has no Lemming memories → do not show an error.
- Search/filter returns no results → show a clear empty filtered state and allow clearing the filter.

### Validation errors

- Missing title → reject with clear validation message.
- Missing content → reject with clear validation message.
- Invalid scope → reject with clear validation message.
- Unsupported file-based Knowledge fields through `knowledge.store` → reject safely.

### Scope errors

- Lemming tries to create memory in another Department → reject.
- Lemming tries to create memory in another World → reject.
- User tries to edit sibling Department memory → reject or hide.
- User views Department Knowledge → include only memories in valid ancestry and its own Lemmings.

### Notification errors

- Memory stored but chat notification fails → keep memory, emit/keep event, do not fail tool call.
- Chat not mounted or unavailable → store memory and skip visible notification.

### Delete behavior

- User deletes memory while another user is viewing it → memory disappears or fails on next refresh/action.
- Lemming tries to use a deleted memory later → memory is unavailable.

---

## 14. Events / Observability Expectations

Recommended lightweight event names:

- `knowledge.memory.created`
- `knowledge.memory.updated`
- `knowledge.memory.deleted`
- `knowledge.memory.created_by_llm`

These event names are recommended for consistency across observability channels. For this MVP, implementation may emit them through PubSub, logs, telemetry-style signals, or existing non-durable runtime events. Persistent audit rows are not required.

Event payloads should include:

- `knowledge_item_id`
- internal `kind` / `category`, when present
- `source`
- owning scope metadata
- actor / creator metadata where available
- Lemming / instance metadata for LLM-created memories where available

Event payloads should avoid:

- secrets
- raw internal runtime state
- raw file paths
- unrelated message history
- full memory content unless explicitly required for a user-visible event

---

## 15. UX Notes

The Knowledge surface should make the memory model understandable without requiring users to know the storage implementation.

Recommended visible fields:

- Title
- Tags
- Scope / inherited-from indicator
- Source: user / llm
- Created / updated timestamp
- Creator where available

Recommended actions:

- Create memory
- Edit memory
- Delete memory
- Search title/tags with one text box
- Filter by source where practical
- Paginate memory lists, 25 per page by default, using local Ecto limit/offset/count queries

For this PR, one Knowledge surface is preferred over three separate family tabs. Future Knowledge families can be added inside the same surface as sections or sub-tabs.

---

## 16. Risks And Mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| LLM stores too many noisy memories | Knowledge quality degrades | Keep default scope narrow at the current Lemming and show chat notification so user can delete |
| Scope rules become confusing | Users may not know why a memory appears | Show owning scope / inherited-from indicator |
| Hard delete removes useful knowledge accidentally | User cannot recover deleted memory | Acceptable MVP tradeoff; archive can be added later |
| Event payload leaks too much content | Privacy/security risk | Keep events metadata-focused and avoid secrets/raw state |
| Knowledge model overfits memories | Future source/reference file work becomes harder | Keep an internal kind/category if needed, but expose a simple memory-first API now |
| Tool input becomes confusing for LLMs | Bad tool calls or low-quality metadata | Keep `knowledge.store` input limited to title, content, tags, and scope; document a suggested title format in the tool catalog |

---

## 17. Implementation Constraints

Implementation should preserve these product boundaries:

- Keep memories as the first Knowledge item supported by the shared Knowledge Repository model.
- Keep `knowledge.store` generic by name but memory-only in this PR.
- Do not require Lemmings to send `category` or `type`.
- Use tags as the lightweight organization mechanism for MVP.
- Add title-format guidance to the `knowledge.store` tool catalog entry so Lemmings produce searchable, mostly uniform titles.
- Use local Ecto pagination with stable ordering, `limit`, `offset`, and a count query; do not add a pagination dependency.
- Keep Lemming-created memory default scope as the current Lemming (`lemming_id`), which maps to the product concept currently called Lemming Type.
- Keep notification best-effort and non-transactional.
- Use hard delete for MVP.
- Avoid file and RAG concerns in this PR.
- Avoid building archive/status lifecycle beyond what is needed for active memories.
