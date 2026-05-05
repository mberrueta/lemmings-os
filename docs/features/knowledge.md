# Knowledge Memories

## Purpose

Knowledge memories are durable notes that operators or Lemmings can reuse across
future work. They are intended for stable facts, preferences, rules, and small
operational reminders.

Examples:

- `ACME - email summary language`: Client ACME prefers short email summaries in Portuguese.
- `Proposal payment terms`: Always include payment terms in customer quotes.
- `Department tone`: Use premium, warm, concise language for this Department.

This MVP implements memories only. Source files, reference files, semantic search,
and archive workflows are not implemented yet.

## Who Uses It

- Operators use the Knowledge UI to create, edit, filter, and delete memories.
- Lemmings use the `knowledge.store` runtime tool to store memory notes during execution.
- Developers use `LemmingsOs.Knowledge` for scope-safe memory CRUD and listing.

## Scope Model

Memories are stored in the existing hierarchy:

```text
World -> City -> Department -> Lemming
```

A memory row always has a `world_id`. Lower-level IDs are present only when the
memory belongs to that level:

| Memory scope | Persisted IDs | Visible to |
|---|---|---|
| World | `world_id` | That World scope and descendants |
| City | `world_id`, `city_id` | That City and descendants |
| Department | `world_id`, `city_id`, `department_id` | That Department and descendants |
| Lemming | `world_id`, `city_id`, `department_id`, `lemming_id` | That Lemming; Department listings also show same-Department Lemming memories |

Important rules:

- Cross-World visibility is not allowed.
- Sibling City and sibling Department memories are excluded.
- Downward inheritance applies for effective visibility.
- A Lemming-scoped memory maps to the persisted `lemmings.id` / `lemming_id` field. Product copy may call this "Lemming Type", but there is no separate Lemming Type table in this implementation.
- The effective-memory context API for a Department includes World, City, Department, and same-Department Lemming memories.
- The concrete scoped listing API used by embedded UI tabs lists memories owned under the selected scope and its descendants; it does not add inherited parent memories in that mode.

## Operator UI

The primary surface is `/knowledge`.

The same Knowledge LiveView is also embedded in scoped tabs:

- City detail Knowledge tab
- Department detail Knowledge tab
- Lemming detail Knowledge tab

Current UI behavior:

- The global `/knowledge` page lists all active memories across scopes.
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

## `knowledge.store`

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

## Developer Notes

Primary modules:

- `LemmingsOs.Knowledge` owns memory CRUD, effective listing, exact-scope validation, and lifecycle events.
- `LemmingsOs.Knowledge.KnowledgeItem` defines the shared `knowledge_items` schema for memory rows.
- `LemmingsOs.Tools.Adapters.Knowledge` validates model-provided `knowledge.store` arguments and delegates persistence to `LemmingsOs.Knowledge`.
- `LemmingsOsWeb.KnowledgeLive` renders global and embedded memory management surfaces.

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

## Known MVP Limits

- Only memory notes are implemented.
- No source files or reference files.
- No file upload, Artifact promotion into Knowledge, Tika extraction, chunking, or pgvector.
- No semantic search, `knowledge.search`, or `knowledge.read` tool.
- No archive/unarchive or soft-delete lifecycle.
- No approval gate before LLM-created memories are stored.
- Search is simple title/tag filtering; memory content is not searched by the current list filters.
