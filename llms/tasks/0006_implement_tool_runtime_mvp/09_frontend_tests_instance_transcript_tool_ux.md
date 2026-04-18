# Task 09: Frontend Tests Instance Transcript Tool UX

## Status
- **Status**: ⏳ PENDING
- **Approved**: [ ] Human sign-off

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
*[Filled by executing agent after completion]*

## Human Review
*[Filled by human reviewer]*
