# Task 10: Documents ExUnit Coverage Closure

## Status
- **Status**: COMPLETE
- **Approved**: [ ]

## Assigned Agent
`qa-elixir-test-author` - QA-driven Elixir test writer for ExUnit, integration tests, LiveView tests, OTP tests, and focused regression coverage.

## Agent Invocation
Act as `qa-elixir-test-author`. Close ExUnit coverage gaps for the document tools after the focused implementation tasks have added their own tests.

## Objective
Compare the Task 01 scenario matrix against the tests already added by Tasks 02 through 08, then fill only meaningful remaining ExUnit gaps for catalog, adapter, runtime, config, Gotenberg success/failure, path safety, asset blocking, atomic writes, precedence, size limits, and safe observability.

This task should not rewrite already-good focused tests unless needed to fix correctness, determinism, or missing coverage.

## Inputs Required
- [x] `llms/tasks/0012_print_to_pdf/plan.md`
- [x] Task 01 scenario matrix
- [x] Completed Tasks 02 through 09
- [x] `llms/coding_styles/elixir_tests.md`
- [x] `test/lemmings_os/tools/**`

## Expected Outputs
- [x] Coverage gap checklist mapped from Task 01 scenarios to existing tests and newly added tests.
- [x] Missing catalog/runtime/config/adapter tests added only where prior tasks did not already cover the behavior.
- [x] Missing Bypass coverage added for Gotenberg success, failure, retry, and no-call validation cases.
- [x] Missing assertions added for partial-output cleanup and forbidden path/content leakage.
- [x] Tests that mutate Application env or System env restore prior values in `on_exit`.

## Acceptance Criteria
- [x] No external network calls occur in tests.
- [x] Tests use factories or local temp files as appropriate; no fixture-style helpers are introduced.
- [x] Assertions are outcome-based and avoid large raw HTML comparisons.
- [x] All P0 scenarios from Task 01 have coverage or an explicit human-approved reason for manual-only validation.
- [x] Targeted tests pass without warnings.

## Technical Notes
- Use `Bypass` for Gotenberg. Do not require a real Gotenberg container in tests.
- Use stable helper names local to the test module when setting up WorkAreas and files.
- Keep test files focused; avoid broad assertions against implementation internals unless needed to verify atomic write cleanup or retry counts.
- Defer test quality/style review to Task 13; this task owns coverage closure, not a second broad audit.

## Execution Instructions
1. Read the scenario matrix, completed implementation, and tests already added by Tasks 02 through 08.
2. Identify coverage gaps before editing tests.
3. Add missing focused tests only for uncovered or under-covered behavior.
4. Run the narrowest relevant tests first:
   ```text
   mix test test/lemmings_os/tools/catalog_test.exs
   mix test test/lemmings_os/tools/adapters/documents_test.exs
   mix test test/lemmings_os/tools/runtime_test.exs
   ```
5. Run `mix format`.
6. Record commands and results in this task file.

## Coverage Gap Checklist (Task 01 -> current tests)

- `CAT-001` covered by existing `test/lemmings_os/tools/catalog_test.exs`.
- `RUN-001` covered by existing runtime markdown dispatch success test.
- `RUN-002` gap closed by new runtime PDF dispatch success-envelope test.
- `RUN-003` and `RUN-004` covered by existing unsupported tool and invalid scope tests.
- `RUN-005` gap closed by new runtime metadata propagation test (`work_area_ref` honored).
- `MD-001` through `MD-003` covered by existing adapter markdown conversion, validation, and atomic-write failure tests.
- `PDF-001` gap closed for `.htm` alias; existing `.html` success test already present.
- `PDF-002` gap closed by new markdown default-render vs `print_raw_file: true` coverage.
- `PDF-003` gap closed by new `.txt`, `.png`, `.jpg`, `.jpeg`, and `.webp` wrapper coverage.
- `PDF-004` through `PDF-008` covered by existing explicit/conventional/fallback asset tests, blocked remote/CSS import checks, output conflict checks, and no-backend-call assertions.
- `PDF-009` gap closed by new source-size-limit pre-backend check; existing generated-PDF size-limit check already covered.
- `PDF-010` covered by existing non-2xx, backend unavailable, and retry tests.
- `PDF-011` gap closed for unsupported print source extension; invalid path and explicit asset missing checks already covered.
- `OBS-001` covered by existing safe log assertions for start/completed/backend-failed paths.
- `CONF-001` covered by existing runtime documents env default/override/invalid parsing tests.
- `COMP-001` remains manual/static by design (out of ExUnit scope).

## Commands Run

```text
mix test test/lemmings_os/tools/catalog_test.exs
# 3 tests, 0 failures

mix test test/lemmings_os/tools/adapters/documents_test.exs
# 27 tests, 0 failures

mix test test/lemmings_os/tools/runtime_test.exs
# 17 tests, 0 failures

mix test test/lemmings_os/config/runtime_documents_config_test.exs
# 4 tests, 0 failures

mix format
# completed with no errors

mix precommit
# passed: dialyzer + credo
```

## Execution Summary

### Work Performed
- [x] Compared Task 01 scenario matrix against:
  - `test/lemmings_os/tools/catalog_test.exs`
  - `test/lemmings_os/tools/adapters/documents_test.exs`
  - `test/lemmings_os/tools/runtime_test.exs`
  - `test/lemmings_os/config/runtime_documents_config_test.exs`
- [x] Identified real remaining P0/P1 gaps and added focused tests only for missing behavior.
- [x] Re-ran targeted suites, formatted code, and ran `mix precommit`.

### Outputs Created
- [x] Added adapter coverage in `test/lemmings_os/tools/adapters/documents_test.exs` for:
  - `.htm` source support
  - Markdown default vs raw printing
  - Text/image wrapper printing
  - Print source size limit no-call behavior
  - Unsupported print source extension handling
- [x] Added runtime coverage in `test/lemmings_os/tools/runtime_test.exs` for:
  - `documents.print_to_pdf` normalized success envelope
  - Runtime `work_area_ref` metadata propagation for documents tools

### Assumptions Made
- [x] `COMP-001` (Docker Compose topology) is manual/static validation only and not an ExUnit gap.
- [x] Existing `WorkArea.resolve/2` coverage remains the primary `WA-001` boundary guard and is reused by documents adapters.

### Decisions Made
- [x] Added only scenario-driven missing tests; avoided refactoring existing stable tests.
- [x] Kept all backend interactions under `Bypass` to preserve deterministic, offline tests.

### Blockers
- [x] None.

### Questions for Human
- [x] None.

### Ready for Next Task
- [x] Yes
- [ ] No

## Human Review
Human reviewer confirms test coverage and remaining manual validation notes before Task 11 begins.
