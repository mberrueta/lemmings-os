# Task 15: Final PR Audit

## Status

- **Status**: 🔒 BLOCKED
- **Approved**: [ ] Human sign-off
- **Blocked by**: Task 14
- **Blocks**: None
- **Estimated Effort**: S

## Assigned Agent

audit-pr-elixir - final PR reviewer for release-readiness, residual risk, and merge recommendation.

## Agent Invocation

Act as audit-pr-elixir following llms/constitution.md and perform the final PR audit for the Department management branch.

## Objective

Provide the last independent review pass after validation and docs work are complete, so the human can decide whether the branch is ready to merge.

## Inputs Required

- [ ] llms/tasks/0003_implement_department_management/plan.md
- [ ] outputs from Tasks 01-14
- [ ] final branch diff

## Expected Outputs

- [ ] final findings or explicit no-findings statement
- [ ] residual risk summary
- [ ] final merge-readiness recommendation

## Acceptance Criteria

- [ ] audit considers implementation, tests, docs, and validation outcomes together
- [ ] findings are ordered by severity
- [ ] residual risks and acceptable follow-ups are explicit

## Technical Notes

### Constraints

- Findings first, summary second

## Execution Instructions

### For the Agent

1. Review the final branch state, not an intermediate task slice.
2. Re-check prior risks after the validation step.
3. State clearly whether the branch is merge-ready.

### For the Human Reviewer

1. Decide whether to merge based on the final audit and all prior approvals.

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

- [ ] ✅ APPROVED - Ready to merge
- [ ] ❌ REJECTED - See feedback below

### Feedback

### Git Operations Performed

```bash
# human-only
```
