# Task 15: Test Scenarios and Coverage Plan

## Status

- **Status**: BLOCKED
- **Approved**: [ ] Human sign-off
- **Blocked by**: Task 09, Task 10, Task 11, Task 12, Task 13, Task 14, Task 19
- **Blocks**: Task 16
- **Estimated Effort**: M

## Assigned Agent

`qa-test-scenarios` - QA planner for scenario decomposition, risk-based coverage, and branch-level regression gating.

## Agent Invocation

Act as `qa-test-scenarios` following `llms/constitution.md` and produce the executable test scenario matrix for the full Lemming management branch.

## Objective

Turn the branch-level acceptance criteria into a concrete, prioritized test plan covering schema, context, resolver, import/export, read models, and LiveView flows.

## Inputs Required

- [ ] `llms/tasks/0004_implement_lemming_management/plan.md`
- [ ] Outputs from Tasks 09 through 14
- [ ] Output from Task 19 for documentation-linked regressions
- [ ] Existing Lemmings/Departments/Cities tests and factories

## Expected Outputs

- [ ] Scenario matrix grouped by domain and layer
- [ ] Priority labels for must-have vs follow-up coverage
- [ ] Regression checklist for Task 16 and Task 17

## Acceptance Criteria

- [ ] Covers schema/changeset validation including activation guard and scoped slug uniqueness
- [ ] Covers context CRUD, lifecycle APIs, and delete denial behavior
- [ ] Covers resolver behavior for `World -> City -> Department -> Lemming`, including `tools_config`
- [ ] Covers import/export success and failure cases, including schema version handling
- [ ] Covers Home/Cities/Departments/Lemmings page regressions introduced by this feature
- [ ] Covers create/edit/detail/index UI flows using selector-based assertions
- [ ] Explicitly marks deferred or intentionally untested scope

## Technical Notes

### Constraints

- Keep the plan grounded in what the branch actually ships
- Prefer stable DOM selectors and deterministic time/data setup

## Execution Instructions

### For the Agent

1. Split scenarios by layer and risk, not by file names.
2. Make high-risk contracts explicit: world scoping, activation guard, delete denial, resolver preload requirements, import/export versioning.
3. Produce a checklist that Task 16 can implement directly.

### For the Human Reviewer

1. Verify the plan covers branch-level acceptance, not just happy paths.
2. Verify deferred areas are called out explicitly rather than silently omitted.

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
