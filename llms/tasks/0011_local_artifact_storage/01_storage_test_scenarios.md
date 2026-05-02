# Task 01: Storage Test Scenarios

## Status
- **Status**: COMPLETE
- **Approved**: [X] Human sign-off

## Assigned Agent
`qa-test-scenarios` - Test scenario designer for acceptance criteria, edge cases, regressions, and coverage planning.

## Agent Invocation
Act as `qa-test-scenarios`. Define the complete scenario matrix for the local Artifact storage backend before implementation starts.

## Objective
Convert the feature plan into a concrete, ordered test and acceptance scenario matrix covering storage, context integration, download behavior, observability, docs, security, accessibility scope, and release validation.

## Inputs Required
- [x] `llms/constitution.md`
- [x] `llms/project_context.md`
- [x] `llms/coding_styles/elixir.md`
- [x] `llms/coding_styles/elixir_tests.md`
- [x] `llms/tasks/0011_local_artifact_storage/plan.md`
- [x] Existing tests under `test/lemmings_os/artifacts*` and `test/lemmings_os_web/controllers/instance_artifact_controller_test.exs`

## Expected Outputs
- [x] Scenario matrix documented in this task file.
- [x] Clear P0/P1/P2 coverage recommendations by subsystem.
- [x] Explicit negative/security cases: traversal, symlink escape, path leakage, oversized files, missing managed files, unsafe metadata.
- [x] Explicit no-persistent-audit expectation for `LemmingsOs.Events`.

## Acceptance Criteria
- [x] Scenarios cover every acceptance criterion in `plan.md`.
- [x] Scenarios are grouped by storage backend, Artifact context, controller/download, observability, docs, security, accessibility scope, and release validation.
- [x] Each scenario has a clear expected outcome and suggested test layer.
- [x] No implementation code is changed in this task.

## Technical Notes
### Relevant Code Locations
```text
lib/lemmings_os/artifacts/local_storage.ex
lib/lemmings_os/artifacts/promotion.ex
lib/lemmings_os/artifacts.ex
lib/lemmings_os_web/controllers/instance_artifact_controller.ex
test/lemmings_os/artifacts/local_storage_test.exs
test/lemmings_os/artifacts/promotion_test.exs
test/lemmings_os_web/controllers/instance_artifact_controller_test.exs
```

### Constraints
- Do not write implementation tests in this task.
- Do not perform git operations.
- Treat durable audit persistence through `LemmingsOs.Events` as out of scope.

## Execution Instructions
1. Read all inputs.
2. Build a scenario table with ID, priority, layer, setup, action, expected result, and later task owner.
3. Highlight coverage gaps that Task 06 must convert into ExUnit tests.
4. Document assumptions and any ambiguous behavior for human review.

---

## Scope & Assumptions

This plan covers the local filesystem Artifact storage hardening described in `plan.md`. It defines what Tasks 02 through 11 must validate; it does not implement tests or production code.

Assumptions:
- V1 supports only the local backend. S3/MinIO, deletion, retention, scanning, previews, RAG ingestion, versioning, and cross-City shared storage remain future work.
- `path_for/2` and `open/2` may return internal trusted filesystem paths only after caller-side scope/status checks.
- Public read models, controller responses, Logger metadata, telemetry metadata, and persisted safe error metadata must not expose storage roots, absolute paths, raw workspace paths, file contents, notes, full metadata, exception dumps, or secrets.
- A ready Artifact may be marked `error` as a limited repair side effect when trusted open/download discovers missing, unreadable, or broken managed storage.
- Durable storage audit rows through `LemmingsOs.Events` are explicitly out of scope; this feature uses Logger and telemetry only.
- Any tests that mutate application env must restore prior values with `on_exit`.

## Risk Areas

- **Filesystem escape**: traversal, absolute path input, unsafe filename bytes, Windows-style separators, and symlink components could read/write outside the configured root.
- **Path leakage**: errors, descriptors, responses, logs, telemetry, and metadata could reveal host paths or workspace paths.
- **Artifact corruption**: failed updates could update DB metadata before a safe replacement exists.
- **Oversized files**: storage writes could copy beyond the configured maximum and leave ready-looking artifacts or temp files.
- **Broken durable downloads**: controller code could bypass context/storage checks and call `File.read/1` directly.
- **Observability drift**: telemetry names or metadata could differ from the plan, or persistent audit events could be introduced accidentally.
- **Operational mismatch**: docs could imply DB-only backup is enough or omit persistent volume requirements.

## Scenario Matrix

