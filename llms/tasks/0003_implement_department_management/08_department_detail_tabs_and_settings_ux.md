# Task 08: Department Detail Tabs and Settings UX

## Status

- **Status**: COMPLETE
- **Approved**: [X] Human sign-off
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

- Implemented Department detail tabs for Overview, Lemmings, and Settings on the route-backed detail page.
- Added lifecycle action affordances for activate, drain, disable, and delete with operator-facing flash behavior.
- Built Settings V1 to show effective config, Department-local overrides, and a safe editable subset of local fields.
- Added acceptance-focused LiveView coverage for overview context, mock-backed lemmings messaging, lifecycle transitions, and settings distinction.

### Outputs Created

- `lib/lemmings_os_web/live/departments_live.ex`
- `lib/lemmings_os_web/live/departments_live.html.heex`
- `lib/lemmings_os_web/components/world_components.ex`
- `test/lemmings_os_web/live/departments_live_test.exs`

### Assumptions Made

| Assumption | Rationale |
|------------|-----------|
| Department detail should remain route-backed with patchable tab state | Keeps Task 08 aligned with Task 07's navigation ownership and preserves deep-linkable tabs |
| Lemmings preview may remain mock-backed for now if clearly disclosed | Task 08 explicitly allows honest mock-backed rendering instead of runtime orchestration |
| Settings V1 should edit only a bounded subset of Department-local overrides | The task asks for a foundation UX, not a full settings-system redesign |

### Decisions Made

| Decision | Alternatives Considered | Rationale |
|----------|------------------------|-----------|
| Reused `WorldComponents.department_detail_page/1` for the detail internals | Splitting into a new page-specific component tree | Kept the detail UX colocated with existing world/city/department presentation code |
| Displayed effective config and local overrides side by side | Per-field provenance tracing | Satisfies the requested distinction without overcommitting to a final settings model |
| Kept delete visible but honest about denied outcomes | Hiding delete until hard delete is supported | Preserves lifecycle scope while reflecting current backend safety constraints |

### Blockers Encountered

- Task metadata still listed this work as blocked, but the codebase already had the dependent Task 07 handoff and domain APIs in place when implemented.

### Questions for Human

1. Should the repeated Department detail button/card class clusters stay inline for now, or be promoted later into shared Tailwind utility classes as part of a broader UI cleanup?

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
