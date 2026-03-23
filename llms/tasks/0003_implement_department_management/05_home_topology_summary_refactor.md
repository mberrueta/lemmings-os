# Task 05: Home Topology Summary Refactor

## Status

- **Status**: ✅ COMPLETE
- **Approved**: [x] Human sign-off
- **Blocked by**: None
- **Blocks**: Task 09
- **Estimated Effort**: S

## Assigned Agent

dev-frontend-ui-engineer - frontend engineer for LiveView read models, truthful UI states, and layout cleanup.

## Agent Invocation

Act as dev-frontend-ui-engineer following llms/constitution.md and refactor Home so topology summary uses real persisted Department data without reintroducing dashboard clutter.

## Objective

Add a truthful topology summary to Home while preserving the simplified overview direction established in prior World/City work.

## Inputs Required

- [ ] llms/tasks/0003_implement_department_management/plan.md
- [ ] Task 03 output
- [ ] lib/lemmings_os_web/live/home_live.ex
- [ ] lib/lemmings_os_web/live/home_live.html.heex
- [ ] lib/lemmings_os_web/page_data/home_dashboard_snapshot.ex

## Expected Outputs

- [ ] snapshot changes for real topology counts
- [ ] Home UI update reflecting those counts
- [ ] removal or avoidance of any fake Department-centric clutter

## Acceptance Criteria

- [ ] Home remains high-level and not Department-centric
- [ ] topology summary uses persisted counts, including departments and active departments if available
- [ ] no fake recent activity, queue, or lemming metrics are introduced

## Technical Notes

### Relevant Code Locations

```
lib/lemmings_os_web/page_data/home_dashboard_snapshot.ex
lib/lemmings_os_web/live/home_live.html.heex
```

### Patterns to Follow

- Prefer snapshot enrichment over HEEx-level counting logic

### Constraints

- Do not broaden Home into an operational Department index

## Execution Instructions

### For the Agent

1. Read the current Home snapshot and template.
2. Add only the minimum truthful Department topology signals.
3. Keep UI changes narrow and consistent with the current simplified Home direction.

### For the Human Reviewer

1. Confirm Home is still overview-only.
2. Reject if any mocked operational clutter returns.

---

## Execution Summary

*[Filled by executing agent after completion]*

### Work Performed

- Replaced the old city-only Home signal with a single snapshot-driven topology summary backed by persisted Cities and Departments.
- Removed the omitted-sections panel so Home no longer advertises deferred or fake operational breadth.
- Added stable stat IDs and refreshed Home tests to assert real topology counts in both the snapshot and the rendered LiveView.

### Outputs Created

- `topology_summary` card in `HomeDashboardSnapshot`
- simplified Home support grid without the omitted panel
- focused test coverage for persisted city and department counts

### Assumptions Made

| Assumption | Rationale |
|------------|-----------|
| Counting Departments by traversing persisted Cities is acceptable for Home | Home remains a small overview read model and there is no existing world-level Department aggregate API yet |

### Decisions Made

| Decision | Alternatives Considered | Rationale |
|----------|------------------------|-----------|
| Replace `city_health` with a single `topology_summary` card | Adding separate Department cards or broadening Home into a Department dashboard | A single card keeps Home high-level while surfacing the new hierarchy truthfully |
| Remove the omitted sections panel entirely | Keeping the panel or replacing it with new placeholders | The panel conflicted with the simplified and truthful Home direction |

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
