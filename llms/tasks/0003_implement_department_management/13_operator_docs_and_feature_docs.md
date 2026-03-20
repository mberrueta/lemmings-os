# Task 13: Operator Docs and Feature Docs

## Status

- **Status**: 🔒 BLOCKED
- **Approved**: [ ] Human sign-off
- **Blocked by**: Task 12
- **Blocks**: Task 14
- **Estimated Effort**: S

## Assigned Agent

docs-feature-documentation-author - documentation writer for operator-facing product docs aligned to real behavior.

## Agent Invocation

Act as docs-feature-documentation-author following llms/constitution.md and update operator/feature docs for the shipped Department foundation.

## Objective

Document how operators use Department lifecycle, navigation, delete guardrails, and the initial settings foundation as they actually ship.

## Inputs Required

- [ ] llms/tasks/0003_implement_department_management/plan.md
- [ ] Task 12 output
- [ ] docs/operator/city-management.md
- [ ] any user-facing docs touched by the implementation

## Expected Outputs

- [ ] updated operator docs for Department creation/navigation/lifecycle/delete/settings
- [ ] wording that is honest about mock-backed or deferred Lemmings behavior

## Acceptance Criteria

- [ ] docs explain that Departments are persisted now
- [ ] docs describe delete guardrails conservatively
- [ ] docs describe settings as an initial foundation expected to evolve
- [ ] docs do not imply per-field source tracing or final runtime orchestration

## Technical Notes

### Constraints

- Keep docs operator-facing and behavior-first

## Execution Instructions

### For the Agent

1. Read the updated ADR/architecture wording first.
2. Update operator-facing docs to match the final implementation.
3. Call out any still-mock-backed areas honestly.

### For the Human Reviewer

1. Confirm the docs are useful to an operator and technically accurate.

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
