# Artifact Model Test Scenario Matrix

## Scope & Assumptions
- Scope: Task 0010 Artifact model implementation (Tasks 01-10), with explicit focus on acceptance coverage requested by Task 06.
- Source documents read: `llms/constitution.md`, `llms/coding_styles/elixir_tests.md`, `llms/tasks/0010_implement_artifact_model/plan.md`, and Task 01-05 outputs.
- Test style assumptions:
  - Use factory-driven deterministic setup (`insert/2`, `build/2`).
  - No external network calls in tests.
  - Use stable selectors/IDs for LiveView assertions.
  - Scope arguments are explicit (`world`/scope struct), no implicit global lookups.
- This document defines what to test; it does not implement tests.

## Risk Areas
- Scope escape: wrong-world or wrong-instance artifact access.
- File/path safety: traversal, symlink escape, invalid local storage refs.
- Lifecycle safety: non-ready artifacts accidentally selectable/downloadable.
- Data leakage: workspace paths, storage refs, notes, raw metadata, content leaking via descriptors/logs/errors/UI.
- Update semantics: accidental overwrite without explicit update mode.
- Reliability: missing physical file after DB row exists; safe degradation.
- Non-goals drift: durable Artifact lifecycle events or Secret Bank usage introduced by mistake.

## Scenario ID Groups
- `SCH-*`: schema and changeset validations.
- `STO-*`: local storage boundary.
- `CTX-*`: Artifacts context API and scope filtering.
- `PRO-*`: promotion/update flows.
- `OBS-*`: observability and safety guarantees.
- `DL-*`: download/open controller route behavior.
- `UI-*`: instance timeline promotion and rendering behavior.
- `SEC-*`: security, leakage, and forbidden integrations.
- `REL-*`: release and end-to-end validation commands.

