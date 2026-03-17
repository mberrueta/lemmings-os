# Task 11: Home Dashboard Snapshot

## Status

- **Status**: 🔒 BLOCKED
- **Approved**: [ ]
- **Blocked by**: Task 10
- **Blocks**: Task 12

## Assigned Agent

`dev-backend-elixir-engineer` - Senior backend engineer for Elixir/Phoenix.

## Agent Invocation

Use `dev-backend-elixir-engineer` to build the Home dashboard read model.

## Objective

Create a dashboard snapshot that prioritizes trustworthy world/domain/bootstrap/runtime signals and avoids invented authority when hierarchy sources are missing.

## Inputs Required

- [ ] `llms/tasks/0001_implement_world_management/plan.md`
- [ ] Task 05 and Task 06 outputs
- [ ] `lib/lemmings_os_web/live/home_live.ex`

## Expected Outputs

- [ ] `HomeDashboardSnapshot` or equivalent
- [ ] fewer-card strategy when real data is sparse
- [ ] tests for degraded, unavailable, and partial states

## Acceptance Criteria

- [ ] no cards look authoritative without real sources
- [ ] dashboard emphasizes world identity, config health, and actionable alerts first
- [ ] missing hierarchy/runtime sources become honest unavailable or unknown states

## Technical Notes

### Constraints

- No hidden fallback to `MockData`
- Prefer fewer trustworthy cards over fuller fake dashboards

## Execution Instructions

### For the Agent

1. Build the snapshot around trustworthiness, not completeness.
2. Follow the frozen taxonomy.
3. Record any intentionally omitted cards.

### For the Human Reviewer

1. Confirm the dashboard is stricter and more honest.
2. Approve before Task 12 begins.