| ID | Priority | Layer | Area | Scenario | Preconditions | Steps | Expected Result | Owner / Notes |
|---|---|---|---|---|---|---|---|---|
| STOR-001 | P0 | Unit | Storage | Adapter behavior contract exists with V1 callbacks only | Task 02 implementation present | Inspect/compile `LemmingsOs.Artifacts.Storage.Adapter` and `LocalStorage` implementation | Callbacks are `put/4`, `open/2`, `path_for/2`, `exists?/2`, `health_check/1`; no delete callback | Task 02 / Task 06 |
| STOR-002 | P0 | Unit | Config | Storage root config uses `LEMMINGS_ARTIFACT_STORAGE_ROOT` | Runtime config test can set env safely | Set root env and evaluate config | Root env wins over app config | Task 02 / restore env in `on_exit` |
| STOR-003 | P1 | Unit | Config | Default max file size is 100 MB | No explicit max configured | Read configured storage options | `max_file_size_bytes == 100 * 1024 * 1024` | Task 02 |
| STOR-004 | P0 | Unit | Storage | Canonical storage ref format | Valid UUIDs and safe filename | Build/store artifact ref | Ref is `local://artifacts/<world_id>/<artifact_id>/<safe_filename>` and excludes root/workspace paths | Existing coverage to keep |
| STOR-005 | P0 | Unit | Security | Unsafe filenames are rejected | Valid UUIDs | Try empty, `.`, `..`, traversal, absolute, nested path, backslash, drive prefix, null byte, control char, leading tilde | Returns safe reason token such as `:invalid_filename`; no file is written | Expand existing coverage |
| STOR-006 | P0 | Unit | Security | Malformed storage refs are rejected | Configured root | Try missing segment, wrong scheme/host, query/fragment, traversal, nested filename, null byte, bad UUID | Returns `{:error, :invalid_storage_ref}` and does not expose paths | Expand existing coverage |
| STOR-007 | P0 | Unit | Security | Resolved trusted path remains inside root | Configured root and valid ref | Resolve/path_for valid ref | Result path is under expanded root and physical layout is `<root>/<world_id>/<artifact_id>/<filename>` | Existing coverage to keep |
| STOR-008 | P0 | Unit | Security | Symlink escape in world/artifact/file path is rejected | Root contains symlink component pointing outside root | Call `store_copy/put`, `path_for`, and `open` for matching ref | Returns structured error; no outside write/read occurs | Must cover read and write, not only write |
| STOR-009 | P0 | Unit | Storage | Atomic first write | Valid source file and empty destination | Store file | Writes temp file in target dir, renames atomically, final file exists, no temp files remain | Task 03 / implementation-aware assertion |
| STOR-010 | P0 | Unit | Storage | Failed write does not leave ready-looking final file | Source read or copy fails before rename | Attempt store | Returns structured error; final managed file does not exist; temp file cleaned when possible | Task 03 |
| STOR-011 | P0 | Unit | Storage | Oversized file is rejected by configured max | Max set below source size | Store file | Returns `:file_too_large` or equivalent safe token; no final file; no ready Artifact metadata should be created by integration flow | Task 03 + Task 04 |
| STOR-012 | P0 | Unit | Storage | Checksum and size are computed from managed file | Valid source file | Store file, then inspect returned data and managed bytes | `size_bytes` and SHA-256 match final managed content, not untrusted metadata | Existing coverage to keep |
| STOR-013 | P1 | Unit | Storage | Best-effort permissions are applied | Platform supports POSIX mode inspection | Store file | Directories are `0700` and files `0600` where supported; test is tolerant/skipped when unsupported | Task 03 |
| STOR-014 | P0 | Unit | Storage | `open/2` returns locked success shape | Ready file exists in managed storage | Call backend `open/2` after valid ref | Returns `{:ok, %{path:, filename:, content_type:, size_bytes:}}`; path is internal and root-bounded | Task 03 |
| STOR-015 | P0 | Unit | Storage | `open/2` returns safe errors for missing/unreadable files | Valid ref but missing or unreadable final file | Call `open/2` | Returns `{:error, reason_token}` only; no paths or exception dumps in reason | Task 03 |
| STOR-016 | P1 | Unit | Storage | `exists?/2` is explicit and root-safe | Valid, missing, malformed, and symlink-escape refs | Call `exists?/2` | Returns boolean or explicit tuple per contract; malformed/escaping refs are not treated as existing | Task 03 |
| STOR-017 | P1 | Unit | Storage | `path_for/2` is trusted/internal only and root-safe | Valid and unsafe refs | Call `path_for/2` | Valid returns internal root-bounded path; unsafe returns safe error token | Task 03 |
| STOR-018 | P1 | Unit | Observability | `health_check/1` validates create/write/remove behavior | Temporary storage root config | Call health check for writable root, unwritable/missing bad root, and symlink escape root | Returns explicit success/error tuples and emits safe telemetry in observability task | Task 03 + Task 05 |
| CTX-001 | P0 | Integration | Artifact Context | First promotion persists ready Artifact after successful storage write | Workspace file exists | Promote file through context | Artifact row is ready with storage_ref, checksum, size; descriptor omits `storage_ref` and paths | Existing coverage to keep |
| CTX-002 | P0 | Integration | Artifact Context | Failed first-time storage write creates no misleading ready Artifact | Storage returns error, bad source, unsafe filename, or oversized source | Promote file | Returns safe error; no ready Artifact row is inserted | Task 04 / Task 06 |
| CTX-003 | P0 | Integration | Artifact Context | `:update_existing` writes safely before DB metadata update | Existing ready Artifact with valid managed file | Update with new source | Same row id; checksum/size and managed file reflect new content after successful replacement | Existing coverage to keep |
| CTX-004 | P0 | Integration | Artifact Context | Failed update preserves prior row and file | Existing ready Artifact; replacement storage fails before safe rename | Promote with `mode: :update_existing` | Returns safe error; old managed file, checksum, size, and status remain unchanged | Existing partial coverage for `:mode_required`; add storage failure |
| CTX-005 | P1 | Integration | Artifact Context | `:promote_as_new` creates independent row | Existing same-scope filename | Promote with `mode: :promote_as_new` | New row id; existing row unchanged; both list in scope as expected | Existing coverage to keep |
| CTX-006 | P0 | Integration | Validation | Safe storage error metadata is accepted | Artifact changeset attrs include allowed storage error keys | Validate/insert metadata with `storage_error_reason`, `storage_error_operation`, `storage_error_at` | Changeset valid when values are safe strings and optional `source` contract is preserved | Task 04 / Task 06 |
| CTX-007 | P0 | Integration | Validation | Unsafe storage error metadata is rejected | Metadata contains unexpected keys or unsafe values | Validate metadata with absolute path, root path, workspace path, file content, notes, exception dump, secret-like value, non-string value | Changeset invalid with safe validation errors | Task 04 / Task 06 |
| CTX-008 | P0 | Integration | Security | Public descriptors never expose storage internals | Artifact persisted with storage ref and metadata | Call create/get/list/list_for_instance descriptors | Descriptor omits `storage_ref`, absolute paths, root path, and raw workspace path | Existing coverage to keep and expand |
| CTX-009 | P0 | Integration | Artifact Context | Trusted download/open API enforces scope and status before storage open | Ready, archived, deleted, error, wrong-world, wrong-instance artifacts | Call context download/open function | Ready in scope opens; wrong scope/status returns `:not_found` without resolving storage | Task 04 |
| CTX-010 | P0 | Integration | Artifact Context | Missing/unreadable ready storage marks Artifact error when context can repair | Ready Artifact row points to missing or unreadable managed file | Call trusted context open/download | Returns storage error/not found; persisted Artifact becomes `error` with safe metadata | Task 04 |
| CTX-011 | P1 | Integration | Lifecycle | Soft-deleted Artifacts do not physically delete files | Ready Artifact with managed file | Mark status `deleted` | DB status changes; managed file remains on disk | Task 04 / confirms no delete callback |
| DL-001 | P0 | Controller | Downloads | Durable artifact download serves bytes with safe headers | Ready Artifact in scope with managed bytes | GET durable download route | 200, body bytes match, `content-type`, `x-content-type-options: nosniff`, safe attachment filename | Existing coverage to keep |
| DL-002 | P0 | Controller | Downloads | Wrong world/instance/status returns safe 404 before storage resolution | Artifact with invalid storage ref but wrong scope/status | GET route with wrong world, wrong instance, archived/deleted/error | 404 `Artifact not found`; no storage path/ref/root leak | Existing coverage to keep |
| DL-003 | P0 | Controller | Downloads | Missing managed file returns safe 404 and repairs status where applicable | Ready Artifact; physical file removed | GET durable download route | 404 without path/ref/root leakage; Artifact is marked `error` if context owns repair | Existing coverage lacks repair assertion |
| DL-004 | P0 | Controller | Downloads | Invalid storage ref returns safe 404 | Ready Artifact has unsupported/malformed storage ref | GET durable download route | 404 without leaking ref or root; optional status repair metadata is safe | Existing coverage to keep and expand |
| DL-005 | P0 | Controller | Security | Header filename sanitization prevents response splitting | Artifact filename contains CR/LF/control chars in DB | GET route | `content-disposition` strips controls and remains a single safe header | Existing coverage to keep |
| DL-006 | P1 | Controller | Compatibility | Workspace catch-all route remains compatible | Runtime workspace file exists | GET existing workspace artifact route | Still serves workspace bytes with safe headers; durable storage changes do not regress route | Existing coverage to keep |
| OBS-001 | P0 | Integration | Observability | Storage write emits canonical telemetry start/stop/exception | Telemetry test handler attached | Successful and failing write/update | Events use `[:lemmings_os, :artifact_storage, :write, ...]`; metadata includes allowed IDs/filename/content type/size/checksum/operation/reason | Task 05 / Task 06 |
| OBS-002 | P0 | Integration | Observability | Storage open emits canonical telemetry stop/exception | Telemetry test handler attached | Successful and failing open/download | Events use `[:lemmings_os, :artifact_storage, :open, ...]`; metadata excludes forbidden fields | Task 05 / Task 06 |
| OBS-003 | P1 | Integration | Observability | Health check emits canonical telemetry | Telemetry test handler attached | Run successful and failing health checks | Events use `[:lemmings_os, :artifact_storage, :health_check, ...]`; metadata is safe | Task 05 / Task 06 |
| OBS-004 | P0 | Integration | Observability | Logger metadata is useful and non-leaky | Capture logs around write/open/health failures | Trigger success and failure paths | Logs may include safe event string and IDs/reason; logs exclude paths, root, workspace source, contents, metadata, notes, secrets, exception dumps | Task 05 / Task 06 |
| OBS-005 | P0 | Integration | Audit | No durable audit rows are persisted through `LemmingsOs.Events` | Event count or test double available | Run write/open/download failures and successes | No Artifact storage audit/event rows are inserted; only Logger/telemetry are used | Task 05 / Task 06 |
| DOC-001 | P1 | Manual | Docs | Env var and local layout are documented | Docs updated in Task 07 | Review docs | `LEMMINGS_ARTIFACT_STORAGE_ROOT`, layout, default max size, and local-only behavior are documented | Task 07 |
| DOC-002 | P0 | Manual | Docs | Backup and volume requirements are explicit | Docs updated in Task 07 | Review self-host/Docker docs | Operators are told to back up Postgres plus artifact storage volume; DB-only backup is insufficient | Task 07 |
| DOC-003 | P1 | Manual | Docs | Non-goals are documented | Docs updated in Task 07 | Review feature docs | Soft delete does not purge bytes; cleanup/retention/S3/MinIO/encryption beyond FS permissions/scanning/previews/RAG/versioning are future work | Task 07 |
| A11Y-001 | P1 | Manual | Accessibility | No accessibility-impacting UI changes are introduced | Implementation complete | Diff templates/components/controllers | If no operator-facing UI changed, document no review needed; if UI changed, run accessibility audit on changed surfaces | Task 08 |
| SEC-001 | P0 | Manual | Security | End-to-end leak review | Implementation complete | Review tests, controller responses, logs, telemetry, metadata, descriptors | Forbidden path/content/secret surfaces are covered by assertions or manual audit notes | Task 09 |
| REL-001 | P0 | Manual | Release | Narrow tests and final validation pass | Implementation and tests complete | Run targeted storage/context/controller/observability tests, `mix format`, then `mix precommit` | All pass with zero warnings/errors; env-mutating tests restore config | Task 11 |

