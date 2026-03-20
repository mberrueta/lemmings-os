# Task 07: Departments Index Desmoke

## Status

- **Status**: 🔒 BLOCKED
- **Approved**: [ ] Human sign-off
- **Blocked by**: Task 03, Task 04
- **Blocks**: Task 08, Task 09
- **Estimated Effort**: M

## Assigned Agent

dev-frontend-ui-engineer - frontend engineer for LiveView navigation, selectors, map/index surfaces, and read-model-driven page desmoke.

## Agent Invocation

Act as dev-frontend-ui-engineer following llms/constitution.md and replace the mock-backed Departments index with a city-scoped persisted Department surface.

## Objective

Own the Departments index page only: city scoping, selector behavior, map/index presentation, and navigation into detail. Do not own detail-tab internals in this task.

## Inputs Required

- [ ] llms/tasks/0003_implement_department_management/plan.md
- [ ] Task 03 output
- [ ] Task 04 output
- [ ] lib/lemmings_os_web/live/departments_live.ex
- [ ] lib/lemmings_os_web/live/departments_live.html.heex
- [ ] lib/lemmings_os_web/components/world_components.ex
- [ ] lib/lemmings_os/mock_data.ex

## Expected Outputs

- [ ] persisted Department-backed DepartmentsLive index flow
- [ ] default-to-first-city behavior when params are absent
- [ ] city selector and city-scoped map/index navigation

## Acceptance Criteria

- [ ] Departments remains scoped to one city at a time
- [ ] page defaults to the first city when city param is absent
- [ ] map/index shows all departments for the selected city only
- [ ] clicking a department navigates into detail
- [ ] this task does not own Overview/Lemmings/Settings tab content beyond entering the detail route/state

## Technical Notes

### Relevant Code Locations

```
lib/lemmings_os_web/live/departments_live.ex
lib/lemmings_os_web/live/departments_live.html.heex
lib/lemmings_os_web/components/world_components.ex
```

### Patterns to Follow

- LiveView param-driven selection like existing pages
- Honest persisted data, no top-level MockData dependency

### Constraints

- Keep detail-tab ownership for Task 08
- Do not build a cross-city merged index

## Execution Instructions

### For the Agent

1. Remove the top-level MockData dependency from Departments index flow.
2. Implement city selection and defaulting behavior.
3. Adapt the visual/index surface so it works from real Department data.
4. Keep the handoff into Department detail explicit and minimal.

### For the Human Reviewer

1. Verify ownership stays on the index surface only.
2. Confirm the page never merges all cities together.
3. Reject if detail tab content starts getting implemented here.

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
