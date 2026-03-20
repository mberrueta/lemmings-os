# Task 08: Department Detail Tabs and Settings UX

## Status

- **Status**: 🔒 BLOCKED
- **Approved**: [ ] Human sign-off
- **Blocked by**: Task 03, Task 04, Task 07
- **Blocks**: Task 09
- **Estimated Effort**: L

## Assigned Agent

dev-frontend-ui-engineer - frontend engineer for operational page design, tabs, lifecycle actions, and bounded settings UX.

## Agent Invocation

Act as dev-frontend-ui-engineer following llms/constitution.md and implement Department detail tabs plus the initial Department settings foundation UX.

## Objective

Own the Department detail page internals after the index/navigation handoff is in place: Overview, Lemmings placeholder, Settings foundation, and lifecycle actions.

## Inputs Required

- [ ] llms/tasks/0003_implement_department_management/plan.md
- [ ] Task 03 output
- [ ] Task 04 output
- [ ] Task 07 output
- [ ] lib/lemmings_os_web/live/departments_live.ex
- [ ] lib/lemmings_os_web/live/departments_live.html.heex
- [ ] lib/lemmings_os_web/components/world_components.ex

## Expected Outputs

- [ ] Department detail Overview, Lemmings, and Settings tabs
- [ ] lifecycle action affordances for activate/drain/disable/delete
- [ ] settings UX that shows effective config plus Department-local overrides

## Acceptance Criteria

- [ ] Overview shows name, slug, status, parent city/world, tags, notes, and lifecycle actions
- [ ] Lemmings tab is either runtime-backed or explicitly mock-backed with honest messaging
- [ ] Settings distinguishes effective config from Department-local overrides, but does not require per-field source tracing
- [ ] editable controls may begin with a small safe subset and are clearly presented as V1
- [ ] this task does not redefine the index-scoping or city selector contracts already owned by Task 07

## Technical Notes

### Relevant Code Locations

```
lib/lemmings_os_web/live/departments_live.ex
lib/lemmings_os_web/live/departments_live.html.heex
lib/lemmings_os_web/components/world_components.ex
lib/lemmings_os/config/resolver.ex
```

### Patterns to Follow

- Tabbed operational page structure
- Read-model-driven config display rather than UI-side merge logic

### Constraints

- No final settings-system redesign
- No full Lemming runtime orchestration

## Execution Instructions

### For the Agent

1. Assume Task 07 already owns index selection and navigation.
2. Build detail internals only after that handoff.
3. Keep the Lemmings tab honest if it remains mock-backed.
4. Treat settings as an initial foundation, not a final editor.
5. Document any narrow UI contract needed for tests.

### For the Human Reviewer

1. Check that Task 08 starts where Task 07 ends.
2. Confirm tabs and lifecycle actions match the approved scope.
3. Reject if the settings UI overcommits to a final design.

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
