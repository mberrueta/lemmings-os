# Task 07: Frontend Transcript Tool Cards

## Status
- **Status**: COMPLETED
- **Approved**: [X] Human sign-off

## Assigned Agent
`dev-frontend-ui-engineer`

## Agent Invocation
Act as `dev-frontend-ui-engineer` following `llms/constitution.md` and implement the transcript tool-card UX for Tool Runtime MVP.

## Objective
Add compact tool execution cards to the instance session transcript, including historical rendering after reload and live lifecycle updates.

## Inputs Required

- [ ] `llms/tasks/0006_implement_tool_runtime_mvp/plan.md`
- [ ] Tasks 01 through 04 outputs
- [ ] `lib/lemmings_os_web/live/instance_live.ex`
- [ ] Existing transcript component patterns

## Expected Outputs

- [ ] Compact tool cards in the instance transcript
- [ ] Historical tool execution rendering after reload
- [ ] Live transcript updates for tool lifecycle changes

## Acceptance Criteria

- [ ] Tool cards render inline in the existing transcript
- [ ] Cards remain compact and avoid full raw output by default
- [ ] Cards show tool name, lifecycle state, and summary
- [ ] Historical persisted tool executions render in chronological order
- [ ] Cards support inspection of persisted execution details after reload
- [ ] Live updates reflect runtime lifecycle changes without reload

## Technical Notes

### Constraints
- Keep the instance session page as the primary operator surface
- Do not create a separate tool console for this PR

## Execution Instructions

### For the Agent
1. Extend the instance transcript rendering for tool events.
2. Keep the UI compact and aligned with current session patterns.
3. Support both reload-based and live-update-based visibility.

### For the Human Reviewer
1. Verify the transcript UX stays compact.
2. Verify reload/history behavior works.
3. Verify live lifecycle updates appear correctly.

---

## Execution Summary
Implemented compact transcript tool cards on the instance session page.

### Work Completed
- Interleaved persisted `ToolExecution` records with transcript messages in chronological order, including historical reload rendering and day dividers.
- Added live transcript refresh support for `:tool_execution_upserted` PubSub events.
- Added compact tool execution cards with tool name, lifecycle state, summary, preview, duration, and collapsed persisted detail inspection.
- Added LiveView tests covering historical reload ordering and live lifecycle updates for tool cards.

### Verification
- `mix test test/lemmings_os_web/live/instance_live_test.exs`
- `mix precommit`

## Human Review
*[Filled by human reviewer]*
