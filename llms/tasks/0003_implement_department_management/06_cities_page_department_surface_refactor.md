# Task 06: Cities Page Department Surface Refactor

## Status

- **Status**: ✅ COMPLETE
- **Approved**: [ ] Human sign-off
- **Blocked by**: None
- **Blocks**: Task 09
- **Estimated Effort**: M

## Assigned Agent

dev-frontend-ui-engineer - frontend engineer for LiveView page snapshots, card/grid surfaces, and truthful data-backed desmoke work.

## Agent Invocation

Act as dev-frontend-ui-engineer following llms/constitution.md and refactor the Cities surface around persisted Department cards for the selected city.

## Objective

Convert Cities from a mock-child preview surface into a real city selector plus compact Department cards surface, without taking ownership of Department detail flows.

## Inputs Required

- [ ] llms/tasks/0003_implement_department_management/plan.md
- [ ] Task 03 output
- [ ] Task 04 output
- [ ] lib/lemmings_os_web/live/cities_live.ex
- [ ] lib/lemmings_os_web/live/cities_live.html.heex
- [ ] lib/lemmings_os_web/page_data/cities_page_snapshot.ex
- [ ] lib/lemmings_os_web/page_data/cities_mock_children_snapshot.ex

## Expected Outputs

- [ ] real Department cards in the Cities snapshot/template
- [ ] removal of authoritative mock Department child adapter usage
- [ ] + affordance that routes to the Departments surface scoped to the selected city

## Acceptance Criteria

- [ ] Cities keeps city selection and compact city details
- [ ] Department cards show only name, status, tags, and truncated notes when present
- [ ] cards navigate to Department detail
- [ ] Cities does not implement inline Department CRUD
- [ ] ownership stops at list/card surface; it does not define Department detail tabs or settings interactions

## Technical Notes

### Relevant Code Locations

```
lib/lemmings_os_web/page_data/cities_page_snapshot.ex
lib/lemmings_os_web/live/cities_live.html.heex
lib/lemmings_os_web/components/world_components.ex
```

### Patterns to Follow

- Snapshot-backed UI, not direct Repo access
- Honest card data only, no fake workload metrics

### Constraints

- Do not absorb Department detail ownership from Task 08
- Remove dependency on fake fields like tasks_queue and description

## Execution Instructions

### For the Agent

1. Replace the current mock child adapter with persisted Department read data.
2. Keep this task limited to Cities surface ownership.
3. Leave Department detail concerns for Task 08.
4. Document any selector/navigation contract that Task 07 or Task 08 must rely on.

### For the Human Reviewer

1. Check that Cities is now a city-selector plus department-card surface.
2. Confirm there is no inline Department CRUD.
3. Verify task ownership did not spill into Department detail UX.

---

## Execution Summary

*[Filled by executing agent after completion]*

### Work Performed

- Replaced the selected-city mock child surface with persisted Department cards loaded through `CitiesPageSnapshot`.
- Removed the Cities page dependency on `mock_children` for department rendering and dropped the active lemmings preview panel from this surface.
- Added stable navigation contracts from Cities to the Departments list and Department detail routes.

### Outputs Created

- persisted department summaries in `CitiesPageSnapshot`
- compact department cards on the Cities page
- focused snapshot and LiveView coverage for the new Cities surface

### Assumptions Made

| Assumption | Rationale |
|------------|-----------|
| Department cards can navigate through the existing `/departments?city=...&dept=...` route shape | Task 06 only needs to surface truthful links and should not absorb Department detail ownership from later tasks |

### Decisions Made

| Decision | Alternatives Considered | Rationale |
|----------|------------------------|-----------|
| Keep Department rendering inside `WorldComponents` for now | Creating a new Cities-specific component module | The existing Cities page already imports `WorldComponents`, so this keeps the refactor narrow |
| Show only name, status, tags, and truncated notes | Reusing mock queue metrics or adding lemming previews | The task explicitly requires compact truthful cards and forbids fake workload metrics |

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
