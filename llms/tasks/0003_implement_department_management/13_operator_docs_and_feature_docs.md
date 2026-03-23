# Task 13: Operator Docs and Feature Docs

## Status

- **Status**: COMPLETE
- **Approved**: [x] Human sign-off
- **Blocked by**: None
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

### Work Performed

- Added a new operator-facing Department guide covering persisted Department behavior, navigation, lifecycle actions, conservative delete guardrails, the mock-backed Lemmings tab, and the initial Settings foundation.
- Updated the City operator guide to link to the new Department guide and corrected the outdated limitation that claimed Department persistence was not implemented.
- Updated the root README so the operator docs section and documentation layout include Department management docs.

### Outputs Created

- `docs/operator/department-management.md`
- `docs/operator/city-management.md`
- `README.md`

### Assumptions Made

| Assumption | Rationale |
|------------|-----------|
| Operator-facing Department docs should live next to the existing City operator guide | `docs/operator/` already exists, is linked from the README, and is the most discoverable place for behavior-first operational documentation |
| The documentation should explicitly say Department creation/edit UI is incomplete | The shipped branch includes persistence and settings/lifecycle controls, but no dedicated create/edit Department form in the operator UI |

### Decisions Made

| Decision | Alternatives Considered | Rationale |
|----------|------------------------|-----------|
| Create a dedicated Department operator guide instead of expanding the City guide into a mixed document | Put all Department material inside `docs/operator/city-management.md` | Department lifecycle/settings behavior is large enough to deserve its own operator-facing doc and avoids turning the City guide into a grab bag |
| Document the Lemmings tab as mock-backed and non-authoritative | Describe it as if it were real runtime inventory | Matches the shipped UI and tests, and avoids misleading operators about current runtime orchestration |
| Document delete as conservatively denied by default | Describe delete as a normal successful lifecycle action | The current domain behavior denies delete unless safety can be proven, and the docs should set that expectation clearly |

### Blockers Encountered

- None

### Questions for Human

1. Do you want a short cross-link from the Departments page itself to the new operator guide later, or should it remain README/doc-only for now?

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
