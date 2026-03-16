# Task 08: Settings Read-Only Runtime Page

## Status

- **Status**: 🔒 BLOCKED
- **Approved**: [ ]
- **Blocked by**: Task 07
- **Blocks**: Task 09

## Assigned Agent

`dev-frontend-ui-engineer` - Frontend engineer for Phoenix LiveView.

## Agent Invocation

Use `dev-frontend-ui-engineer` to convert Settings into a read-only runtime/instance page.

## Objective

Replace the mock settings form with operator-facing runtime information tied to the new World domain/bootstrap flow.

## Inputs Required

- [ ] `llms/tasks/0001_implement_world_management/plan.md`
- [ ] `llms/tasks/0001_implement_world_management/06_world_snapshot_and_runtime_checks.md`
- [ ] `lib/lemmings_os_web/live/settings_live.ex`
- [ ] `lib/lemmings_os_web/components/system_components.ex`

## Expected Outputs

- [ ] Settings page shows version, node/host, current bootstrap path, last import/reload status, validation summary, and help links
- [ ] mock save/validate form removed
- [ ] updated LiveView tests

## Acceptance Criteria

- [ ] Settings is informational only
- [ ] governance editing is not duplicated here
- [ ] unavailable runtime fields are shown honestly

## Technical Notes

### Constraints

- No forms for persistence
- No bootstrap/domain mutation from Settings

## Execution Instructions

### For the Agent

1. Remove mock form flows cleanly.
2. Reuse shared status semantics where applicable.
3. Keep the page minimal.

### For the Human Reviewer

1. Confirm Settings is read-only and useful.
2. Confirm no hidden governance duplication remains.
3. Approve before Task 09 begins.