## Acceptance Criteria

- Given a valid world id, artifact id, safe filename, and configured storage root, when a file is stored, then the persisted ref is canonical, the physical path is root-bounded, size/checksum are computed from managed bytes, permissions are applied best-effort, and no temp files remain.
- Given unsafe filename or storage ref input, when any storage API receives it, then the operation returns a safe reason token and does not write, read, or leak any filesystem path.
- Given a symlink inside the storage root that points outside the root, when storing, resolving, pathing, opening, or checking existence, then the backend rejects the operation before accessing the external target.
- Given a source file over `max_file_size_bytes`, when promotion/storage is attempted, then no ready Artifact is created or updated and no final managed file remains.
- Given an existing ready Artifact, when `:update_existing` succeeds, then the same DB row is retained and its checksum/size match the new managed bytes.
- Given an existing ready Artifact, when `:update_existing` storage replacement fails, then the old DB metadata and old managed file remain valid.
- Given a ready Artifact whose managed file is missing or unreadable, when the trusted context/controller open path is used, then the user receives safe 404 behavior and the Artifact is marked `error` with safe metadata where the context has enough information.
- Given wrong World scope, wrong instance, or non-ready status, when download/open is requested, then storage is not resolved and the caller receives `:not_found` or a safe 404.
- Given Logger or telemetry observations for storage operations, when payloads are inspected, then event names follow the plan and metadata includes only safe IDs/tokens, never roots, absolute paths, raw workspace paths, contents, notes, full metadata, secrets, or exception dumps.
- Given storage operations succeed or fail, when durable event tables are inspected, then no storage audit rows are persisted through `LemmingsOs.Events`.
- Given soft-deleted Artifacts, when status changes to `deleted`, then the managed file remains on disk and no physical delete code path exists in the adapter.
- Given final documentation, when an operator reads backup guidance, then it is clear that Artifact metadata is in Postgres and bytes are in the configured storage root, and both must be backed up.

