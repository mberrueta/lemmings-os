# Task 16: Test Implementation

## Status

- **Status**: BLOCKED
- **Approved**: [ ] Human sign-off
- **Blocked by**: Task 15
- **Blocks**: Task 17
- **Estimated Effort**: L

## Assigned Agent

`qa-elixir-test-author` - QA-focused Elixir test writer for ExUnit, LiveView, and deterministic integration coverage.

## Agent Invocation

Act as `qa-elixir-test-author` following `llms/constitution.md` and implement the approved Lemming management test suite from Task 15.

## Objective

Add the automated tests needed to prove the Lemming definition foundation is correct across persistence, lifecycle, resolver behavior, import/export, and UI.

## Inputs Required

- [ ] `llms/tasks/0004_implement_lemming_management/plan.md`
- [ ] Task 15 output
- [ ] Implemented code from Tasks 01 through 14
- [ ] Existing test helpers/factories

## Expected Outputs

- [ ] ExUnit tests for schema/context/resolver/import-export behavior
- [ ] LiveView/page-data tests for impacted operator flows
- [ ] Coverage for delete guard, activation guard, and world-scoping boundaries

## Acceptance Criteria

- [ ] Tests follow repo factory and DB sandbox conventions
- [ ] Tests use DOM selectors and stable IDs for LiveView assertions
- [ ] Tests cover import/export roundtrip and schema version edge cases
- [ ] Tests are ready to support `mix test` and `mix precommit`

## Technical Notes

### Constraints

- Implement the approved Task 15 plan; do not expand into unrelated coverage churn
- Keep tests deterministic and free of debug output

## Execution Instructions

### For the Agent

1. Implement only the scenarios approved in Task 15.
2. Group tests by layer and responsibility.
3. Record any intentionally untestable gap left by current scope.

### For the Human Reviewer

1. Verify the implemented suite maps back to Task 15.
2. Check that the highest-risk contracts have explicit coverage.

---

## Execution Summary

*[Filled by executing agent after completion]*

### Work Performed

- [What was actually done]

### Outputs Created

- [List of files/artifacts created]

### Assumptions Made

| Assumption | Rationale |
|------------|-----------|

### Decisions Made

| Decision | Alternatives Considered | Rationale |
|----------|------------------------|-----------|

### Blockers Encountered

- [Blocker 1] - Resolution: [How resolved or "Needs human input"]

### Questions for Human

1. [Question needing human input]

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

- [ ] APPROVED - Proceed to next task
- [ ] REJECTED - See feedback below

### Feedback

### Git Operations Performed

```bash
# human-only
```
