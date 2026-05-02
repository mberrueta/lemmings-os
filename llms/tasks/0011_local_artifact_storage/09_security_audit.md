# Task 09: Security Audit

## Status
- **Status**: COMPLETE
- **Approved**: [X] Human sign-off

## Assigned Agent
`audit-security` - Security reviewer for input validation, authorization, secrets, logging, and data leakage risk.

## Agent Invocation
Act as `audit-security`. Review the completed local Artifact storage implementation for security issues and implement narrow fixes for confirmed in-scope findings.

## Objective
Verify local Artifact storage cannot escape the configured root, leak sensitive paths/content, weaken scope checks, or introduce secret/audit persistence risks.

## Inputs Required
- [ ] `llms/constitution.md`
- [ ] `llms/project_context.md`
- [ ] `llms/tasks/0011_local_artifact_storage/plan.md`
- [ ] Tasks 01-08 outputs
- [ ] Full implementation diff
- [ ] Relevant test results

## Expected Outputs
- [ ] Findings-first security audit documented in this task file.
- [ ] Review of path traversal, absolute path handling, symlink escape, null/control chars, filename separators, permissions, and max size.
- [ ] Review of scope/status checks before storage open/download.
- [ ] Review of error metadata, logs, telemetry, and controller responses for path/content/secret leakage.
- [ ] Confirmation no Artifact storage durable audit rows are persisted through `LemmingsOs.Events`.
- [ ] Focused fixes and regression tests for confirmed findings where safe.

## Acceptance Criteria
- [ ] High/medium findings are fixed or explicitly documented as blockers.
- [ ] No SecretBank coupling is added to Artifact storage.
- [ ] No file contents, absolute paths, root paths, raw workspace paths, full metadata, notes, or secrets leak through DB/logs/events/responses.
- [ ] Targeted tests or grep evidence back security claims.

## Technical Notes
### Relevant Code Locations
```text
lib/lemmings_os/artifacts.ex
lib/lemmings_os/artifacts/local_storage.ex
lib/lemmings_os/artifacts/artifact.ex
lib/lemmings_os_web/controllers/instance_artifact_controller.ex
test/lemmings_os/artifacts*
test/lemmings_os_web/controllers/instance_artifact_controller_test.exs
```

### Constraints
- Do not broaden authorization or UI scope beyond confirmed defects.
- Do not perform git operations.

## Execution Instructions
1. Read all inputs and inspect final diff.
2. Produce findings first, ordered by severity with file/line references.
3. Implement narrow fixes only for confirmed in-scope issues.
4. Run targeted tests for fixes.
5. Document residual risks and evidence.

---

## Execution Summary
### Findings

1. **Medium - unsafe persisted filenames could enter Logger/telemetry metadata.**
   - Location: `LemmingsOs.Artifacts.LocalStorage.open/2` observability metadata.
   - Impact: an Artifact row can contain control characters in `filename`; HTTP headers sanitize that value, but storage open Logger/telemetry metadata previously received the raw filename.
   - Fix: storage metadata now sanitizes filename values before Logger/telemetry emission, stripping control characters and path separators and truncating to 255 bytes. Added regression coverage for CR/LF filename metadata.

2. **No high findings.**

### Review Notes

- Path traversal, absolute paths, separators, null/control characters, drive prefixes, and leading `~` filenames are rejected by `LocalStorage` validation.
- Storage refs are parsed as `local://artifacts/<world_id>/<artifact_id>/<filename>`, validate UUIDs and filename shape, reject query/fragment, and resolve under the configured root before returning/opening paths.
- Symlink components under the storage root are rejected before `path_for/2`, `exists?/2`, `open/2`, or writes return/access a managed path.
- Downloads now call `Artifacts.open_artifact_download/2`, which checks scope/status before storage open and repairs missing/broken ready storage to `error` with safe metadata.
- Storage error metadata is limited to `storage_error_reason`, `storage_error_operation`, and `storage_error_at`; values reject paths, control characters, drive-style strings, and non-strings.
- Logger/telemetry metadata uses ids, operation, filename token, size/checksum, and normalized reason tokens only; tests assert no root/source path/ref/content leakage on representative paths.
- `rg "Events.record_event|LemmingsOs.Events" lib/lemmings_os/artifacts lib/lemmings_os_web/controllers/instance_artifact_controller.ex` returned no matches, confirming no durable Artifact storage audit rows were introduced.

### Evidence

- Targeted suite passed: `mix test test/lemmings_os/artifacts/local_storage_test.exs test/lemmings_os/artifacts/artifact_test.exs test/lemmings_os/artifacts_test.exs test/lemmings_os/artifacts/promotion_test.exs test/lemmings_os_web/controllers/instance_artifact_controller_test.exs test/lemmings_os/config/runtime_artifact_storage_config_test.exs`.

## Human Review
*[Filled by human reviewer]*
