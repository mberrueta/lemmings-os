# Task 05: Home Topology Summary Refactor

## Status

- **Status**: 🔒 BLOCKED
- **Approved**: [ ] Human sign-off
- **Blocked by**: Task 03
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
