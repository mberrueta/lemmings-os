# Task 14: Import/Export Minimal UI

## Status

- **Status**: BLOCKED
- **Approved**: [ ] Human sign-off
- **Blocked by**: Task 06, Task 10
- **Blocks**: Task 15, Task 16
- **Estimated Effort**: M

## Assigned Agent

`dev-frontend-ui-engineer` - frontend engineer for minimal operator-facing import/export flows.

## Agent Invocation

Act as `dev-frontend-ui-engineer` following `llms/constitution.md` and implement the minimal Lemming import/export UI promised by the plan, without widening into a wizard or package manager.

## Objective

Expose the already-built import/export context functions through a small operator UI:

- export from the Lemming detail view
- import into a Department via paste or file upload

This task is intentionally narrow and may be deferred if implementation cost becomes disproportionate, but the task artifact must exist to make that decision explicit.

## Inputs Required

- [ ] `llms/tasks/0004_implement_lemming_management/plan.md`
- [ ] Task 06 output
- [ ] Task 10 output
- [ ] Department Lemmings tab UI from Task 09
- [ ] Any router/controller/live action chosen for file download handling

## Expected Outputs

- [ ] Export action wired from the Lemming detail surface
- [ ] Import UI wired from the Department Lemmings tab
- [ ] Minimal parsing/error UX for invalid JSON or unsupported schema version

## Acceptance Criteria

- [ ] Lemming detail view exposes an `Export JSON` action
- [ ] Export produces a downloadable `.json` payload backed by `export_lemming/1`
- [ ] Department Lemmings tab exposes an `Import JSON` action
- [ ] Import accepts either pasted JSON or a simple uploaded file
- [ ] Import uses `import_lemmings/4` in the web layer after JSON parsing
- [ ] Unknown schema versions surface a clear operator-facing error
- [ ] No wizard, preview, diff view, drag-and-drop, or progress workflow is introduced
- [ ] If this task is explicitly deferred during implementation, the defer decision and rationale are recorded in the execution summary

## Technical Notes

### Constraints

- Keep JSON parsing in the web layer; the context still accepts maps
- Keep the UX intentionally minimal and honest
- Do not add package-management or skill-import concepts

## Execution Instructions

### For the Agent

1. Start from the context API built in Task 06.
2. Keep export single-click and import single-surface.
3. Prefer the smallest routing/event model that fits the existing app structure.
4. Record a defer rationale if the UI is consciously postponed.

### For the Human Reviewer

1. Verify the UI stays within the minimal scope promised by the plan.
2. Verify JSON parsing is not moved into the context.
3. Reject if the task balloons into a multi-step workflow.

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
