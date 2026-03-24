# Task 18: Security and Performance Review

## Status

- **Status**: BLOCKED
- **Approved**: [ ] Human sign-off
- **Blocked by**: Task 17
- **Blocks**: Task 20
- **Estimated Effort**: M

## Assigned Agent

`audit-pr-elixir` - staff-level Elixir/Phoenix reviewer for correctness, security, performance, and testing gaps.

## Agent Invocation

Act as `audit-pr-elixir` following `llms/constitution.md` and review the Lemming management branch for correctness, security, performance, and coverage risks.

## Objective

Perform the formal branch review after implementation and validation, before the final PR audit.

## Inputs Required

- [ ] `llms/tasks/0004_implement_lemming_management/plan.md`
- [ ] Outputs from Tasks 01 through 17
- [ ] Relevant source and tests touched by the feature

## Expected Outputs

- [ ] Review findings ordered by severity
- [ ] Explicit callouts on security, performance, and testing gaps
- [ ] Recommendation on whether the branch is ready for final audit

## Acceptance Criteria

- [ ] Review covers world-scoping and cross-hierarchy access risks
- [ ] Review covers delete guard honesty and failure modes
- [ ] Review covers import/export parsing boundary and schema-version handling
- [ ] Review covers resolver preload / N+1 / aggregate-query risk on the new surfaces
- [ ] Review explicitly states whether residual risks remain

## Technical Notes

### Constraints

- Findings first, summary second

## Execution Instructions

### For the Agent

1. Review the full branch state, not a narrow file slice.
2. Prioritize correctness, security, and scaling risks over style notes.
3. State clearly if there are no findings.

### For the Human Reviewer

1. Resolve or explicitly accept review findings before Task 20.

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
