# Task 12: Home Page Desmoke

## Status

- **Status**: 🔒 BLOCKED
- **Approved**: [ ]
- **Blocked by**: Task 11
- **Blocks**: Task 13

## Assigned Agent

`dev-frontend-ui-engineer` - Frontend engineer for Phoenix LiveView.

## Agent Invocation

Use `dev-frontend-ui-engineer` to replace the mocked Home dashboard with the real snapshot.

## Objective

Wire `HomeLive` and `HomeComponents` to the new dashboard snapshot and remove fake operational cards.

## Inputs Required

- [ ] `llms/tasks/0001_implement_world_management/plan.md`
- [ ] `llms/tasks/0001_implement_world_management/11_home_dashboard_snapshot.md`
- [ ] Task 11 implementation output
- [ ] `lib/lemmings_os_web/live/home_live.ex`
- [ ] `lib/lemmings_os_web/components/home_components.ex`

## Expected Outputs

- [ ] `HomeLive` no longer depends on mocked dashboard assignments
- [ ] Home UI renders fewer, more trustworthy cards when sources are limited
- [ ] updated LiveView tests

## Acceptance Criteria

- [ ] Home no longer implies unsupported precision
- [ ] unavailable/degraded states are visually clear
- [ ] navigation remains intact

## Technical Notes

### Constraints

- Navigation only
- No invented counts or fake recent activity

## Execution Instructions

### For the Agent

1. Replace mocked dashboard content with snapshot-driven content.
2. Prefer pruning cards over simulating data.
3. Keep the page useful as an overview.

### For the Human Reviewer

1. Confirm the page remains useful but no longer overclaims.
2. Approve before Task 13 begins.