## Scenario Matrix
| ID | Priority | Layer | Area | Scenario | Preconditions | Steps | Expected Result | Notes |
|---|---|---|---|---|---|---|---|---|
| SCH-01 | P0 | Unit | Validation | Required Artifact fields enforced | Valid world IDs/factory attrs | Remove one required field per case and validate changeset | Changeset invalid with localized error | `world_id`, `filename`, `type`, `content_type`, `storage_ref`, `size_bytes`, `checksum`, `status`, `metadata` |
| SCH-02 | P0 | Unit | Validation | Allowed `type` whitelist | Baseline valid attrs | Iterate invalid and valid types | Invalid rejected, allowed types accepted | `markdown,pdf,json,csv,email,html,image,text,other` |
| SCH-03 | P0 | Unit | Validation | Allowed `status` whitelist | Baseline valid attrs | Iterate invalid and valid statuses | Invalid rejected, allowed statuses accepted | `ready,archived,deleted,error` |
| SCH-04 | P1 | Unit | Validation | Metadata default and contract validation | Baseline attrs | Omit metadata; then add disallowed keys | Omitted defaults to `%{}`; disallowed payload rejected | Protect against prompt/output/secret dumps |
| SCH-05 | P0 | Integration | DB/Schema | Provenance nullify behavior on delete | Artifact references instance/tool execution | Delete referenced provenance rows | Artifact remains; provenance FK fields nilified | Ensures Artifacts survive instance cleanup |
| STO-01 | P0 | Unit | Filesystem Safety | Storage ref builder output format | world_id + artifact_id + filename | Build storage ref | Exact `local://artifacts/<world>/<artifact>/<filename>` format | Opaque DB-facing value |
| STO-02 | P0 | Unit | Filesystem Safety | Reject invalid `storage_ref` patterns | None | Resolve refs with traversal/absolute/backslash/drive/null byte inputs | Resolution returns safe error | Includes platform-specific separators |
| STO-03 | P0 | Unit | Filesystem Safety | Copy source file into managed storage | Temp source file exists | Run `store_copy` | File copied, checksum + size computed correctly | Bytes only in filesystem, never DB |
| STO-04 | P0 | Unit | Security | Symlink escape detection | Managed dir + outside file + symlink | Resolve/read symlink target | Operation fails safely if target escapes root | Must deny outside-root read |
| STO-05 | P1 | Unit | Safety | Managed storage path not exposed by API | Created artifact | Inspect returned descriptor/log payloads | No root path or resolved absolute path present | Internal-only storage path |
| CTX-01 | P0 | Integration | Scope/Auth | `create_artifact/2` enforces world scope consistency | Scope + attrs with mismatched world_id | Call create | Returns `{:error, :scope_mismatch}` | No row written |
| CTX-02 | P0 | Integration | Scope/Auth | `get_artifact` default returns ready-only | Ready + archived rows in-scope | Call `get_artifact/2` and include_non_ready variant | Default hides archived; opt-in can fetch | Also verify wrong-world not found |
| CTX-03 | P0 | Integration | Scope/Auth | `list_artifacts_for_scope` status filtering | Mixed statuses | Call default and explicit statuses | Default only ready; explicit statuses honored | Deleted/error excluded by default |
| CTX-04 | P0 | Integration | Scope/Auth | `list_artifacts_for_instance` isolates instance | Two instances same world | Query by instance id | Only target instance artifacts returned | No cross-instance bleed |
| CTX-05 | P1 | Integration | Lifecycle | `update_artifact_status/3` accepts only allowed statuses | Ready artifact | Update to archived/deleted/error/invalid | Allowed transitions persist; invalid rejected | Validate world scoping |
| CTX-06 | P0 | Unit | Safety | Public descriptor omits `storage_ref` and internal paths | Artifact row exists | Call descriptor helper/public API | Safe descriptor excludes sensitive fields | Includes id/filename/type/status/size/checksum/timestamps only |
| PRO-01 | P0 | Integration | Promotion | Promote workspace file to ready artifact | Instance scope + workspace file exists | Call `promote_workspace_file/2` | Row created `status=ready`; bytes copied; checksum/size set | Manual promotion only |
| PRO-02 | P0 | Integration | Promotion | Promotion copies file without moving source | Workspace file exists | Promote then re-read source | Source file remains unchanged | No destructive move |
| PRO-03 | P0 | Integration | Promotion | Original workspace path not persisted | Workspace path contains sentinel | Promote and inspect DB/descriptor | Raw workspace path absent from row + descriptor | Check metadata, notes, filename, storage_ref fields |
| PRO-04 | P0 | Integration | Update Semantics | Collision requires explicit mode | Existing same scope+lemming+filename | Promote with missing/ambiguous mode | Safe error; no overwrite | Prevent silent updates |
| PRO-05 | P0 | Integration | Update Semantics | `mode: :update_existing` overwrites managed bytes | Existing artifact + new source bytes | Promote with update mode | Same artifact row kept; checksum/size updated | Deterministic before/after assertions |
| PRO-06 | P0 | Integration | Update Semantics | `mode: :promote_as_new` creates distinct artifact | Existing artifact present | Promote with promote_as_new | New artifact row created; old row preserved | Non-unique filename index intent |
| PRO-07 | P0 | Integration | Failure Safety | Missing source file fails safely | Non-existent workspace path | Attempt promotion | Safe error token; no content/path leakage | No partial artifact row |
| PRO-08 | P1 | Integration | Failure Safety | Invalid source path traversal is rejected | Path like `../secret.txt` | Attempt promotion | `{:error, :invalid_path}` (or equivalent safe token) | No filesystem escape |
| OBS-01 | P0 | Integration | Observability | No durable Artifact lifecycle writes to `events` | Baseline event count | Promote/update/read/download flows | No new durable Artifact lifecycle rows | Task 05 scope lock |
| OBS-02 | P0 | Unit | Observability | If telemetry/logs exist, payload allowlist only | Telemetry handler/log capture | Trigger success/failure operations | Payload excludes content/storage_ref/paths/notes/full metadata/secrets | Verify key set explicitly |
| OBS-03 | P1 | Unit | Observability | Failure reasons normalized to safe tokens | Controlled failure cases | Inspect emitted reason | Reason values are bounded tokens | No exception dumps |
| DL-01 | P0 | Integration | Controller/Auth | Ready artifact downloads within visible scope | Instance + ready artifact + file exists | GET durable download route with valid world scope | `200`, attachment headers, file bytes returned | Route must be before workspace catch-all |
| DL-02 | P0 | Integration | Controller/Auth | Wrong scope denied before path resolution | Artifact in different world | Request with unrelated world scope | 404/forbidden-style safe failure | Assert storage resolution not invoked first |
| DL-03 | P0 | Integration | Controller/Lifecycle | Archived/deleted/error artifacts blocked | Artifact statuses set non-ready | Request download | Safe not found/forbidden, no file send | Default policy is ready-only |
| DL-04 | P0 | Integration | Controller/Failure | Missing physical file handled safely | DB row exists, file removed | Request download | Safe failure; optional status update to `error`; no path leak | Ensure deterministic response code |
| DL-05 | P0 | Integration | Controller/Security | Response headers are safe | Ready artifact exists | Request download | `x-content-type-options: nosniff`, safe content disposition | No absolute path in headers/body |
| DL-06 | P1 | Integration | Controller/Compatibility | Existing workspace artifact route still works | Workspace file in instance work area | Request legacy catch-all route | Existing behavior unchanged | Prevent regression from route ordering |
| UI-01 | P0 | LiveView | Timeline UX | File event renders `Promote to Artifact` action | Timeline includes file-producing tool event | Render view and target stable control ID | Action visible and actionable | Stable DOM IDs required |
| UI-02 | P0 | LiveView | Promotion UX | Promote action creates and displays artifact reference | Same as UI-01 | Trigger promote action | Timeline shows safe artifact descriptor fields | No raw file content dump |
| UI-03 | P0 | LiveView | Update/New UX | Existing filename collision presents update/new choices | Existing artifact same scope+filename | Open promotion UI | Both actions available with explicit mode intent | Prevent implicit overwrite |
| UI-04 | P1 | LiveView | Notes Rendering | Notes are visible but non-intrusive | Artifact has notes | Render artifact reference | Notes shown via compact UI pattern | Avoid large inline blocks |
| UI-05 | P0 | LiveView | Safe Rendering | Descriptor rendering excludes `storage_ref`/paths/content | Artifact with sentinel sensitive values | Render timeline row | Sentinel sensitive values absent from UI | Validate escaped/safe text rendering |
| SEC-01 | P0 | Unit | Security | Artifact code has no Secret Bank dependency | None | Static grep + compile references | No direct/indirect Secret Bank calls in artifact modules | Include tests/docs guard note |
| SEC-02 | P0 | Integration | Security | Artifact contents not auto-injected into LLM runtime context | Artifact exists with unique sentinel content | Trigger runtime context assembly flow | Sentinel content absent unless explicitly referenced by feature | Protect default model context |
| SEC-03 | P0 | Integration | Security | Path traversal and symlink escape across promotion + download | Malicious workspace path/symlink setup | Attempt promote/download | Requests fail safely without leakage | End-to-end hardening case |
| SEC-04 | P1 | Integration | Security | Wrong-scope artifact IDs are non-enumerable | Multiple worlds with known IDs | Probe cross-world IDs | Consistent safe not-found behavior | No existence oracle |
| REL-01 | P0 | Manual/CI | Validation | Narrow suites pass for touched layer | Tests implemented per layer | Run narrow `mix test` targets | All targeted suites green | Use before full suite |
| REL-02 | P0 | Manual/CI | Validation | Full `mix test` passes | Code complete | Run `mix test` | All tests pass | Zero failures |
| REL-03 | P0 | Manual/CI | Validation | Final `mix precommit` passes | Formatting + tests + credo/dialyzer ready | Run `mix precommit` | Passes with zero warnings/errors | Required quality gate |

