# Task 19: ADR and Architecture Update

## Status

- **Status**: BLOCKED
- **Approved**: [ ] Human sign-off
- **Blocked by**: Task 01, Task 02, Task 03, Task 04, Task 05
- **Blocks**: Task 15, Task 16, Task 17, Task 18, Task 20
- **Estimated Effort**: M

## Assigned Agent

`tl-architect` - technical lead architect for narrowing ADR and architecture wording to the shipped Lemming definition model.

## Agent Invocation

Act as `tl-architect` following `llms/constitution.md` and update the ADRs and architecture docs so they match the Lemming model actually implemented in this branch.

## Objective

Correct the repo documentation that still describes a Lemming as a runtime process/supervised execution unit, and align it with the definition-first model shipped by this plan: persisted Department-scoped Lemming definitions, future runtime instances, and the provisional Lemming-only `tools_config` bucket.

## Inputs Required

- [ ] `llms/tasks/0004_implement_lemming_management/plan.md`
- [ ] Tasks 01 through 05 outputs
- [ ] `docs/architecture.md`
- [ ] `docs/adr/0020-hierarchical-configuration-model.md`
- [ ] `docs/adr/0021-core-domain-schema.md`
- [ ] `README.md`
- [ ] Any shipped UI/docs copy that still describes Lemmings as runtime processes

## Expected Outputs

- [ ] Updated `docs/adr/0021-core-domain-schema.md`
- [ ] Updated `docs/adr/0020-hierarchical-configuration-model.md`
- [ ] Updated `docs/architecture.md`
- [ ] Updated `README.md` if it still describes Lemmings as supervised/runtime processes
- [ ] Explicit wording that runtime execution belongs to a future `lemming_instances` entity, not the shipped `lemmings` table

## Acceptance Criteria

- [ ] Docs no longer describe a shipped Lemming as a live process, supervised unit, or runtime execution record
- [ ] `docs/adr/0021-core-domain-schema.md` explains why this branch ships `lemmings` instead of `lemming_types`
- [ ] `docs/adr/0021-core-domain-schema.md` states that shipped `lemmings` are Department-scoped definitions
- [ ] `docs/adr/0021-core-domain-schema.md` states that runtime executions are deferred to a future `lemming_instances` entity/table
- [ ] `docs/adr/0020-hierarchical-configuration-model.md` documents `World -> City -> Department -> Lemming` resolution
- [ ] `docs/adr/0020-hierarchical-configuration-model.md` documents that `tools_config` is Lemming-only in this PR as a deliberate provisional asymmetry
- [ ] `docs/adr/0020-hierarchical-configuration-model.md` explicitly states that v1 `tools_config` carries no governance semantics and does not alter ADR-0012 / ADR-0020 merge rules
- [ ] `docs/architecture.md` reflects the shipped definition-first model and removes/supersedes runtime-only field descriptions from the Lemming entity
- [ ] `README.md` is updated if it still says a Lemming is a supervised process or execution unit
- [ ] Deferred behaviors remain explicit: runtime processes, instance execution, mailbox/state/checkpoint persistence, and full skill packaging/import

## Technical Notes

### Constraints

- Keep updates grounded in the implemented branch, not the aspirational long-term model
- Update live docs only; do not rewrite historical task artifacts
- Be explicit where this branch narrows or diverges from prior ADR wording

### Required Targets

The following docs are mandatory review targets for this task:

- `docs/adr/0021-core-domain-schema.md`
- `docs/adr/0020-hierarchical-configuration-model.md`
- `docs/architecture.md`

`README.md` is conditionally required if it still contains the outdated runtime-process framing.

## Execution Instructions

### For the Agent

1. Compare Tasks 01 through 05 outputs against the listed ADRs/docs.
2. Remove or supersede wording that treats shipped Lemmings as runtime processes.
3. Document the shipped `lemmings` table as a Department-scoped persisted definition model.
4. Record the intentional `tools_config` asymmetry and its deferred upward propagation path.
5. Keep deferred runtime execution responsibilities explicit and narrow.

### For the Human Reviewer

1. Verify the docs match the branch that actually shipped, not the older runtime-process framing.
2. Verify ADR-0021 and ADR-0020 both explain the implementation divergence clearly.
3. Reject if the docs still imply that `lemmings` are live supervised processes.

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
