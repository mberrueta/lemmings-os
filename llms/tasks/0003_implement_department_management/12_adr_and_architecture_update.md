# Task 12: ADR and Architecture Update

## Status

- **Status**: 🔒 BLOCKED
- **Approved**: [ ] Human sign-off
- **Blocked by**: Task 11
- **Blocks**: Task 13
- **Estimated Effort**: M

## Assigned Agent

tl-architect - technical lead architect for narrowing ADR wording to match shipped implementation.

## Agent Invocation

Act as tl-architect following llms/constitution.md and update ADR/architecture documents so Department persistence and resolver behavior match the shipped implementation.

## Objective

Align architecture and ADR documents with what Department management actually ships now, including what remains explicitly deferred.

## Inputs Required

- [ ] llms/tasks/0003_implement_department_management/plan.md
- [ ] Task 11 output
- [ ] docs/architecture.md
- [ ] docs/adr/0017-runtime-topology-city-execution-model.md
- [ ] docs/adr/0020-hierarchical-configuration-model.md
- [ ] docs/adr/0021-core-domain-schema.md
- [ ] llms/project_context.md

## Expected Outputs

- [ ] doc/ADR wording updates that reflect Department persistence
- [ ] explicit documentation of deferred Department runtime behavior
- [ ] alignment note for naming mismatches if needed

## Acceptance Criteria

- [ ] docs no longer describe Departments as not-yet-persisted where that is now outdated
- [ ] resolver docs mention shipped World -> City -> Department support without promising full source tracing
- [ ] docs clearly distinguish shipped persistence foundation from deferred runtime orchestration

## Technical Notes

### Constraints

- Update only live docs, not closed historical task artifacts

## Execution Instructions

### For the Agent

1. Start from the review findings in Task 11.
2. Narrow wording where prior ADRs overclaimed future behavior.
3. Keep deferred items explicit.

### For the Human Reviewer

1. Verify docs describe what actually shipped, not what is merely intended later.

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
