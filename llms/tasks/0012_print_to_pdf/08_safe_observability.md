# Task 08: Safe Observability

## Status
- **Status**: COMPLETED
- **Approved**: [x]

## Assigned Agent
`dev-logging-daily-guardian` - Logging quality guardian for safe structured events, metadata consistency, and sensitive-data avoidance.

## Agent Invocation
Act as `dev-logging-daily-guardian`. Add and review document-tool logging and telemetry after backend document behavior and asset policy are implemented.

## Objective
Ensure document tool logs and telemetry are useful for operators without leaking document contents, generated HTML, WorkArea roots, absolute host paths, fallback paths, backend response bodies, or secrets.

## Inputs Required
- [ ] `llms/tasks/0012_print_to_pdf/plan.md`
- [ ] Completed Tasks 01 through 07
- [ ] `llms/coding_styles/elixir.md`
- [ ] Existing logging and telemetry patterns under `lib/lemmings_os/**`

## Expected Outputs
- [ ] Logs cover conversion/print start, completion, expected failures, backend failures, and unexpected failures with safe metadata only.
- [ ] Telemetry, if added, uses atom-list event names and safe metadata.
- [ ] Tests or audit notes verify logs/telemetry exclude document contents, generated HTML, absolute paths, WorkArea roots, fallback paths, secrets, raw backend bodies, and full exception dumps.
- [ ] Existing runtime tool lifecycle telemetry remains compatible.

## Acceptance Criteria
- [ ] No production validation behavior is owned by this task beyond observability-safe normalization needed for logs or telemetry.
- [ ] Logs may include WorkArea-relative source/output paths, reason codes, backend name, status code when safe, byte size, duration, and hierarchy metadata where available.
- [ ] Logs must not include document contents, generated HTML, absolute paths, WorkArea roots, fallback env file paths, secrets, raw backend response bodies, or full exception dumps.
- [ ] Unexpected failures are logged with reason codes rather than inspected payloads.

## Technical Notes
- Task 07 owns the HTML/CSS asset blocking behavior.
- This task may adjust adapter metadata and tests to keep observability safe, but it should avoid broad backend behavior changes.
- If telemetry is added, include hierarchy metadata where available from the runtime/instance context.

## Execution Instructions
1. Read the completed adapter implementation and existing logging patterns.
2. Add safe logging/telemetry only where it improves operational visibility.
3. Add or update tests/audit assertions for non-leaky metadata.
4. Run:
   ```text
   mix test test/lemmings_os/tools/adapters/documents_test.exs
   mix test test/lemmings_os/tools/runtime_test.exs
   mix format
   ```
5. Record commands and results in this task file.

## Execution Summary

### Work Performed
- [x] Added structured safe observability logs to `print_to_pdf/3` for start, completion, expected failures, backend failures, backend retries, and backend unavailability.
- [x] Kept log payloads free of document contents, generated HTML, absolute paths, WorkArea roots, fallback paths, secrets, and raw backend response bodies.
- [x] Added adapter tests asserting observability events and non-leaky logging behavior.
- [x] Preserved runtime tool lifecycle telemetry compatibility (no lifecycle telemetry contract changes).

### Outputs Created
- [x] Updated `lib/lemmings_os/tools/adapters/documents.ex`.
- [x] Updated `test/lemmings_os/tools/adapters/documents_test.exs`.

### Assumptions Made
- [x] Existing runtime tool lifecycle telemetry already provides required lifecycle compatibility; this task focuses on safe adapter-level logging.

### Decisions Made
- [x] Used static log messages plus structured metadata and stable `event` keys.
- [x] Used normalized reason tokens derived from safe error codes for unexpected/expected failures instead of inspected payloads.
- [x] Logged only safe relative path data (`path`) plus operational metadata (`status`, `reason`, `retry_count`, `max_retries`, `duration_ms`, `size_bytes`, hierarchy ids).

### Blockers
- [x] `mix precommit` is not fully green due existing Credo findings in `lib/lemmings_os/tools/adapters/documents.ex` (readability/refactoring), including pre-existing complexity/style issues.

### Questions for Human
- [x] Should we do a follow-up cleanup task to resolve the remaining Credo findings in `documents.ex`?

### Ready for Next Task
- [x] Yes
- [ ] No

### Commands Run
- `mix test test/lemmings_os/tools/adapters/documents_test.exs` ✅
- `mix test test/lemmings_os/tools/runtime_test.exs` ✅
- `mix format` ✅
- `mix precommit` ⚠️ Dialyzer passed; Credo reported existing/refactor issues in `lib/lemmings_os/tools/adapters/documents.ex`.

## Human Review
Human reviewer confirms non-leaky observability before Task 09 begins.
