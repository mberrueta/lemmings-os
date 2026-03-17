# Task 07: World Page Desmoke

## Status

- **Status**: COMPLETE
- **Approved**: [X]
- **Blocked by**: Task 06
- **Blocks**: Task 08

## Assigned Agent

`dev-frontend-ui-engineer` - Frontend engineer for Phoenix LiveView.

## Agent Invocation

Use `dev-frontend-ui-engineer` to replace the mocked World page with the real persisted-domain-backed view.

## Objective

Wire `WorldLive` and `WorldComponents` to the real world snapshot and remove the current mock-driven world overview.

## Inputs Required

- [ ] `llms/tasks/0001_implement_world_management/plan.md`
- [ ] `llms/tasks/0001_implement_world_management/06_world_snapshot_and_runtime_checks.md`
- [ ] Task 06 implementation output
- [ ] `lib/lemmings_os_web/live/world_live.ex`
- [ ] `lib/lemmings_os_web/components/world_components.ex`

## Expected Outputs

- [ ] `WorldLive` backed by persisted-world read models
- [ ] read-only refresh/import actions
- [ ] UI for identity, bootstrap config, import state, runtime checks, warnings, and placeholder sections
- [ ] LiveView tests for main success and failure states

## Acceptance Criteria

- [ ] The page makes the domain/bootstrap/runtime split obvious
- [ ] The page no longer relies on `MockData`
- [ ] `cities` and `tools` remain visible without implying completeness

## Technical Notes

### Constraints

- No YAML editing
- No world CRUD screen
- Keep the existing shell and visual system

## Execution Instructions

### For the Agent

1. Remove `MockData` from the World page flow.
2. Preserve the visual shell.
3. Render normalized issues and statuses directly.

### For the Human Reviewer

1. Confirm the page now feels domain-real and operator-trustworthy.
2. Confirm placeholder sections are honest.
3. Approve before Task 08 begins.
