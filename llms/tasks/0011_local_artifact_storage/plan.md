# Implement local Artifact storage backend

## Summary

Implement and harden the existing local filesystem storage path for Artifacts.

The repo already has the Artifact domain model, `LemmingsOs.Artifacts.LocalStorage`, promotion integration, durable artifact download routing, and focused tests. This task must harden that current implementation instead of creating a parallel storage system. The goal is a safe, adapter-shaped local backend for reading and writing Artifact bytes on disk, with a clean seam for future MinIO/S3-style backends.

This issue does not redefine Artifact lifecycle, promotion UI, download authorization, or broad Artifact metadata semantics. It may make the narrow Artifact schema/changeset adjustment required to persist safe storage error metadata.

## Current State

- `LemmingsOs.Artifacts.LocalStorage` already builds `local://artifacts/...` refs, resolves trusted refs under the configured root, copies files, and computes checksum/size.
- `LemmingsOs.Artifacts.Promotion` already promotes workspace files and supports explicit `:update_existing` and `:promote_as_new` behavior.
- `InstanceArtifactController.download/2` currently resolves storage refs and reads files directly for downloads after scope/status checks.
- Runtime config currently reads `LEMMINGS_ARTIFACT_STORAGE_PATH`; this issue standardizes on `LEMMINGS_ARTIFACT_STORAGE_ROOT`.
- `Artifact` metadata validation currently allows only empty metadata or `%{"source" => "manual_promotion"}`; it must be extended narrowly for safe storage error metadata.

## Decisions

- Canonical storage ref format is `local://artifacts/<world_id>/<artifact_id>/<safe_filename>`.
- Physical layout is `<artifact_storage_root>/<world_id>/<artifact_id>/<safe_filename>`.
- Keep `LemmingsOs.Artifacts.LocalStorage` as the local backend module unless a tiny adapter wrapper is cleaner; do not create a duplicate independent storage implementation.
- Add `LemmingsOs.Artifacts.Storage.Adapter` behavior and make the existing local backend implement or delegate behind that behavior.
- V1 adapter callbacks are `put/4`, `open/2`, `path_for/2`, `exists?/2`, and `health_check/1`; do not include `delete/2` because physical deletion is out of scope.
- `path_for/2` is trusted/internal only. Public Artifact APIs must not expose resolved filesystem paths.
- `open/2` returns an internal trusted path only after the caller has performed Artifact scope/status checks. Its contract is `{:ok, %{path: path, filename: filename, content_type: content_type, size_bytes: size_bytes}} | {:error, reason_token}`.
- `LEMMINGS_ARTIFACT_STORAGE_ROOT` is the primary runtime env var. `LEMMINGS_ARTIFACT_STORAGE_PATH` may be supported only as a deprecated fallback to avoid breaking existing local envs.
- Default `max_file_size_bytes` is `100 * 1024 * 1024`.
- Observability uses existing repo conventions: safe `Logger` metadata and `:telemetry.execute/3`; do not invent an undefined artifact event helper.
- Canonical telemetry event names are atom-list events under `[:lemmings_os, :artifact_storage, ...]`. String-style names are allowed only in Logger `:event` metadata or log messages.
- Durable Artifact storage audit persistence via `LemmingsOs.Events` is out of scope. Storage operations may emit safe Logger metadata and `:telemetry` events only.
- Accessibility review is out of scope unless implementation changes operator-facing UI or LiveView templates.

## Task Sequence

| # | Task | Agent | Status | Approved |
|---|------|-------|--------|----------|
| 01 | Storage Test Scenarios | `qa-test-scenarios` | ⏳ PENDING | [ ] |
| 02 | Adapter Config Contract | `dev-backend-elixir-engineer` | ⏳ PENDING | [ ] |
| 03 | Local Storage Hardening | `dev-backend-elixir-engineer` | ⏳ PENDING | [ ] |
| 04 | Artifact Context And Downloads | `dev-backend-elixir-engineer` | ⏳ PENDING | [ ] |
| 05 | Storage Observability | `dev-logging-daily-guardian` | ⏳ PENDING | [ ] |
| 06 | Storage Test Coverage | `qa-elixir-test-author` | ⏳ PENDING | [ ] |
| 07 | Feature Documentation | `docs-feature-documentation-author` | ⏳ PENDING | [ ] |
| 08 | Accessibility Scope Review | `audit-accessibility` | ⏳ PENDING | [ ] |
| 09 | Security Audit | `audit-security` | ⏳ PENDING | [ ] |
| 10 | Staff Elixir PR Audit | `audit-pr-elixir` | ⏳ PENDING | [ ] |
| 11 | Release Validation | `rm-release-manager` | ⏳ PENDING | [ ] |