## Acceptance Criteria Mapping
| Plan Acceptance Criterion | Scenario Coverage |
|---|---|
| Schema/table supports scope/provenance/metadata/lifecycle | SCH-01, SCH-02, SCH-03, SCH-04, SCH-05 |
| Bytes in local storage, not DB | STO-03, PRO-01, PRO-02 |
| Configurable artifact storage root | STO-01, STO-03 |
| Promotion copies workspace file into managed storage | PRO-01, PRO-02 |
| Promotion creates `ready` artifact | PRO-01 |
| Promotion computes `size_bytes` and SHA-256 | STO-03, PRO-01, PRO-05 |
| Original workspace path not persisted | PRO-03 |
| Manual promotion action exists in timeline | UI-01 |
| Same scope + lemming + filename can update existing | PRO-05, UI-03 |
| Promoted artifact appears in timeline as safe reference | UI-02, UI-05 |
| Controlled open/download route | DL-01 |
| `archived/deleted/error` not selectable/downloadable by default | CTX-02, CTX-03, DL-03 |
| Context APIs require explicit scope | CTX-01, CTX-02, CTX-03, CTX-04 |
| No durable Artifact lifecycle writes to `events` | OBS-01 |
| Artifact module does not access Secret Bank | SEC-01 |
| Artifact contents not auto-added to LLM context | SEC-02 |
| Docs updated (features + ADR) | REL-01 (docs-touch verification within slice), REL-03 |
| Tests cover schema/storage/promotion/update/download/UI/observability safety | SCH-*, STO-*, CTX-*, PRO-*, OBS-*, DL-*, UI-*, SEC-* |
| `mix format`, `mix test`, `mix precommit` pass | REL-01, REL-02, REL-03 |

