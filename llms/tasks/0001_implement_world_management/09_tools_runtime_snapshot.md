# Task 09: Tools Runtime Snapshot

## Status

- **Status**: COMPLETE
- **Approved**: [X]
- **Blocked by**: Task 08
- **Blocks**: Task 10

## Assigned Agent

`dev-backend-elixir-engineer` - Senior backend engineer for Elixir/Phoenix.

## Agent Invocation

Use `dev-backend-elixir-engineer` to define the Tools read model for this issue.

## Objective

Create a runtime-first tools snapshot that can later reconcile with hierarchical policy, without claiming that the bootstrap config is already the final policy engine.

## Inputs Required

- [ ] `llms/tasks/0001_implement_world_management/plan.md`
- [ ] `docs/adr/0012-tool-policy-authorization-model.md`
- [ ] `lib/lemmings_os_web/live/tools_live.ex`

## Expected Outputs

- [ ] `ToolsPageSnapshot` or equivalent
- [ ] runtime capability status mapping
- [ ] explicit partial/deferred policy handling
- [ ] tests for empty, known, unavailable, and partial states

## Acceptance Criteria

- [ ] runtime capability state is primary
- [ ] policy reconciliation remains partial/deferred
- [ ] usage counts remain optional and non-fabricated

## Technical Notes

### Constraints

- Do not imply full ADR-0012 / ADR-0020 policy engine completion
- Keep the page useful even with partial backend sources

## Execution Instructions

### For the Agent

1. Prefer runtime facts over inferred policy.
2. Map page health back to the frozen taxonomy.
3. Use `unknown` / `unavailable` when data is missing.

### For the Human Reviewer

1. Confirm the snapshot does not overclaim policy completeness.
2. Approve before Task 10 begins.
