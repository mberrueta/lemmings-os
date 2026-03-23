# Task 12: ADR and Architecture Update

## Status

- **Status**: COMPLETE
- **Approved**: [X] Human sign-off
- **Blocked by**: None
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

### Work Performed

- Updated `docs/architecture.md` so Department persistence is described as shipped, Department runtime orchestration remains deferred, and the persisted hierarchy includes the real `departments` columns.
- Updated `docs/adr/0017-runtime-topology-city-execution-model.md` to distinguish shipped Department persistence from still-deferred Department runtime supervision.
- Updated `docs/adr/0020-hierarchical-configuration-model.md` so Department config storage and `World -> City -> Department` resolver support match the shipped implementation, while keeping deny-dominant merge, caching, ID-based loading, and source tracing explicitly deferred.
- Updated `docs/adr/0021-core-domain-schema.md` to reflect the shipped `departments` table, shipped `LemmingsOs.Departments.Department` schema module, and the remaining deferred Lemming runtime/persistence work.

### Outputs Created

- `docs/architecture.md`
- `docs/adr/0017-runtime-topology-city-execution-model.md`
- `docs/adr/0020-hierarchical-configuration-model.md`
- `docs/adr/0021-core-domain-schema.md`

### Assumptions Made

| Assumption | Rationale |
|------------|-----------|
| Department persistence should be documented as shipped even though Department runtime supervision is still deferred | The branch now includes the `departments` table, schema, context APIs, UI, and resolver support, but not City-hosted Department/Lemming runtime processes |
| ADR wording should stay narrow and avoid promising provenance/source tracing from the resolver | The shipped resolver returns only effective typed config buckets and does not expose per-field source metadata |

### Decisions Made

| Decision | Alternatives Considered | Rationale |
|----------|------------------------|-----------|
| Update existing ADRs instead of creating a new one | New ADR for Department persistence | The change is a correction/alignment of already-accepted architecture docs, not a new architectural fork |
| Keep runtime orchestration explicitly deferred in docs | Rewrite docs as if Department supervisor/manager already exist | The branch ships persistence and operator control-plane behavior only; overstating runtime execution would reintroduce drift |
| Document Department resolver support as shipped but source tracing as deferred | Promise richer provenance/explanation output from the resolver | Matches the actual `Resolver.resolve/1` contract without overclaiming future introspection behavior |

### Blockers Encountered

- None

### Questions for Human

1. Review whether the narrowed wording around Department runtime orchestration vs persisted control-plane foundation matches the intended long-term framing.

### Ready for Next Task

- [x] All outputs complete
- [x] Summary documented
- [x] Questions listed (if any)

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
