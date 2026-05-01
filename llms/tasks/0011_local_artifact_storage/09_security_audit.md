# Task 09: Security Audit

## Status
- **Status**: ⏳ PENDING
- **Approved**: [ ] Human sign-off

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
*[Filled by executing agent after completion]*

## Human Review
*[Filled by human reviewer]*
