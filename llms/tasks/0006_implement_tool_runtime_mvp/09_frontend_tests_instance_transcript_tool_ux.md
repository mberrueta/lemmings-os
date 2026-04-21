# Task 09: Frontend Tests Instance Transcript Tool UX

## Status
- **Status**: COMPLETED
- **Approved**: [X] Human sign-off

## Assigned Agent
`qa-elixir-test-author`

## Agent Invocation
Act as `qa-elixir-test-author` following `llms/constitution.md` and implement LiveView tests for the transcript tool-card UX.

## Objective
Add frontend test coverage for the instance transcript tool-card behavior introduced in Task 07.

## Inputs Required

- [ ] `llms/tasks/0006_implement_tool_runtime_mvp/plan.md`
- [ ] Task 07 outputs
- [ ] Existing `instance_live` LiveView tests

## Expected Outputs

- [ ] LiveView coverage for transcript tool cards
- [ ] LiveView coverage for reload/history behavior
- [ ] LiveView coverage for live lifecycle updates

## Acceptance Criteria

- [ ] Tests verify tool cards render in the transcript
- [ ] Tests verify compact lifecycle state and summary rendering
- [ ] Tests verify historical persisted records render after reload
- [ ] Tests verify persisted execution details can be inspected after reload
- [ ] Tests verify live started/completed/failed updates

## Technical Notes

### Constraints
- Use selector-driven assertions
- Keep tests deterministic

## Execution Instructions

### For the Agent
1. Extend `instance_live` coverage for tool-card behavior.
2. Cover reload/history and live updates.
3. Keep tests aligned with existing LiveView test patterns.

### For the Human Reviewer
1. Verify transcript tool-card coverage is complete.
2. Verify reload and live-update behavior is tested.
3. Verify tests are selector-driven and deterministic.

---

## Execution Summary
### Work Performed
- Extended `InstanceLive` LiveView coverage for transcript tool-card UX with explicit failed-lifecycle cases.
- Added a live update test for `running -> error` tool execution card transitions via PubSub without remount.
- Added a reload/remount test to verify persisted failed tool execution details remain inspectable.

### Scenario Coverage
- `S08b` (existing): historical transcript renders tool cards in chronological order.
- `S08c` (existing): live `running -> ok` updates render without remount.
- `S08e` (new): live `running -> error` updates render without remount.
- `S08f` (new): persisted failed execution details render after page reload.

### Files Modified
- `test/lemmings_os_web/live/instance_live_test.exs`

### Validation
- `mix test test/lemmings_os_web/live/instance_live_test.exs`
- `mix precommit`

### Acceptance Criteria Check
- [x] Tests verify tool cards render in the transcript
- [x] Tests verify compact lifecycle state and summary rendering
- [x] Tests verify historical persisted records render after reload
- [x] Tests verify persisted execution details can be inspected after reload
- [x] Tests verify live started/completed/failed updates

## Human Review
*[Filled by human reviewer]*
