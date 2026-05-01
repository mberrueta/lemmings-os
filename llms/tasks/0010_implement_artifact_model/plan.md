# Artifact Domain Model — Initial Implementation Plan

## Status

Initial implementation plan for GitHub issue #27.

## Goal

Implement the first Artifact domain model for LemmingsOS.

An Artifact is a manually promoted runtime output backed by a physical file and tracked with durable metadata, scope, provenance, lifecycle status, and a safe storage reference.

This work must establish the foundation for future workflows such as PDF generation, email attachments, approvals, and knowledge ingestion without implementing those workflows now.

---

## Product decisions locked

### File vs Artifact

```text
File = bytes in workspace/storage.
Artifact = promoted runtime output with scope, provenance, lifecycle, metadata, and storage reference.
```

Workspace files remain scratch files by default.

A file becomes an Artifact only when a human manually promotes it from the instance chat/timeline UI.

### Artifact creation

For this issue:

- manual human promotion only
- no automatic LLM/tool promotion
- no prompt rules for deciding what becomes an Artifact
- no direct tool-created Artifacts

### Artifact storage

- Artifact is always backed by a physical file.
- File bytes are never stored in the database.
- The database stores metadata and an opaque `storage_ref`.
- Promoted files are copied into app-managed local artifact storage.
- The original workspace file is not moved and is not tracked after promotion.

### Scope and provenance

Artifact ownership is scope-based.

Artifact provenance is optional.

- `world_id` required
- `city_id` nullable
- `department_id` nullable
- `lemming_id` nullable
- `lemming_instance_id` nullable
- `created_by_tool_execution_id` nullable

Artifacts must survive creator instance cleanup. Provenance references must nilify, not cascade-delete Artifacts.

### Lifecycle

Allowed statuses:

```elixir
~w(ready archived deleted error)
```

Promotion creates `ready` Artifacts.

Only `ready` Artifacts are normally visible/selectable/usable by future tools.

`archived`, `deleted`, and `error` are rejected by normal Artifact resolution APIs.

---

## Out of scope

Do not implement:

- automatic LLM/tool promotion
- prompt rules for Artifact creation
- MinIO/S3/external storage backends
- PDF generation
- email sending or email attachments
- approval workflow
- full Artifact browser/library
- cross-Department sharing
- public/share links
- Artifact versioning
- secret scanning
- RAG/knowledge ingestion
- user-uploaded documents/templates
- physical cleanup/retention/purge
- rich preview UI for every file type

---

## Proposed implementation phases

## Phase 1 — Data model and schema

### Goal

Introduce the durable Artifact record.

### Tasks

- Add migration for `artifacts` table.
- Add `LemmingsOs.Artifacts.Artifact` schema.
- Add schema validations for required fields.
- Add string validation for allowed `type` values.
- Add string validation for allowed `status` values.
- Add basic scope validation.
- Add nullable provenance associations.
- Add tests for schema validation and changesets.

### Suggested table

```text
artifacts
  id uuid primary key

  world_id uuid not null
  city_id uuid null
  department_id uuid null
  lemming_id uuid null
  lemming_instance_id uuid null
  created_by_tool_execution_id uuid null

  type varchar not null
  filename varchar not null
  content_type varchar not null
  storage_ref text not null
  size_bytes bigint not null
  checksum varchar not null
  status varchar not null
  notes text null
  metadata jsonb not null default '{}'

  inserted_at timestamp not null
  updated_at timestamp not null
```

### Required validations

- `world_id` required
- `filename` required
- `type` required
- `content_type` required
- `storage_ref` required
- `size_bytes` required
- `checksum` required
- `status` required
- `metadata` defaults to `%{}`
- `type` in `markdown | pdf | json | csv | email | html | image | text | other`
- `status` in `ready | archived | deleted | error`

### Notes

Do not use DB enums.

Use plain string fields and schema/context validation.

---

## Phase 2 — Local artifact storage

### Goal

Create a minimal local storage boundary for managed Artifact files.

### Tasks

- Add config for local Artifact storage root.
- Add local storage module.
- Implement copy into managed Artifact storage.
- Implement SHA-256 checksum calculation.
- Implement size calculation.
- Implement safe `storage_ref` generation.
- Implement internal storage ref resolution for trusted runtime/download code.
- Add tests for storage path generation, copying, checksum, and size.

### Config

Suggested default:

```elixir
config :lemmings_os, :artifact_storage,
  backend: :local,
  root_path: System.get_env("LEMMINGS_ARTIFACT_STORAGE_PATH", "storage/artifacts")
```

### Physical layout

```text
<artifact_storage_root>/<world_id>/<artifact_id>/<filename>
```

### DB storage ref

```text
local://artifacts/<world_id>/<artifact_id>/<filename>
```

### Constraints

Do not store:

- raw workspace path
- resolved filesystem path
- file bytes in DB
- storage root path in logs/events

---

## Phase 3 — Artifacts context API

### Goal

Expose a small context API for creating, promoting, listing, getting, and updating Artifact status.

### Tasks