Each task requires human approval before the next starts. Human reviewers own all git operations.

## Implementation Changes

### Storage Backend

- Add `LemmingsOs.Artifacts.Storage.Adapter` with explicit `{:ok, result} | {:error, reason}` callbacks for write/open/path/existence/health operations.
- Refactor `LemmingsOs.Artifacts.LocalStorage` to satisfy the behavior while preserving existing public helpers where tests or callers already use them.
- Replace direct `File.cp/2` destination writes with temp-file-in-same-directory plus atomic rename.
- Enforce `max_file_size_bytes` before or during copy so oversized source files do not produce ready Artifacts.
- Compute `size_bytes` and SHA-256 from the managed temp/final file and return them with the canonical storage ref.
- Apply best-effort permissions where supported: directories `0700`, files `0600`.
- Keep path safety behavior: reject path traversal, absolute paths, null bytes, control characters, separators inside filenames, symlink escape components, and empty filenames.
- When resolving any trusted storage path, resolve/expand the final path and verify it remains inside the configured storage root before opening it or returning it. This must protect against symlinks inside the root that point outside the root even when traversal checks pass.
- Add `exists?/2`, `open/2`, trusted `path_for/2`, and `health_check/1` on the backend. `open/2` must follow the locked return contract and return structured storage errors without exposing host paths in error values.

### Artifact Context And Downloads

- Add or update a trusted Artifact context function for download/open that performs scope/status checks first, then delegates file access to the storage backend and returns the `open/2` success shape to the controller.
- Update `InstanceArtifactController.download/2` to use the trusted context/backend open path instead of resolving the storage ref and calling `File.read/1` directly.
- Preserve explicit update behavior: `:update_existing` overwrites the managed file atomically and keeps the same Artifact row; `:promote_as_new` creates a new row.
- Failed first-time storage writes must not create misleading ready Artifacts.
- Failed updates before a safe replacement must leave the existing Artifact DB row and existing managed file metadata unchanged.
- Missing/unreadable/broken managed files for ready Artifacts should return a structured storage error, produce a safe 404 at the controller boundary, and mark the Artifact as `error` where the context has enough information to do so.
- A trusted read/open path may mark a ready Artifact as `error` when storage is missing or unreadable. This is an intentional repair/consistency side effect, not a general read mutation pattern.

### Metadata, Config, And Observability

- Extend `Artifact` metadata validation only enough to support safe storage error metadata while preserving the existing `source` contract.
- Allowed storage error keys are `storage_error_reason`, `storage_error_operation`, and `storage_error_at`; values must be safe strings and must not include absolute paths, storage roots, raw workspace paths, file contents, full exception dumps, notes, or secrets.
- Update runtime/config defaults to include `max_file_size_bytes: 100 * 1024 * 1024` and prefer `LEMMINGS_ARTIFACT_STORAGE_ROOT`.
- Emit safe Logger metadata and canonical telemetry events for storage write/update/open/health outcomes.
- Telemetry event names must use these shapes: `[:lemmings_os, :artifact_storage, :write, :start]`, `[:lemmings_os, :artifact_storage, :write, :stop]`, `[:lemmings_os, :artifact_storage, :write, :exception]`, `[:lemmings_os, :artifact_storage, :open, :stop]`, `[:lemmings_os, :artifact_storage, :open, :exception]`, `[:lemmings_os, :artifact_storage, :health_check, :stop]`, and `[:lemmings_os, :artifact_storage, :health_check, :exception]`.
- Artifact update/replacement uses the same storage write telemetry events; use metadata `operation: :update` when distinguishing replacement from first write is useful.
- String-style names such as `"artifact.storage.write.succeeded"` may be used only for Logger `:event` metadata or log messages, not as telemetry event names.
- Do not persist Artifact storage audit/telemetry rows through `LemmingsOs.Events` in this issue.
- Event/log metadata may include ids, filename, content type, size, checksum, operation, and reason token. It must not include absolute paths, root path, source workspace path, file contents, full metadata, notes, or secret values.

### Docs

- Document `LEMMINGS_ARTIFACT_STORAGE_ROOT`, local layout, Docker/self-host persistent volume requirements, and backup expectations.
- State clearly that Artifact metadata is in Postgres but Artifact bytes are in the configured storage root; operators must back up both.
- Document that DB-only backup is insufficient.
- Document that soft-deleted Artifacts are not physically purged in this issue.
- Document that S3/MinIO, physical cleanup, retention, encryption-at-rest beyond filesystem permissions, scanning, previews, RAG ingestion, cross-City shared storage, and versioning are future work.

## Test Plan

