# Task 11: Security and Performance Review

## Status

- **Status**: 🔒 BLOCKED
- **Approved**: [ ] Human sign-off
- **Blocked by**: Task 10
- **Blocks**: Task 12
- **Estimated Effort**: M

## Assigned Agent

audit-pr-elixir - staff-level Elixir/Phoenix reviewer for correctness, security, performance, and testing gaps.

## Agent Invocation

Act as audit-pr-elixir following llms/constitution.md and review the Department branch for security, performance, correctness, and coverage risks.

## Objective

Perform the formal Department feature review before ADR/doc work and final validation.

## Inputs Required

- [ ] llms/tasks/0003_implement_department_management/plan.md
- [ ] outputs from Tasks 01-10
- [ ] relevant source and tests touched by the feature

## Expected Outputs

- [ ] review findings ordered by severity
- [ ] explicit callouts on security, performance, and testing gaps
- [ ] recommendation on whether the branch is ready for doc/update work

## Acceptance Criteria

- [ ] review covers preload/N+1 risk
- [ ] review covers delete guard honesty and failure modes
- [ ] review covers notes/XSS safety and input normalization
- [ ] review covers settings-scope overreach risk
- [ ] review explicitly states whether residual risks remain

## Technical Notes

### Relevant Code Locations

```
lib/lemmings_os/
lib/lemmings_os_web/
test/
```

### Constraints

- Findings first, summary second

## Execution Instructions

### For the Agent

1. Review the full diff and touched architecture paths.
2. Prioritize correctness, security, and performance findings over style notes.
3. State clearly if there are no findings.

### For the Human Reviewer

1. Resolve or explicitly accept review findings before moving on.

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
