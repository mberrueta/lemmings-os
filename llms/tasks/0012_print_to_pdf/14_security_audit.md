# Task 14: Security Audit

## Status
- **Status**: COMPLETE
- **Approved**: [ ]

## Assigned Agent
`audit-security` - Security reviewer for authentication, authorization, input validation, secrets, OWASP risks, and PII safety.

## Agent Invocation
Act as `audit-security`. Audit the document tools for path, content, network, backend, and logging risks.

## Objective
Verify that document tools cannot escape WorkAreas, leak host paths or content, fetch remote assets, expose Gotenberg publicly by default, accept agent-controlled backend URLs, or leave partial unsafe outputs.

## Inputs Required
- [x] `llms/tasks/0012_print_to_pdf/plan.md`
- [x] Completed Tasks 02 through 13
- [x] Source diff, tests, runtime config, and Docker Compose changes

## Expected Outputs
- [x] Security findings written into this task file, ordered by severity.
- [x] Path traversal, absolute path, Windows path, backslash path, symlink, fallback file, and output overwrite behavior reviewed.
- [x] Remote asset and CSS import blocking reviewed.
- [x] Gotenberg URL control and private exposure reviewed.
- [x] Logs, telemetry, results, and errors reviewed for document content, host path, fallback path, backend body, and secret leakage.
- [x] Size-limit and atomic-write behavior reviewed.

## Acceptance Criteria
- [x] No critical/high findings remain unresolved or unwaived.
- [x] Validation errors happen before Gotenberg calls.
- [x] Operator fallback files cannot escape `priv/documents/` or follow symlinks.
- [x] Gotenberg is not published to the host in default Compose.
- [x] Security residual risks are documented for release notes.

## Technical Notes
- Treat Gotenberg as an internal rendering backend that should not be directly reachable by agents or public users.
- This audit included code and tests.

## Execution Instructions
1. Read the plan and completed implementation.
2. Inspect source, tests, config, and Compose changes.
3. Run security-relevant targeted tests or static checks if useful.
4. Write findings and required fixes in this task file.

## Findings (Ordered by Severity)

### Medium
1. `overwrite: false` is vulnerable to a TOCTOU overwrite race.
   - File refs: `lib/lemmings_os/tools/adapters/documents.ex:335`, `lib/lemmings_os/tools/adapters/documents.ex:528`, `lib/lemmings_os/tools/adapters/documents.ex:1477`.
   - Why: Existence is checked before write/rename, but a file can be created between check and `File.rename/2`; rename may replace it.
   - Impact: `overwrite: false` is best-effort under concurrent writes, not strict.
   - Recommendation: Document this constraint explicitly and, if strict no-overwrite semantics are required, switch to an atomic create/link strategy that fails on destination-exists.

### Low
1. Test coverage gaps for full blocked-reference matrix and fallback escape variants.
   - File refs: `test/lemmings_os/tools/adapters/documents_test.exs:689`, `test/lemmings_os/tools/adapters/documents_test.exs:728`.
   - Why: Current tests verify representative blocked references, and now include outside-root fallback via symlinked parent directory; `file://` and protocol-relative URL cases remain implicit via shared guard logic.
   - Impact: Core protections exist, but regression risk remains for untested branches.
   - Recommendation: Add focused tests for all blocked-reference classes and fallback-outside-root/symlink-component escape attempts.

### Resolved During Finalization
1. Fallback `priv/documents` boundary hardening for symlinked parent directories.
   - Resolution: fallback asset resolution now rejects symlinked path components and resolves fallback root from application paths, not process CWD.
   - Evidence: `lib/lemmings_os/tools/adapters/documents.ex` and `test/lemmings_os/tools/adapters/documents_test.exs` (`fallback asset under symlinked parent directory is rejected as outside_root`).

## Controls Verified (No Finding)
- WorkArea path safety rejects traversal, absolute, Windows drive, backslash, and symlink traversal for agent-controlled paths via `WorkArea.resolve/2` and tests.
  - File refs: `lib/lemmings_os/tools/work_area.ex:56`, `lib/lemmings_os/tools/work_area.ex:143`, `lib/lemmings_os/tools/work_area.ex:191`, `test/lemmings_os/tools/work_area_test.exs:50`.
- Remote asset policy checks occur before backend call and are fail-fast.
  - File refs: `lib/lemmings_os/tools/adapters/documents.ex:1168`, `lib/lemmings_os/tools/adapters/documents.ex:1235`, `test/lemmings_os/tools/adapters/documents_test.exs:713`, `test/lemmings_os/tools/adapters/documents_test.exs:750`.
- Gotenberg is internal-only in default Compose (no host `ports` on `gotenberg`).
  - File refs: `docker-compose.yml:42`, `docker-compose.yml:44`, `docker-compose.yml:46`.
- Agent cannot set backend URL through tool args; URL comes from server config only.
  - File refs: `lib/lemmings_os/tools/adapters/documents.ex:1535`, `config/runtime.exs:56`.
- Logging/results avoid document body, absolute paths, and backend response body leakage in tested paths.
  - File refs: `lib/lemmings_os/tools/adapters/documents.ex:1385`, `lib/lemmings_os/tools/adapters/documents.ex:1405`, `test/lemmings_os/tools/adapters/documents_test.exs:271`, `test/lemmings_os/tools/adapters/documents_test.exs:315`.
- Atomic temp-write then rename behavior is present; oversized-PDF path prevents final output creation.
  - File refs: `lib/lemmings_os/tools/adapters/documents.ex:1477`, `test/lemmings_os/tools/adapters/documents_test.exs:387`.

## Critical/High Status
No critical or high unresolved findings were identified.

## Residual Risks For Release Notes
- Asset blocking is intentionally conservative regex/pattern matching and not a full HTML/CSS parser; bypass resistance depends on this MVP scope.
- `overwrite: false` currently provides conflict protection but not strict race-free guarantees under concurrent local writers.

## Execution Summary

### Work Performed
- Reviewed plan requirements and completed task outputs for Tasks 02-13.
- Audited implementation in documents adapter, WorkArea path resolver, runtime config, and Compose topology.
- Audited tests for path safety, fallback behavior, blocked assets, logging leakage, backend behavior, and atomic output handling.
- Performed a small local filesystem behavior check to validate `lstat` behavior through symlinked parent directories.
- Ran targeted test suites for documents adapter, WorkArea path resolver, and runtime documents config.

### Outputs Created
- Updated this audit record with severity-ordered findings, verified controls, residual risks, and completion status.

### Assumptions Made
- Operator-controlled deployment files and env vars are trusted inputs, but still subject to defense-in-depth boundary checks.
- Threat model includes untrusted agent tool input and potential concurrent file activity on shared runtime hosts.

### Decisions Made
- Classified findings by practical exploitability and deployment boundary impact.
- Kept this task review-only and did not modify application code.

### Blockers
- None.

### Questions for Human
- None.

### Ready for Next Task
- [x] Yes
- [ ] No

### Commands Run And Results
- `mix test test/lemmings_os/tools/adapters/documents_test.exs` (success; 22 tests, 0 failures)
- `mix test test/lemmings_os/tools/work_area_test.exs` (success; 10 tests, 0 failures)
- `mix test test/lemmings_os/config/runtime_documents_config_test.exs` (success; 4 tests, 0 failures)
- `elixir -e '...File.lstat(".../link/..." )...'` (manual check confirmed `lstat` reports regular file when parent path component is a symlink)

## Human Review
Human reviewer resolves or waives security findings before Task 15 begins.