- Add `LemmingsOs.Artifacts` context.
- Implement `create_artifact/2`.
- Implement `promote_workspace_file/2`.
- Implement `get_artifact/2`.
- Implement `list_artifacts_for_instance/2`.
- Implement `list_artifacts_for_scope/2`.
- Implement `update_artifact_status/3`.
- Add tests for scope enforcement.
- Add tests for promotion success and failure.
- Add tests for status filtering.

### Public functions

```elixir
create_artifact(scope, attrs)
promote_workspace_file(scope, attrs)
get_artifact(scope, artifact_id)
list_artifacts_for_instance(scope, lemming_instance_id)
list_artifacts_for_scope(scope)
update_artifact_status(scope, artifact_id, status)
```

### Scope rule

All public functions require explicit scope.

No global Artifact lookup.

### Promotion behavior

Promotion must:

1. receive a workspace file path from trusted UI/runtime context
2. copy the file into managed Artifact storage
3. compute `size_bytes`
4. compute SHA-256 `checksum`
5. create/update Artifact row
6. emit safe lifecycle events
7. return safe Artifact descriptor

### Update behavior

If an existing Artifact matches:

```text
world_id + city_id + department_id + lemming_id + filename
```

allow update.

Update means:

- overwrite managed Artifact file
- recompute checksum
- recompute size
- keep same Artifact row
- emit `artifact.updated`

No versioning.

---

## Phase 4 — Observability and events

### Goal

Artifact operations must produce safe audit/telemetry events without leaking content or paths.

### Tasks

- Add `LemmingsOs.Artifacts.Events` or equivalent event helper.
- Emit events from create/promote/update/status/delete/read/error paths.
- Ensure reason tokens are safe.
- Add tests that event payloads do not include raw file contents, workspace paths, storage refs, or resolved paths.

### Required event vocabulary

```text
artifact.created
artifact.promoted
artifact.updated
artifact.status_changed
artifact.deleted
artifact.read
artifact.promotion_failed
artifact.error
```

### Safe event fields

```elixir
%{
  artifact_id: artifact.id,
  world_id: artifact.world_id,
  city_id: artifact.city_id,
  department_id: artifact.department_id,
  lemming_id: artifact.lemming_id,
  lemming_instance_id: artifact.lemming_instance_id,
  created_by_tool_execution_id: artifact.created_by_tool_execution_id,
  filename: artifact.filename,
  type: artifact.type,
  content_type: artifact.content_type,
  status: artifact.status,
  size_bytes: artifact.size_bytes,
  checksum: artifact.checksum,
  reason_token: reason_token
}
```

### Forbidden event fields

- file contents
- `storage_ref`
- resolved filesystem path
- raw workspace path
- full metadata blindly
- notes by default
- secret values

---

## Phase 5 — Instance timeline/UI integration

### Goal

Allow operators to manually promote generated workspace files from the existing instance chat/timeline.

### Tasks

- Identify where current file events are rendered in the instance session/timeline.
- Add `Promote to Artifact` action to file events.
- Add handler that calls `LemmingsOs.Artifacts.promote_workspace_file/2`.
- Detect same scope + lemming + filename existing Artifact.
- Show `Update Artifact` and `Promote as New Artifact` when applicable.
- Show promoted Artifact reference in timeline.
- Display notes unobtrusively when present.
- Add LiveView tests for promotion button and artifact reference rendering.

### Timeline display

Show safe descriptor only:

```text
filename
type
status
size
created_at
creator instance, if known
tool execution, if known
```

Do not show:

- raw file contents
- raw filesystem path
- storage root path
- full metadata
- prompt/model/tool raw output

### Notes UI

`notes` should be visible but not intrusive.

Acceptable UI patterns:

- tooltip
- popover
- modal
- details expansion

Do not send notes to LLM context by default.

---

## Phase 6 — Artifact open/download route

### Goal

Provide minimal controlled open/download behavior from the instance UI.

### Tasks

- Add route for Artifact download/open.
- Resolve Artifact by explicit scope.
- Check Artifact belongs to current visible scope.
- Reject `archived`, `deleted`, and `error` by default.
- Resolve `storage_ref` internally to local file path.
- Stream/send file response.
- Emit `artifact.read` event/telemetry.
- Add tests for authorized download, missing file, wrong scope, and rejected status.

### Suggested route options

Option A:

```text
/artifacts/:id/download
```

Option B:

```text
/lemmings/instances/:instance_id/artifacts/:artifact_id/download
```

Prefer whichever aligns better with existing instance UI routes.

### Authorization rule

For this issue:

```text
User can open/download an Artifact if it belongs to the current visible scope.
```

No new permission model.

---

## Phase 7 — Documentation

### Goal

Document the Artifact behavior and update architecture references.

### Tasks

- Add `docs/features/artifacts.md`.
- Update `docs/adr/0008-lemming-persistence-model.md`.
- Optionally update `docs/adr/0005-tool-execution-model.md` only if needed.
- Update any operator/developer docs that mention workspace files or generated outputs.

### `docs/features/artifacts.md` should cover

