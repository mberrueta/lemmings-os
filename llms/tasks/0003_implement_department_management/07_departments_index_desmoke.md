# Task 07: Departments Index Desmoke

## Status

- **Status**: ✅ COMPLETE
- **Approved**: [X] Human sign-off
- **Blocked by**: None
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

- Replaced the top-level `MockData` Departments index flow with persisted city-scoped loading via `CitiesPageSnapshot` and `LemmingsOs.Departments`.
- Implemented selector-driven city scoping with default-to-first-city behavior when `?city=` is absent.
- Refactored the Departments page surface into a city selector, a city-scoped index list, and a matching tile/map panel that only renders departments for the selected city.
- Reduced `dept=` route handling to a minimal persisted detail handoff panel so Task 08 can own the real detail tabs.

### Outputs Created

- persisted `DepartmentsLive` index flow
- DepartmentsLive desmoke coverage
- explicit detail handoff copy and route contract for Task 08

### Assumptions Made

| Assumption | Rationale |
|------------|-----------|
| A lightweight detail handoff panel is sufficient for Task 07 | The task explicitly owns index navigation only and should not absorb the Overview/Lemmings/Settings internals planned for Task 08 |

### Decisions Made

| Decision | Alternatives Considered | Rationale |
|----------|------------------------|-----------|
| Reuse `CitiesPageSnapshot` to resolve world and default city selection | Building a new Departments snapshot from scratch in this task | Reusing the existing city read model kept the persisted selection logic narrow and consistent with the Cities surface |
| Keep the existing city map surface but feed it persisted Department data | Replacing the map with static tiles | The task explicitly owns a map/index presentation, so preserving the canvas while swapping the source of truth avoids a UI regression |

### Blockers Encountered

- None

### Questions for Human

1. None.

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
