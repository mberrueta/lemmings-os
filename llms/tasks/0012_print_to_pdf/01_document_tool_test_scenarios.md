# Task 01: Document Tool Test Scenarios

## Status
- **Status**: PENDING
- **Approved**: [ ]

## Assigned Agent
`qa-test-scenarios` - Test scenario designer for acceptance criteria, edge cases, regressions, and coverage planning.

## Agent Invocation
Act as `qa-test-scenarios`. Convert the print-to-PDF feature plan into a concrete scenario matrix before implementation starts.

## Objective
Define the complete test and acceptance scenario matrix for the two document tools: catalog registration, runtime dispatch, WorkArea path safety, Markdown rendering, PDF printing through Gotenberg, header/footer/CSS precedence, fallback assets, remote asset blocking, atomic writes, config parsing, observability, Docker Compose, and final validation.

## Inputs Required
- [ ] `llms/constitution.md`
- [ ] `llms/project_context.md`
- [ ] `llms/coding_styles/elixir.md`
- [ ] `llms/coding_styles/elixir_tests.md`
- [ ] `llms/tasks/0012_print_to_pdf/plan.md`
- [ ] `lib/lemmings_os/tools/catalog.ex`
- [ ] `lib/lemmings_os/tools/runtime.ex`
- [ ] `lib/lemmings_os/tools/work_area.ex`
- [ ] Existing tests under `test/lemmings_os/tools/**`

## Expected Outputs
- [ ] A scenario matrix appended to this task file.
- [ ] P0/P1/P2 coverage recommendations by subsystem.
- [ ] Explicit no-network-in-tests guidance using Bypass for Gotenberg.
- [ ] Explicit negative/security cases for path traversal, symlinks, unsupported formats, remote assets, CSS imports, fallback file constraints, oversized files, backend failures, and path/content leakage.

## Acceptance Criteria
- [ ] Every acceptance criterion in `plan.md` maps to at least one scenario.
- [ ] Scenarios identify the intended test layer: catalog, adapter unit, runtime integration, config, Compose review, logging/telemetry, or manual audit.
- [ ] Scenarios specify expected safe error codes where the plan freezes them.
- [ ] No implementation code or ExUnit tests are written in this task.

## Technical Notes
Relevant implementation areas:

```text
lib/lemmings_os/tools/catalog.ex
lib/lemmings_os/tools/runtime.ex
lib/lemmings_os/tools/work_area.ex
lib/lemmings_os/tools/adapters/filesystem.ex
lib/lemmings_os/tools/adapters/web.ex
test/lemmings_os/tools/catalog_test.exs
test/lemmings_os/tools/runtime_test.exs
test/lemmings_os/tools/adapters/filesystem_test.exs
docker-compose.yml
config/runtime.exs
mix.exs
```

## Execution Instructions
1. Read all inputs first.
2. Build a table with ID, priority, layer, setup, action, expected result, and later task owner.
3. Separate must-have P0 coverage from lower-priority compatibility or manual checks.
4. Call out ambiguities for human review before Task 02 starts.

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
Human reviewer confirms the scenario matrix is complete before Task 02 begins.
