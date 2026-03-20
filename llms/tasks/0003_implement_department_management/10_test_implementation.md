# Task 10: Test Implementation

## Status

- **Status**: 🔒 BLOCKED
- **Approved**: [ ] Human sign-off
- **Blocked by**: Task 09
- **Blocks**: Task 11
- **Estimated Effort**: L

## Assigned Agent

qa-elixir-test-author - QA-focused Elixir test writer for ExUnit, LiveView, and deterministic integration coverage.

## Agent Invocation

Act as qa-elixir-test-author following llms/constitution.md and implement the Department test suite defined by Task 09.

## Objective

Add the agreed automated tests for Department persistence, lifecycle APIs, resolver behavior, snapshots, and UI flows.

## Inputs Required

- [ ] llms/tasks/0003_implement_department_management/plan.md
- [ ] Task 09 output
- [ ] implemented code from Tasks 01-08
- [ ] llms/coding_styles/elixir_tests.md

## Expected Outputs

- [ ] ExUnit tests for schema/context/resolver
- [ ] LiveView or snapshot tests for Home/Cities/Departments flows
- [ ] deterministic coverage for delete guard behavior

## Acceptance Criteria

- [ ] tests follow repo factory and DB sandbox conventions
- [ ] no raw-HTML assertions where DOM-level selectors are more appropriate
- [ ] tests cover optional notes rendering, tag normalization, and city-scoped Department selection
- [ ] test suite is ready to support mix test and mix precommit

## Technical Notes

### Relevant Code Locations

```
test/lemmings_os/
test/lemmings_os_web/live/
test/support/
```

### Patterns to Follow

- Factory-first test data
- LiveView assertions via IDs and stable selectors

### Constraints

- No debug prints committed
- Keep tests deterministic

## Execution Instructions

### For the Agent

1. Implement only the scenarios approved in Task 09.
2. Keep tests grouped by layer and responsibility.
3. Document any untestable gap left by current runtime limitations.

### For the Human Reviewer

1. Confirm the tests map cleanly back to Task 09 scenarios.
2. Check that risky behaviors have concrete coverage.

---

## Execution Summary

*[Filled by executing agent after completion]*

### Work Performed

-

### Outputs Created

-

### Assumptions Made

| Assumption | Rationale |
|------------|-----------|
| | |

### Decisions Made

| Decision | Alternatives Considered | Rationale |
|----------|------------------------|-----------|
| | | |

### Blockers Encountered

-

### Questions for Human

1.

### Ready for Next Task

- [ ] All outputs complete
- [ ] Summary documented
- [ ] Questions listed (if any)

---

## Human Review

*[Filled by human reviewer]*

### Review Date

[YYYY-MM-DD]

### Decision

- [ ] ✅ APPROVED - Proceed to next task
- [ ] ❌ REJECTED - See feedback below

### Feedback

### Git Operations Performed

```bash
# human-only
```
