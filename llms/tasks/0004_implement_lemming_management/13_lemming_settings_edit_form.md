# Task 13: Lemming Settings/Edit Form

## Status

- **Status**: BLOCKED
- **Approved**: [ ] Human sign-off
- **Blocked by**: Task 10
- **Blocks**: Task 15, Task 16
- **Estimated Effort**: M

## Assigned Agent

`dev-frontend-ui-engineer` - frontend engineer for changeset-backed edit flows and settings surfaces.

## Agent Invocation

Act as `dev-frontend-ui-engineer` following `llms/constitution.md` and implement the Lemming settings/edit form for mutable definition fields and local config overrides.

## Objective

Add the operator-facing edit flow for an existing Lemming so the stored definition can be updated after creation. This task owns the editable settings surface that Task 10 explicitly left read-only.

## Inputs Required

- [ ] `llms/tasks/0004_implement_lemming_management/plan.md`
- [ ] Task 10 output
- [ ] `lib/lemmings_os/lemmings.ex`
- [ ] `lib/lemmings_os/lemmings/lemming.ex`
- [ ] Relevant LiveView/template files chosen by Task 10 for the Lemming detail surface

## Expected Outputs

- [ ] Updated LiveView/event handlers for Lemming edit mode
- [ ] Updated template or component for the edit/settings form
- [ ] Routing/query-param adjustments if needed for entering edit mode

## Acceptance Criteria

- [ ] Operators can edit: `name`, `slug`, `description`, `instructions`, `status`
- [ ] Operators can edit local config overrides for all five buckets, including `tools_config`
- [ ] `world_id`, `city_id`, and `department_id` are not editable from the form
- [ ] Form uses `to_form/2` and `<.input>`-driven HEEx conventions
- [ ] Live validation runs on `phx-change` and errors render inline
- [ ] Successful save calls `Lemmings.update_lemming/2`
- [ ] On success, flash is shown and the detail view reflects persisted updates
- [ ] Activation guard remains enforced when status is changed to `active`
- [ ] No delete behavior is added here

## Technical Notes

### Constraints

- Keep the edit form scoped to the Lemming definition already selected in Task 10
- Do not broaden this task into a separate generic settings system
- Reuse existing config-form patterns from World/City/Department settings where appropriate

## Execution Instructions

### For the Agent

1. Start from the detail surface built in Task 10.
2. Add an explicit edit/settings mode rather than mixing read-only and editable states ambiguously.
3. Keep hierarchy ownership fields server-controlled.
4. Keep the UI honest about local overrides versus effective config.

### For the Human Reviewer

1. Verify this task edits real persisted data, not local assigns only.
2. Verify config editing stays within the Lemming scope and does not imply per-field provenance tracing.
3. Reject if the task introduces delete or runtime-instance behavior.

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
