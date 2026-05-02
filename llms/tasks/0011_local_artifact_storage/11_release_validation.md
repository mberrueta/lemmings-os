# Task 11: Release Validation

## Status
- **Status**: COMPLETE
- **Approved**: [X] Human sign-off

## Assigned Agent
`rm-release-manager` - Release manager for validation evidence, rollout risk, rollback notes, and final sign-off preparation.

## Agent Invocation
Act as `rm-release-manager`. Prepare final release validation for the local Artifact storage backend hardening.

## Objective
Close the issue with validation evidence, documentation/security/style review summary, operational notes, residual risks, and human sign-off checklist.

## Inputs Required
- [ ] `llms/constitution.md`
- [ ] `llms/project_context.md`
- [ ] `llms/coding_styles/elixir.md`
- [ ] `llms/coding_styles/elixir_tests.md`
- [ ] `llms/tasks/0011_local_artifact_storage/plan.md`
- [ ] Tasks 01-10 outputs
- [ ] Full implementation diff and final test results

## Expected Outputs
- [ ] Release validation summary documented in this task file.
- [ ] Exact command evidence for narrow tests, broader tests as appropriate, `mix format`, and `mix precommit`.
- [ ] Confirmation docs are updated and match implementation.
- [ ] Confirmation final reviews covered docs, style/format, security/path leakage, accessibility scope, and regression risk.
- [ ] Operational notes for storage root, persistent volume, backup, rollback, and orphan-file risk.
- [ ] Human sign-off checklist.

## Acceptance Criteria
- [ ] Narrow relevant tests run and pass.
- [ ] `mix format` run or formatting verified.
- [ ] `mix precommit` passes with zero warnings/errors, or blocker is documented.
- [ ] Docs mention storage root, backup, persistent volume, no cleanup, and future S3/MinIO.
- [ ] Security and staff audit outputs have no unresolved high/medium blockers.
- [ ] No persistent Artifact storage audit rows through `LemmingsOs.Events` are introduced.

## Technical Notes
### Suggested Commands
```bash
mix test test/lemmings_os/artifacts/local_storage_test.exs
mix test test/lemmings_os/artifacts/artifact_test.exs test/lemmings_os/artifacts/promotion_test.exs test/lemmings_os/artifacts_test.exs
mix test test/lemmings_os_web/controllers/instance_artifact_controller_test.exs
mix test
mix format
mix precommit
rg -n "Events.record_event|LemmingsOs.Events" lib/lemmings_os/artifacts* lib/lemmings_os_web/controllers/instance_artifact_controller.ex
rg -n "SecretBank|SecretsBank|secret_bank|resolve_runtime_secret" lib/lemmings_os/artifacts* lib/lemmings_os_web/controllers/instance_artifact_controller.ex
```
Adjust commands to actual files changed.

### Constraints
- Do not perform git operations.
- Do not approve release if final validation fails without a documented human waiver.
- Do not hide residual risks.

## Execution Instructions
1. Read all task outputs and final diff.
2. Run validation commands in narrow-to-broad order.
3. Document command results exactly enough for human review.
4. Summarize docs/security/style/accessibility/regression review status.
5. Prepare rollback and residual risk notes.

---

## Execution Summary
### Validation Commands

- `mix format` passed.
- `mix test test/lemmings_os/artifacts/local_storage_test.exs test/lemmings_os/artifacts/artifact_test.exs test/lemmings_os/artifacts_test.exs test/lemmings_os/artifacts/promotion_test.exs test/lemmings_os_web/controllers/instance_artifact_controller_test.exs test/lemmings_os/config/runtime_artifact_storage_config_test.exs` passed: `20 doctests, 71 tests, 0 failures`.
- `mix test` passed: `162 doctests, 790 tests, 0 failures`.
- `mix precommit` passed with Dialyzer total errors `0` and Credo `found no issues`.
- `rg -n "Events.record_event|LemmingsOs.Events" lib/lemmings_os/artifacts lib/lemmings_os_web/controllers/instance_artifact_controller.ex` returned no matches.
- `rg -n "SecretBank|SecretsBank|secret_bank|resolve_runtime_secret" lib/lemmings_os/artifacts lib/lemmings_os_web/controllers/instance_artifact_controller.ex` returned no matches.

### Release Summary

- Local Artifact storage now has an adapter behavior, hardened local backend, scoped context open/download boundary, safe storage-error repair metadata, Logger/telemetry observability, and expanded regression coverage.
- Docs match implementation for `LEMMINGS_ARTIFACT_STORAGE_ROOT`, default max size, local layout, persistent volume requirements, DB plus artifact-volume backups, soft-delete non-purge behavior, and future object-storage/retention boundaries.
- Accessibility review found no UI/HEEx/LiveView changes.
- Security and staff Elixir audits found no unresolved high or medium blockers after the filename metadata sanitization fixes.

### Operational Notes

- Operators must put the artifact storage root on persistent storage in self-host/container deployments.
- Backups must include both Postgres and the artifact storage root or volume.
- Soft-deleted Artifacts are not physically purged; orphaned bytes can accumulate until a future cleanup/retention feature exists.
- Rollback of this code does not remove files already written under the configured root; database rows and local bytes should be handled together if reverting a deployment.

## Human Review
*[Filled by human reviewer]*
