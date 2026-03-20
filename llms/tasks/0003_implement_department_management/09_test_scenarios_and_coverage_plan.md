# Task 09: Test Scenarios and Coverage Plan

## Status

- **Status**: 🔒 BLOCKED
- **Approved**: [ ] Human sign-off
- **Blocked by**: Task 05, Task 06, Task 07, Task 08
- **Blocks**: Task 10
- **Estimated Effort**: M

## Assigned Agent

qa-test-scenarios - test scenario designer for acceptance, regressions, edge cases, and coverage planning.

## Agent Invocation

Act as qa-test-scenarios following llms/constitution.md and define the Department feature test matrix and coverage plan.

## Objective

Convert the approved Department implementation scope into a concrete test plan that covers domain, resolver, snapshot, and LiveView behavior without wasting effort on out-of-scope runtime systems.

## Inputs Required

- [ ] llms/tasks/0003_implement_department_management/plan.md
- [ ] Task 03 output
- [ ] Task 04 output
- [ ] Task 05 output
- [ ] Task 06 output
- [ ] Task 07 output
- [ ] Task 08 output
- [ ] existing tests under test/lemmings_os/ and test/lemmings_os_web/live/
- [ ] llms/coding_styles/elixir_tests.md

## Expected Outputs

- [ ] scenario document or completed task summary defining coverage layers
- [ ] recommended test file map
- [ ] explicit coverage expectations for risky paths

## Acceptance Criteria

- [ ] scenario plan covers schema/changeset, context/lifecycle, resolver, snapshots, and LiveViews
- [ ] delete guard and notes/tag edge cases are covered
- [ ] ownership split between Task 07 and Task 08 is reflected in separate UI test areas
- [ ] plan notes where mock-backed Lemmings tab behavior should be tested honestly

## Technical Notes

### Relevant Code Locations

```
test/lemmings_os/
test/lemmings_os_web/live/
```

### Patterns to Follow

- Outcome-focused tests using explicit DOM IDs for LiveView
- Deterministic DB sandbox coverage

### Constraints

- Do not write implementation tests in this task

## Execution Instructions

### For the Agent

1. Review all implemented surfaces/tasks first.
2. Propose the minimum sufficient test matrix with strong regression value.
3. Highlight any risky gaps that must be covered before PR review.

### For the Human Reviewer

1. Confirm the scenario plan is complete enough to drive Task 10.
2. Reject if key domain or UI paths are left implicit.

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
