# Task 10: Documents ExUnit Coverage Closure

## Status
- **Status**: PENDING
- **Approved**: [ ]

## Assigned Agent
`qa-elixir-test-author` - QA-driven Elixir test writer for ExUnit, integration tests, LiveView tests, OTP tests, and focused regression coverage.

## Agent Invocation
Act as `qa-elixir-test-author`. Close ExUnit coverage gaps for the document tools after the focused implementation tasks have added their own tests.

## Objective
Compare the Task 01 scenario matrix against the tests already added by Tasks 02 through 08, then fill only meaningful remaining ExUnit gaps for catalog, adapter, runtime, config, Gotenberg success/failure, path safety, asset blocking, atomic writes, precedence, size limits, and safe observability.

This task should not rewrite already-good focused tests unless needed to fix correctness, determinism, or missing coverage.

## Inputs Required
- [ ] `llms/tasks/0012_print_to_pdf/plan.md`
- [ ] Task 01 scenario matrix
- [ ] Completed Tasks 02 through 09
- [ ] `llms/coding_styles/elixir_tests.md`
- [ ] `test/lemmings_os/tools/**`

## Expected Outputs
- [ ] Coverage gap checklist mapped from Task 01 scenarios to existing tests and newly added tests.
- [ ] Missing catalog/runtime/config/adapter tests added only where prior tasks did not already cover the behavior.
- [ ] Missing Bypass coverage added for Gotenberg success, failure, retry, and no-call validation cases.
- [ ] Missing assertions added for partial-output cleanup and forbidden path/content leakage.
- [ ] Tests that mutate Application env or System env restore prior values in `on_exit`.

## Acceptance Criteria
- [ ] No external network calls occur in tests.
- [ ] Tests use factories or local temp files as appropriate; no fixture-style helpers are introduced.
- [ ] Assertions are outcome-based and avoid large raw HTML comparisons.
- [ ] All P0 scenarios from Task 01 have coverage or an explicit human-approved reason for manual-only validation.
- [ ] Targeted tests pass without warnings.

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

## Execution Summary

### Work Performed
- [ ] To be completed by the executing agent.

### Outputs Created
- [ ] To be completed by the executing agent.

### Assumptions Made
- [ ] To be completed by the executing agent.

### Decisions Made
- [ ] To be completed by the executing agent.

### Blockers
- [ ] To be completed by the executing agent.

### Questions for Human
- [ ] To be completed by the executing agent.

### Ready for Next Task
- [ ] Yes
- [ ] No

## Human Review
Human reviewer confirms test coverage and remaining manual validation notes before Task 11 begins.