- Unit: canonical ref format, root-bounded path resolution, unsafe filename rejection, symlink escape rejection, storage ref excludes root path, and public descriptors exclude `storage_ref`.
- Unit: atomic write uses temp file plus rename, computes checksum/size, enforces 100 MB max by config default, applies permissions where reliable, cleans temp files after success, and returns structured errors for bad source or bad managed file.
- Unit: `exists?/2`, `open/2`, `path_for/2`, and `health_check/1` return explicit success/error tuples without path leakage.
- Schema/context: safe storage error metadata is accepted; unexpected metadata keys and unsafe storage error values are rejected.
- Integration: promotion first write persists `storage_ref`, checksum, and size; `:update_existing` recomputes metadata and keeps the same row; failed replacement does not corrupt existing valid metadata.
- Controller: durable artifact downloads still serve bytes with safe headers; wrong scope/status returns safe 404; missing/broken storage returns safe 404 without leaking path/ref/root and marks ready Artifact as `error` where applicable.
- Controller/context: tests cover the intentional read/open repair side effect that marks ready Artifacts as `error` for missing/unreadable storage.
- Observability: Logger/telemetry events are emitted for storage success/failure and exclude absolute paths, root path, raw workspace path, file contents, full metadata, notes, and secrets.
- Docs: docs mention `LEMMINGS_ARTIFACT_STORAGE_ROOT`, persistent volume, DB plus artifact volume backup, no cleanup/retention, and future S3/MinIO.
- Final validation: run the narrowest relevant tests first, then `mix format`, then `mix precommit`.

## Acceptance Criteria

- [ ] `LemmingsOs.Artifacts.Storage.Adapter` exists with no physical delete callback in v1.
- [ ] Existing `LemmingsOs.Artifacts.LocalStorage` implements or delegates behind the adapter without creating a duplicate local storage implementation.
- [ ] Storage root is configurable through app config and `LEMMINGS_ARTIFACT_STORAGE_ROOT`, with `LEMMINGS_ARTIFACT_STORAGE_PATH` only as an optional deprecated fallback.
- [ ] Canonical persisted refs use `local://artifacts/<world_id>/<artifact_id>/<safe_filename>` and never absolute filesystem paths.
- [ ] Storage path uses `<root>/<world_id>/<artifact_id>/<safe_filename>`.
- [ ] Writes and explicit updates use temp file plus atomic rename.
- [ ] Checksum and byte size are computed during write/update.
- [ ] Configurable max file size is enforced with a default of `100 * 1024 * 1024` bytes.
- [ ] Best-effort directory/file permissions are applied where supported.
- [ ] Unsafe filenames, path traversal, absolute paths, null bytes, control characters, separators, and symlink escapes are rejected.
- [ ] Trusted open/download path uses the storage backend instead of direct controller `File.read/1` against resolved refs.
- [ ] Missing/unreadable/broken files return structured errors and safe controller responses.
- [ ] Storage failures update Artifact status/metadata safely where applicable.
- [ ] Read/open status mutation is documented and limited to the intentional storage-missing/unreadable repair path.
- [ ] Safe storage error metadata is accepted by `Artifact` validation; unsafe metadata remains rejected.
- [ ] Soft-deleted Artifacts do not physically delete files.
- [ ] No cleanup/sweeper or object-storage backend is implemented.
- [ ] Logger/telemetry events are emitted with safe metadata only.
- [ ] No Artifact storage audit rows are persisted through `LemmingsOs.Events` in this issue.
- [ ] Logs/events/DB/public descriptors do not expose root paths, absolute paths, raw workspace paths, file contents, full metadata, notes, or secrets.
- [ ] No accessibility-impacting UI changes are introduced; if UI changes are made, they receive an accessibility review.
- [ ] Health check exists and is covered by tests.
- [ ] Docker/self-host docs explain volume mount and backup requirements.
- [ ] Final review covers docs, style/format, security/path leakage, and regression risk.
- [ ] Tests that mutate app env restore previous values in `on_exit`.
- [ ] Relevant targeted tests, `mix format`, and `mix precommit` pass.

## Risks And Guardrails

- Existing valid Artifacts can be corrupted if DB metadata is updated before replacement storage succeeds; always write and verify temp file, rename atomically, then update DB metadata.
- Filesystem paths reveal host layout; keep path resolution inside the backend and test logs/events/responses for forbidden fields.
- Soft-deleted Artifacts will grow disk usage; document this explicitly and leave retention/purge for a future task.
- Local storage is node-local or volume-local; do not imply cross-City shared storage.
- Permission assertions can be brittle across OS/container environments; keep permission tests focused and skip only where the platform makes them unreliable.