- File vs Artifact
- Manual promotion rule
- Scope and provenance
- Local storage model
- Type/status model
- Timeline behavior
- Download/open behavior
- Security/privacy rules
- Observability events
- Out of scope and future work

### ADR update

`docs/adr/0008-lemming-persistence-model.md` should state:

```text
Artifacts are durable promoted runtime outputs.
Artifact metadata is stored in Postgres.
Artifact bytes are stored outside Postgres in managed file storage.
Artifact contents are not stored in Postgres, ETS, DETS, logs, or LLM context.
```

---

## Suggested implementation order

1. Migration + schema
2. Local storage module
3. Context API
4. Promotion/update logic
5. Events
6. Download route
7. Timeline UI integration
8. Docs
9. Final tests/precommit

Reason: UI should come after the context/storage contract is stable.

---

## Testing plan

### Unit/context tests

- Artifact changeset validates required fields.
- Artifact changeset rejects invalid `type`.
- Artifact changeset rejects invalid `status`.
- Promotion copies file into managed storage.
- Promotion computes SHA-256 checksum.
- Promotion computes size.
- Promotion does not store original workspace path.
- Promotion returns safe descriptor.
- Promotion failure emits safe failure event.
- Existing Artifact update recomputes checksum and size.
- `get_artifact/2` enforces scope.
- `list_artifacts_for_scope/1` excludes deleted/error/archived unless explicitly requested by context function.

### UI/LiveView tests

- File event renders `Promote to Artifact`.
- Clicking promote creates Artifact.
- Promoted Artifact appears in timeline.
- Existing same-scope filename shows update/new options.
- Artifact reference does not render raw file contents.
- Notes are not rendered as large inline content.

### Download tests

- Ready Artifact can be downloaded from visible scope.
- Wrong scope cannot download.
- Deleted Artifact cannot download.
- Archived Artifact cannot download.
- Error Artifact cannot download.
- Missing physical file marks/returns error safely.
- Download response does not expose resolved filesystem path.

### Observability tests

- Lifecycle events are emitted.
- Event payload includes safe metadata.
- Event payload excludes file contents.
- Event payload excludes storage ref/resolved paths.
- Event payload excludes notes/full metadata by default.

---

## Security checklist

- [ ] Artifact context does not access Secret Bank.
- [ ] Artifact promotion does not inspect file contents for secrets.
- [ ] Artifact file contents are never logged.
- [ ] Artifact file contents are never injected into LLM context automatically.
- [ ] Artifact events do not include `storage_ref` or resolved filesystem path.
- [ ] Artifact metadata is minimal and schema-validated.
- [ ] Artifact notes are not emitted in events by default.
- [ ] Download/open route checks visible scope before resolving file path.

---

## Acceptance criteria

- [ ] Artifact schema/table exists and supports scope, provenance, file metadata, status, notes, and metadata.
- [ ] Artifact bytes are stored in local artifact storage, not DB.
- [ ] Artifact storage root is configurable via app config/env var.
- [ ] Workspace file promotion copies file into managed storage.
- [ ] Promotion creates `ready` Artifact.
- [ ] Promotion computes `size_bytes` and SHA-256 `checksum`.
- [ ] Original workspace path is not persisted.
- [ ] Manual promotion action exists in instance timeline for file events.
- [ ] Same scope + lemming + filename can update existing Artifact.
- [ ] Promoted Artifact appears in timeline as safe reference.
- [ ] Artifact can be opened/downloaded through controlled route.
- [ ] Archived/deleted/error Artifacts are not normally selectable or downloadable.
- [ ] Context APIs require explicit scope.
- [ ] Events are emitted with safe payloads.
- [ ] Artifact module does not access Secret Bank.
- [ ] Artifact contents are not automatically added to LLM context.
- [ ] `docs/features/artifacts.md` is added.
- [ ] ADR 0008 is updated.
- [ ] Tests cover schema, storage, promotion, update, download, UI, and safe events.
- [ ] `mix format`, `mix test`, and `mix precommit` pass.

---

## Risks / watch points

### Filename-based update matching

Matching by scope + lemming + filename is simple, but filename collisions are possible.

Mitigation:

- show explicit UI choice: `Update Artifact` vs `Promote as New Artifact`
- never silently overwrite without user action

### Storage ref leakage

`storage_ref` and resolved filesystem paths should remain internal.

Mitigation:

- public APIs return safe descriptors only
- download route resolves path internally after scope check
- events/logs use `artifact_id`

### Scope ambiguity

Artifacts can exist at World/City/Department scope.

Mitigation:

- validate legal scope shapes
- require explicit scope in every public context function

### Error lifecycle

A physical file may be missing or unreadable after DB row exists.

Mitigation:

- mark Artifact `error` when detected
- emit `artifact.error`
- reject from normal tool-safe resolution

---

## Future work enabled

- `pdf.generate -> artifact_id`
- `email.create_draft -> accepts artifact_id attachments`
- `approval.request -> displays referenced artifacts`
- `knowledge.upload -> ingests artifact_id`
- Artifact browser/library
- Artifact versioning
- external storage backends
- cross-Department sharing
- user-uploaded documents/templates

