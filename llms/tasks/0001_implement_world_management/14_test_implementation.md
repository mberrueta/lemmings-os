# Task 14: Test Implementation

## Status

- **Status**: 🔒 BLOCKED
- **Approved**: [ ]
- **Blocked by**: Task 13
- **Blocks**: Task 15

## Assigned Agent

`qa-elixir-test-author` - QA-driven Elixir test writer.

## Agent Invocation

Use `qa-elixir-test-author` to implement the approved coverage for this branch.

## Objective

Add the ExUnit and LiveView tests needed to lock down persisted `World` foundations, bootstrap ingestion, snapshots, and UI behavior.

## Inputs Required

- [ ] `llms/tasks/0001_implement_world_management/plan.md`
- [ ] `llms/tasks/0001_implement_world_management/13_test_scenarios.md`
- [ ] Tasks 01 through 11 outputs

## Expected Outputs

- [ ] schema/context tests
- [ ] bootstrap loader/import tests
- [ ] snapshot tests
- [ ] LiveView tests for `World`, `Settings`, `Tools`, and `Home`

## Acceptance Criteria

- [ ] tests are deterministic and selector-driven
- [ ] invalid/degraded/unavailable/unknown states are covered
- [ ] no fixture-style helpers are introduced

## Technical Notes

### Constraints

- Follow project testing conventions from the constitution
- Use existing `ConnCase` / `DataCase` patterns

## Execution Instructions

### For the Agent

1. Implement tests from the approved scenario matrix.
2. Prefer small dedicated files if coverage becomes large.
3. Record any missing testability hooks that had to be added.

### For the Human Reviewer

1. Review coverage breadth and readability.
2. Approve before Task 15 begins.
