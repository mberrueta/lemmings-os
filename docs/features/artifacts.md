# Artifacts

## Purpose

Artifacts are durable references to promoted runtime output files.

- `File`: bytes in a runtime workspace.
- `Artifact`: a promoted file with durable metadata, scope ownership, lifecycle status, and provenance.

A workspace file does not become an Artifact automatically.

## Implemented creation model

Current implementation supports manual promotion only.

- Promotion entry point: instance timeline UI for eligible `fs.write_text_file` tool executions.
- Backend API: `LemmingsOs.Artifacts.promote_workspace_file/2`.
- Automatic promotion by model/tool behavior: not implemented.

## Scope and provenance model

Artifact rows are persisted in the `artifacts` table with explicit world hierarchy scope.

Required durable scope/data fields:
- `world_id`
- `filename`
- `type`
- `content_type`
- `storage_ref`
- `size_bytes`
- `checksum`
- `status`
- `metadata`

Optional scope/provenance fields:
- `city_id`
- `department_id`
- `lemming_id`
- `lemming_instance_id`
- `created_by_tool_execution_id`
- `notes`

Allowed values:
- `type`: `markdown | pdf | json | csv | email | html | image | text | other`
- `status`: `ready | archived | deleted | error`

Provenance deletion behavior:
- deleting a creator instance nilifies `lemming_instance_id`
- deleting a creator tool execution nilifies `created_by_tool_execution_id`
- Artifact rows survive those deletes

## Storage model

Artifact bytes are stored in managed local filesystem storage.

- Config key: `:lemmings_os, :artifact_storage`
- Backend: `:local` only
- Runtime env override: `LEMMINGS_ARTIFACT_STORAGE_ROOT`
- Default root path: `priv/runtime/storage`
- Default max file size: `100 * 1024 * 1024` bytes
- Physical layout: `<artifact_storage_root>/<world_id>/<artifact_id>/<filename>`
- Durable reference format: `local://artifacts/<world_id>/<artifact_id>/<filename>`

Promotion copies the source workspace file into managed storage (source file is not moved).
The local backend writes through a temporary file in the target directory and
renames into place after the copy succeeds. Directory and file permissions are
best-effort private filesystem permissions where the host supports them.

Artifact metadata lives in Postgres. Artifact bytes do not. A row with
`storage_ref`, `checksum`, and `size_bytes` is only the database side of the
durable Artifact; the corresponding file under the configured storage root must
also be retained.

## Self-host and backup requirements

Container and self-host deployments must mount the artifact storage root on
persistent storage. If the configured root is inside an ephemeral container
filesystem, promoted Artifact bytes are lost on container replacement or host
restart even though their database rows remain.

Backups must include both:
- the Postgres database
- the artifact storage root or volume

A DB-only backup is insufficient because it restores Artifact metadata without
the file bytes. A filesystem-only backup is also insufficient because it lacks
scope, lifecycle, checksum, content type, and provenance metadata.

Soft-deleted Artifacts are lifecycle rows only. Setting status to `deleted` does
not physically purge the managed file in this implementation.

## Collision and update behavior

Same-scope filename collisions are explicit.

- No existing same-scope filename: create a new `ready` Artifact row.
- Existing same-scope filename + no mode: returns `:mode_required`.
- `mode: :update_existing`: overwrite managed file and keep same Artifact row id.
- `mode: :promote_as_new`: create a second Artifact row for the same filename.

UI behavior mirrors this:
- `Promote to Artifact` shown when no promoted match exists.
- `Update Artifact` + `Promote as New Artifact` shown when a same-filename Artifact exists and workspace file fingerprint changed.

## Timeline rendering behavior

Instance timeline renders promoted Artifact references with safe summary fields.

Rendered summary fields:
- `filename`
- `status`
- `type`
- `size_bytes` label
- created timestamp label

Notes rendering:
- notes are shown behind a `<details>` disclosure
- notes are not included in the compact summary line

The rendered reference intentionally omits `storage_ref`, managed path, and raw file content.

## Download and open behavior

Two routes exist:

1. Durable Artifact download route:
- `GET /lemmings/instances/:instance_id/artifacts/:artifact_id/download`
- world + instance + artifact scope is validated before storage open
- only `ready` Artifacts are downloadable by default
- response includes safe headers:
  - `x-content-type-options: nosniff`
  - `content-disposition: attachment; filename="..."`
- missing or broken managed storage returns a safe `404` and marks the ready
  Artifact as `error` with safe storage-error metadata

2. Workspace compatibility route (legacy path-based open/download):
- `GET /lemmings/instances/:instance_id/artifacts/*path`
- serves workspace file bytes when path resolves safely inside workspace

Failure behavior on both routes is a safe `404` without leaking storage refs or filesystem paths.

## Security and privacy boundaries

Artifact file contents are not persisted in:
- Postgres rows
- ETS runtime state
- DETS snapshots
- logs
- LLM context (automatic injection)

Additional safeguards:
- public Artifact descriptors omit `storage_ref` and filesystem paths
- storage ref parsing/resolution rejects traversal and symlink escape patterns
- malformed or out-of-scope download attempts return safe not-found responses

## Observability scope

In this implementation slice:

- Artifact lifecycle operations do not write durable audit/event rows to `events`
- Artifact code does not rely on `LemmingsOs.Events` for lifecycle audit semantics
- observability is limited to lightweight non-durable Logger metadata and
  `:telemetry` events under `[:lemmings_os, :artifact_storage, ...]`

## Out of scope

Not implemented:
- S3/MinIO/external Artifact storage backends
- automatic model/tool promotion
- Artifact version graph/workflows
- durable Artifact read/download audit taxonomy
- Artifact content ingestion/RAG workflows
- physical cleanup/retention of soft-deleted files
- encryption at rest beyond host filesystem permissions
- content scanning or malware scanning
- previews/thumbnails
- cross-City shared Artifact storage

## Future work

Platform audit/event design should separately define:
- durable vs transient event boundaries
- actor attribution and immutability requirements
- read/download audit policy
- retention/filter/export behavior