## Coverage Recommendations

- **P0 for Task 06**: STOR-004 through STOR-012, STOR-014, STOR-015, CTX-001 through CTX-004, CTX-006 through CTX-010, DL-001 through DL-005, OBS-001, OBS-002, OBS-004, OBS-005, SEC-001, REL-001.
- **P1 for Task 06**: STOR-002, STOR-003, STOR-013, STOR-016 through STOR-018, CTX-005, CTX-011, DL-006, OBS-003, DOC-001 through DOC-003, A11Y-001.
- **P2**: Cosmetic or platform-specific permission details beyond best-effort mode checks; broad browser accessibility testing only if UI surfaces change.

Task 06 should prioritize ExUnit coverage in this order:
1. `test/lemmings_os/artifacts/local_storage_test.exs` for path safety, atomic write, size limit, adapter functions, health check, and tuple errors.
2. `test/lemmings_os/artifacts/artifact_test.exs` and `test/lemmings_os/artifacts_test.exs` for safe metadata, descriptor leakage, and scope/status behavior.
3. `test/lemmings_os/artifacts/promotion_test.exs` for failed first writes and failed replacement preservation.
4. `test/lemmings_os_web/controllers/instance_artifact_controller_test.exs` for trusted context open, safe 404s, repair side effect, and header safety.
5. Focused observability tests for telemetry/log metadata and no `LemmingsOs.Events` persistence.