## Leakage/Security Matrix (Sentinel Values)
Use fixed sentinel values in tests to detect unintended leakage across DB rows, descriptors, logs, telemetry, controller responses, and LiveView rendering.

| Sentinel | Example Value | Must Never Appear In | Covered By |
|---|---|---|---|
| Secret token | `sk_test_artifact_leak_9f6d` | logs, telemetry payloads, descriptors, UI, HTTP errors | OBS-02, UI-05, DL-04, SEC-02 |
| Workspace absolute path | `/tmp/workspaces/w1/i1/private/secret.txt` | DB metadata, descriptors, logs, HTTP bodies | PRO-03, PRO-07, DL-04 |
| Storage ref | `local://artifacts/world/artifact/secret.md` | UI labels, public descriptors, logs by default | CTX-06, UI-05, OBS-02 |
| Resolved storage root path | `/var/lib/lemmings/artifacts/world/a1/secret.md` | headers, response body, logs, telemetry | STO-05, DL-05, OBS-02 |
| Notes sentinel | `NOTE_LEAK_SENTINEL_DO_NOT_LOG` | logs/telemetry and large inline timeline blocks | UI-04, OBS-02 |
| Raw content sentinel | `TOP_SECRET_ARTIFACT_CONTENT` | DB fields other than managed file bytes, logs, descriptors, default runtime context | PRO-01, PRO-03, OBS-02, SEC-02 |

## Acceptance Criteria (Given/When/Then)
- Given an artifact outside the visible world scope, when it is requested through context or download route, then it is rejected with a safe not-found/forbidden-style result.
- Given an artifact in `archived`, `deleted`, or `error` status, when default list/get/download APIs are used, then it is excluded or rejected.
- Given a managed artifact row whose file is missing, when download is requested, then the request fails safely without exposing filesystem details and without durable event writes.
- Given a malicious path (`../`, absolute path, symlink escape), when promotion or resolution is attempted, then the operation is rejected and no sensitive values leak.
- Given an existing same-scope same-filename artifact, when promotion is requested without explicit mode, then no overwrite occurs and a safe collision result is returned.
- Given explicit `update_existing`, when promotion succeeds, then checksum/size are recomputed and the same artifact row is preserved.
- Given explicit `promote_as_new`, when promotion succeeds, then a new artifact row is created while prior rows remain.
- Given timeline promotion and artifact rendering, when the UI displays descriptors, then only safe descriptor fields are shown and no raw contents/storage refs/internal paths are rendered.
- Given observability hooks around artifact operations, when events are emitted, then payloads contain allowlisted metadata only and no durable Artifact lifecycle rows are written to `events`.
- Given runtime context assembly for LLM calls, when no explicit artifact-reference feature is used, then artifact content is not injected automatically.

## Required Narrow Test Commands
Run narrow commands by layer first, then full validation.

1. Schema/storage/context/promotion:
```bash
mix test test/lemmings_os/artifacts/artifact_test.exs \
  test/lemmings_os/artifacts/local_storage_test.exs \
  test/lemmings_os/artifacts_test.exs \
  test/lemmings_os/artifacts/promotion_test.exs
```
2. Download/controller scope and headers (after Task 07 test file exists):
```bash
mix test test/lemmings_os_web/controllers/instance_artifact_controller_test.exs
```
3. LiveView promotion/update/new rendering (after Task 08/09 updates):
```bash
mix test test/lemmings_os_web/live/instance_live_test.exs
```
4. Artifact + runtime non-injection guard:
```bash
mix test test/lemmings_os/lemming_calls_runtime_test.exs
```
5. Final suite:
```bash
mix test
mix precommit
```

## Regression Checklist
- [ ] No silent artifact overwrite on filename collision.
- [ ] No wrong-scope artifact fetch/download.
- [ ] No non-ready artifact default visibility/download.
- [ ] No raw workspace or resolved storage paths in DB/public outputs.
- [ ] No `storage_ref` leakage outside trusted internal boundary.
- [ ] No durable Artifact lifecycle rows written to `events`.
- [ ] No Secret Bank calls inside Artifact modules.
- [ ] No automatic artifact content injection into LLM context.
- [ ] Route ordering preserves both durable download route and legacy workspace catch-all route.
- [ ] Stable LiveView selectors/IDs cover promote/update/new actions.

## Out-of-scope
- Durable audit/event taxonomy design and retention policy.
- External storage backends (S3/MinIO).
- Automatic LLM/tool-driven artifact promotion.
- Artifact version history and full artifact library UX.
