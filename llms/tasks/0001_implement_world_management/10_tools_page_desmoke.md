# Task 10: Tools Page Desmoke

## Status

- **Status**: 🔒 BLOCKED
- **Approved**: [ ]
- **Blocked by**: Task 09
- **Blocks**: Task 11

## Assigned Agent

`dev-frontend-ui-engineer` - Frontend engineer for Phoenix LiveView.

## Agent Invocation

Use `dev-frontend-ui-engineer` to replace the mocked Tools page with the runtime snapshot.

## Objective

Make Tools a real capability/status page backed by runtime snapshot data.

## Inputs Required

- [ ] `llms/tasks/0001_implement_world_management/plan.md`
- [ ] `llms/tasks/0001_implement_world_management/09_tools_runtime_snapshot.md`
- [ ] Task 09 implementation output
- [ ] `lib/lemmings_os_web/live/tools_live.ex`
- [ ] `lib/lemmings_os_web/components/system_components.ex`

## Expected Outputs

- [ ] `ToolsLive` no longer uses `MockData.tools/0`
- [ ] UI renders runtime-first capability state and local filtering
- [ ] updated tests

## Acceptance Criteria

- [ ] the page is no longer a decorative registry
- [ ] unknown/unavailable states are explicit
- [ ] deferred policy reconciliation is visible, not hidden

## Technical Notes

### Constraints

- Preserve shell visuals
- No install/edit workflows

## Execution Instructions

### For the Agent

1. Wire the page to Task 09 outputs.
2. Keep filtering local and read-only.
3. Add stable selectors where needed for tests.

### For the Human Reviewer

1. Confirm runtime capability is clearly primary.
2. Confirm the page does not imply policy completeness.
3. Approve before Task 11 begins.
