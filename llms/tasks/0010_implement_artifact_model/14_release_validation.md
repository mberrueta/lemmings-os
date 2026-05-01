# Task 14: Release Validation

## Status
- **Status**: ✅ COMPLETE
- **Approved**: [ ] Human sign-off

## Assigned Agent
`rm-release-manager` - Release manager for migration risk, rollout notes, rollback planning, and final validation evidence.

## Agent Invocation
Act as `rm-release-manager`. Prepare final release validation for the Artifact model implementation.

## Objective
Close the Artifact implementation with migration notes, rollback guidance, validation evidence, and final checks against constitution and style guides.

## Inputs Required
- [x] `llms/constitution.md`
- [x] `llms/coding_styles/elixir.md`
- [x] `llms/coding_styles/elixir_tests.md`
- [x] `llms/tasks/0010_implement_artifact_model/plan.md`
- [x] Tasks 01-13 outputs
- [x] Full implementation diff and test results

## Expected Outputs
- [x] Release/validation summary documented in this task file.
- [x] Migration risk and rollback notes.
- [x] Final test command evidence.
- [x] Residual risk list and human sign-off checklist.

## Acceptance Criteria
- [x] Re-read and explicitly check `llms/constitution.md`, `llms/coding_styles/elixir.md`, and `llms/coding_styles/elixir_tests.md`.
- [x] Run narrow relevant tests first and record commands/results.
- [x] Run `mix test` and record result.
- [x] Run `mix precommit` and record result.
- [x] Confirm `mix format` or precommit formatting check passes.
- [x] Confirm no SecretBank/SecretsBank Artifact access via documented `rg` result from Task 11 or a fresh final check.
- [x] Confirm docs/ADR are updated and match implementation.
- [x] Confirm migration rollback impact is clearly stated.

## Technical Notes
### Relevant Commands
```bash
mix test test/lemmings_os/artifacts_test.exs
mix test test/lemmings_os_web/live/instance_live_test.exs
mix test test/lemmings_os_web/controllers
mix test
mix precommit
rg "SecretBank|SecretsBank|secret_bank|resolve_runtime_secret" lib test
```
Adjust narrow test paths to the actual files created during implementation.

### Constraints
- Do not perform git operations.
- Do not hide failures; document blockers clearly.
- Do not approve release if `mix precommit` fails without a documented human waiver.

## Execution Instructions

### For the Agent
1. Read all inputs listed above.
2. Review task summaries and final diff.
3. Run validation commands in narrow-to-broad order.
4. Document exact commands and outcomes.
5. Prepare migration/rollback notes and final residual risks.
6. Do not mark complete unless final validation passes or a blocker is explicitly documented.

### For the Human Reviewer
After agent completes:
1. Review final validation evidence.
2. Execute git operations if satisfied.
3. Provide final release sign-off or request follow-up fixes.

---

## Execution Summary
### Release Overview
- Release slice: Artifact model implementation (Tasks 01-14)
- Date: 2026-05-01
- Validation scope: backend artifact model, promotion/storage flow, download controller path, instance timeline integration, docs/ADR alignment
- Risk level: **Medium** (new durable data model + managed file storage path + user-facing download behavior)

### Constitution / Style Re-Check
- Re-read and checked against:
  - `llms/constitution.md`
  - `llms/coding_styles/elixir.md`
  - `llms/coding_styles/elixir_tests.md`
- Result: **PASS** for this slice after Task 11-13 fixes (scope isolation, tuple contracts, HEEx compliance, deterministic tests, no unsafe atom creation, no hardcoded secrets in Artifact code).

### Validation Evidence (Narrow → Broad)
1. Narrow Artifact-focused tests:
   - `mix test test/lemmings_os/artifacts/artifact_test.exs test/lemmings_os/artifacts/local_storage_test.exs test/lemmings_os/artifacts/promotion_test.exs test/lemmings_os/artifacts_test.exs test/lemmings_os_web/controllers/instance_artifact_controller_test.exs test/lemmings_os_web/live/instance_live_test.exs`
   - Result: `18 doctests, 83 tests, 0 failures`
2. Full test suite:
   - `mix test`
   - Result: `160 doctests, 758 tests, 0 failures`
3. Final quality gate:
   - `mix precommit`
   - Result: **PASS** (`dialyzer` clean, `credo` clean, formatter checks passing through precommit)

### SecretBank Boundary Confirmation
- Fresh final check (Artifact-focused paths):
  - `rg -n "SecretBank|SecretsBank|secret_bank|resolve_runtime_secret" lib/lemmings_os/artifacts.ex lib/lemmings_os/artifacts lib/lemmings_os_web/controllers/instance_artifact_controller.ex test/lemmings_os/artifacts_test.exs test/lemmings_os/artifacts test/lemmings_os_web/controllers/instance_artifact_controller_test.exs test/lemmings_os_web/live/instance_live_test.exs`
  - Result: no matches in Artifact implementation and Artifact tests.
- Cross-repo grep still shows expected SecretBank usage in non-Artifact modules (world/city/department/lemming secrets surfaces and secret_bank tests), consistent with Task 11 conclusions.

### Docs / ADR Alignment Check
- Verified updated docs are present and aligned with implementation:
  - `docs/features/artifacts.md`
  - `docs/adr/0008-lemming-persistence-model.md`
  - `README.md` feature index link
- Confirmed documentation states metadata vs bytes split and no automatic secret-bank/artifact-content injection behavior.

### Migration Risk Notes
- Migration: `priv/repo/migrations/20260501120000_create_artifacts.exs`
- DB changes:
  - New `artifacts` table with FK scope fields, lifecycle/status fields, checksum/size, metadata.
  - Indexes on world scope, hierarchy scope, instance/provenance references, and scope+filename lookup.
- Risk assessment:
  - **Runtime risk**: low-to-medium for migration execution (table create + indexes; no backfill step).
  - **Operational risk**: medium overall because durable feature behavior depends on both DB metadata and filesystem storage consistency.

### Rollback Guidance
- Application rollback: deploy previous app version to disable Artifact surface behavior.
- Database rollback impact:
  - Rolling back this migration drops the `artifacts` table and all persisted Artifact metadata rows.
  - Managed artifact files under local storage root are not automatically reconciled by DB rollback and may become orphaned.
- Recommended rollback approach:
  1. If rollback is required, prefer app rollback first while keeping DB unchanged if possible.
  2. If schema rollback is required, explicitly accept metadata loss and schedule orphaned-file cleanup under artifact storage root.
  3. Capture backup/snapshot before destructive DB rollback in production.

### Residual Risks
- Durable download path currently uses `File.read/1` + `send_resp/3`, which can increase memory pressure for very large files.
- No automatic orphan cleanup policy for managed files if rows are deleted/rolled back outside normal lifecycle paths.
- Promotion status focus behavior is improved but limited to current timeline pattern (per Task 12 notes).

### Human Sign-off Checklist
- [ ] Review command evidence above (narrow tests, full `mix test`, `mix precommit`).
- [ ] Confirm migration/rollback impact is acceptable for target environment.
- [ ] Confirm release timing for any potential large-file usage.
- [ ] Approve final release or request follow-up hardening tasks.
