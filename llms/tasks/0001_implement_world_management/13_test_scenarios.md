# Task 13: Test Scenarios and Coverage Plan

## Status

- **Status**: 🔒 BLOCKED
- **Approved**: [ ]
- **Blocked by**: Task 12
- **Blocks**: Task 14

## Assigned Agent

`qa-test-scenarios` - Test scenario designer.

## Agent Invocation

Use `qa-test-scenarios` to define the coverage matrix for the persisted-World + bootstrap + read-only UI slice.

## Objective

Produce the scenario-level test plan before final test implementation.

## Inputs Required

- [ ] `llms/tasks/0001_implement_world_management/plan.md`
- [ ] Tasks 01 through 11 outputs
- [ ] `test/lemmings_os_web/live/navigation_live_test.exs`
- [ ] `test/support/conn_case.ex`
- [ ] `test/support/data_case.ex`

## Expected Outputs

- [ ] scenario matrix for migration/schema/context, bootstrap ingestion, snapshots, and desmoked pages
- [ ] coverage priorities for success, degraded, unavailable, invalid, and unknown states
- [ ] guidance on test file layout

## Acceptance Criteria

- [ ] all frozen statuses are covered
- [ ] all major read-only interactions are covered
- [ ] tests favor selectors and outcomes over brittle text assertions

## Technical Notes

### Constraints

- No implementation code
- Keep scenarios aligned with repo test patterns

## Execution Instructions

### For the Agent

1. Review implemented outputs from prior tasks.
2. Identify the minimum complete test set.
3. Flag any missing selectors or IDs needed for stability.

### For the Human Reviewer

1. Confirm the proposed coverage is sufficient.
2. Approve before Task 14 begins.
