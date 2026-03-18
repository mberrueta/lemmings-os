# Task 15: Demo Runbook and Operator Docs

## Status

- **Status**: 🔒 BLOCKED
- **Approved**: [ ]
- **Blocked by**: Task 14
- **Blocks**: Task 16

## Assigned Agent

`docs-feature-documentation-author` - Feature documentation writer.

## Agent Invocation

Use `docs-feature-documentation-author` to write the operator-facing runbook for the multi-city compose demo and City lifecycle behavior.

## Objective

Document how to run the demo, how `node_name` and startup attachment work, and how an operator should interpret city liveness and stale transitions in the UI.

## Inputs Required

- [ ] `llms/tasks/0002_implement_city_management/plan.md`
- [ ] Tasks 10 and 14 outputs
- [ ] compose artifacts and runtime env contract
- [ ] updated ADR/doc wording

## Expected Outputs

- [ ] runbook or README updates for the compose demo
- [ ] explanation of required env vars
- [ ] explanation of first world/first city startup behavior
- [ ] explanation of expected stale-city behavior when a node stops

## Acceptance Criteria

- [ ] the docs explain `node_name` as full BEAM identity in `name@host` form
- [ ] the docs explain that city rows may be bootstrap-created or operator-created
- [ ] the docs explain that runtime nodes upsert presence/identity against persisted rows on startup
- [ ] the docs explain the stale transition clearly and honestly
- [ ] the docs do not imply remote observation or city-to-city coordination in the demo

## Technical Notes

### Constraints

- Keep the runbook concise and practical
- Do not imply clustering or secure remote onboarding beyond the current scope
- Keep env var documentation explicit

## Execution Instructions

### For the Agent

1. Write docs for the actual operator flow, not the ideal future architecture.
2. Explain the demo in terms a maintainer can run locally.
3. Keep security-sensitive sections explicit about what is deferred.
4. Record any missing operator guidance that should be added later.

### For the Human Reviewer

1. Confirm the runbook is enough to reproduce the demo.
2. Confirm it does not overstate the branch’s runtime capabilities.
3. Confirm the startup and stale-city behavior are clear.
4. Approve before Task 16 begins.