## Regression Checklist

- [ ] Canonical refs remain `local://artifacts/<world_id>/<artifact_id>/<safe_filename>`.
- [ ] `storage_ref` and filesystem paths remain internal-only.
- [ ] Unsafe names/refs/traversal/null/control chars/backslashes/drive prefixes are rejected.
- [ ] Symlink escape is rejected on both write and read/open paths.
- [ ] Writes and updates are atomic and clean temp files.
- [ ] Oversized files do not create or corrupt ready Artifacts.
- [ ] Missing/unreadable managed files produce safe errors and safe controller 404s.
- [ ] Ready Artifact repair to `error` happens only for intentional storage-missing/unreadable paths.
- [ ] Soft delete does not physically delete bytes.
- [ ] Logger and telemetry metadata are safe and use canonical event names.
- [ ] No `LemmingsOs.Events` durable audit rows are added for storage operations.
- [ ] Docs cover env var, volume, backup, DB-plus-bytes split, no cleanup/retention, and future object storage.
- [ ] Any tests that mutate app env restore it in `on_exit`.
- [ ] Targeted tests, `mix format`, and `mix precommit` pass.

## Out-of-scope

- Writing ExUnit implementation in this task.
- New object-storage backend, MinIO/S3 integration, cross-City shared storage, cleanup sweeper, retention policy, physical purge, file versioning, previews, scanning, RAG ingestion, or encryption-at-rest beyond filesystem permissions.
- New operator-facing UI unless later implementation tasks choose to change templates.
- Persistent Artifact storage audit rows through `LemmingsOs.Events`.
- Git operations.

## Ambiguities For Human Review

- Confirm whether `exists?/2` should return bare booleans or `{:ok, boolean} | {:error, reason}`; tests should match the Task 02 behavior contract once implemented.
- Confirm the exact safe reason tokens for oversized file, unreadable file, and missing file. Scenarios require tokenized errors but do not require specific atom names unless Task 02/03 define them.
- `LEMMINGS_ARTIFACT_STORAGE_ROOT` is the only runtime env var for Artifact storage root in this MVP.

## Execution Summary
- Completed the local Artifact storage scenario plan directly in this task file.
- Covered storage backend, adapter/config contract, Artifact context integration, durable download behavior, observability, docs, security, accessibility scope, and release validation.
- Included explicit negative/security cases for traversal, symlink escape, path leakage, oversized files, missing managed files, unsafe metadata, and forbidden durable audit persistence through `LemmingsOs.Events`.
- Mapped follow-on coverage to Task 06 target test files and implementation tasks.

## Human Review
*[Filled by human reviewer]*
