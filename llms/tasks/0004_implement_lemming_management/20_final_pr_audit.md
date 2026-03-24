# Task 20: Final PR Audit

## Status

- **Status**: BLOCKED
- **Approved**: [ ] Human sign-off
- **Blocked by**: Task 18, Task 19
- **Blocks**: None
- **Estimated Effort**: S

## Assigned Agent

`audit-pr-elixir` - final PR reviewer for release-readiness, residual risk, and merge recommendation.

## Agent Invocation

Act as `audit-pr-elixir` following `llms/constitution.md` and perform the final PR audit for the Lemming management branch.

## Objective

Provide the last independent review pass after validation, review, and ADR/doc work are complete, so the human can decide whether the branch is ready to merge.

## Inputs Required

- [ ] `llms/tasks/0004_implement_lemming_management/plan.md`
- [ ] Outputs from Tasks 01 through 19
- [ ] Final branch diff

## Expected Outputs

- [ ] Final findings or explicit no-findings statement
- [ ] Residual risk summary
- [ ] Final merge-readiness recommendation

## Acceptance Criteria

- [ ] Audit considers implementation, tests, docs, and validation outcomes together
- [ ] Findings are ordered by severity
- [ ] Residual risks and acceptable follow-ups are explicit
- [ ] Final recommendation states whether the branch is merge-ready

## Technical Notes

### Constraints

- Findings first, summary second

## Execution Instructions

### For the Agent

1. Review the final branch state, not intermediate task slices.
2. Re-check prior risks after validation and ADR/doc updates.
3. State clearly whether the branch is merge-ready.

### For the Human Reviewer

1. Decide whether to merge based on the final audit and all prior approvals.

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

- [ ] APPROVED - Proceed to merge / next branch step
- [ ] REJECTED - See feedback below

### Feedback

### Git Operations Performed

```bash
# human-only
```
