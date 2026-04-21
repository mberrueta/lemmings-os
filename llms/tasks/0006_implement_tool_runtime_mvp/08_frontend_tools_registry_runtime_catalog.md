# Task 08: Frontend Tools Registry Runtime Catalog

## Status
- **Status**: COMPLETED
- **Approved**: [X] Human sign-off

## Assigned Agent
`dev-frontend-ui-engineer`

## Agent Invocation
Act as `dev-frontend-ui-engineer` following `llms/constitution.md` and wire the tools registry page to the real MVP runtime catalog.

## Objective
Replace the placeholder tools-page runtime data with the fixed four-tool Tool Runtime catalog delivered by the backend slice.

## Inputs Required

- [ ] `llms/tasks/0006_implement_tool_runtime_mvp/plan.md`
- [ ] Task 02 outputs
- [ ] `lib/lemmings_os_web/live/tools_live.ex`
- [ ] `lib/lemmings_os_web/page_data/tools_page_snapshot.ex`

## Expected Outputs

- [ ] Tools page wired to the real fixed runtime catalog
- [ ] UI reflects the same four-tool slice used by backend execution

## Acceptance Criteria

- [ ] Tools page renders the fixed four-tool catalog
- [ ] Tools page no longer depends on placeholder runtime fetch behavior for the happy path
- [ ] The page remains aligned with current tools-page UI patterns

## Technical Notes

### Constraints
- Keep this task limited to tools registry/runtime catalog wiring
- Do not add permissions or policy UI beyond current scope

## Execution Instructions

### For the Agent
1. Replace the placeholder runtime path with the real catalog path.
2. Keep the existing tools-page UX stable.
3. Limit the change to the approved four-tool slice.

### For the Human Reviewer
1. Verify the tools page reflects the real runtime catalog.
2. Verify only the four approved tools appear.
3. Verify no new out-of-scope policy UI is introduced.

---

## Execution Summary
### Work Performed
- Wired `ToolsLive` to the fixed runtime catalog path by using `LemmingsOs.Tools.DefaultRuntimeFetcher` directly for snapshot build.
- Kept policy fetch behavior unchanged to preserve current tools-page policy/degraded UX.
- Updated tools LiveView tests to validate the MVP happy path (fixed four-tool catalog) and filtering behavior against the real tool IDs.
- Updated partial-policy test to assert degraded state using one known policy status over the fixed catalog.

### Files Modified
- `lib/lemmings_os_web/live/tools_live.ex`
- `test/lemmings_os_web/live/tools_live_test.exs`

### Verification
- `mix test test/lemmings_os_web/live/tools_live_test.exs test/lemmings_os_web/page_data/tools_page_snapshot_test.exs test/lemmings_os/tools/catalog_test.exs`
- `mix precommit`

### Acceptance Criteria Check
- [x] Tools page renders the fixed four-tool catalog
- [x] Tools page no longer depends on placeholder runtime fetch behavior for the happy path
- [x] The page remains aligned with current tools-page UI patterns

## Human Review
*[Filled by human reviewer]*
