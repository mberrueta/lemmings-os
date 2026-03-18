# Task 12: Test Implementation

## Status

- **Status**: 🔒 BLOCKED
- **Approved**: [ ]
- **Blocked by**: Task 11
- **Blocks**: Task 13

## Assigned Agent

`qa-elixir-test-author` - QA-driven Elixir test writer.

## Agent Invocation

Use `qa-elixir-test-author` to implement the approved City coverage for this branch.

## Objective

Add the ExUnit and LiveView tests needed to lock down City persistence, startup integration, resolver behavior, heartbeat/liveness, and real UI behavior.

## Inputs Required

- [ ] `llms/tasks/0002_implement_city_management/plan.md`
- [ ] `llms/tasks/0002_implement_city_management/11_test_scenarios_and_coverage_plan.md`
- [ ] Tasks 01 through 10 outputs
- [ ] `llms/constitution.md`

## Expected Outputs

- [ ] schema/context tests
- [ ] resolver tests
- [ ] startup and heartbeat tests
- [ ] LiveView tests for city-related pages
- [ ] any supporting factory updates needed for City coverage

## Acceptance Criteria

- [ ] tests are deterministic and DB-sandbox safe
- [ ] tests use factories instead of fixture-style helpers
- [ ] OTP/process tests use `start_supervised/1`
- [ ] LiveView tests are selector-driven
- [ ] stale/live/unknown behavior is covered
- [ ] world scoping is covered

## Technical Notes

### Relevant Code Locations

- `test/lemmings_os/`
- `test/lemmings_os_web/live/`
- `test/support/factory.ex`
- `test/support/data_case.ex`
- `test/support/conn_case.ex`

### Constraints

- No debug prints committed
- No raw HTML assertions when selectors can be used
- Keep timing-sensitive tests stable

## Execution Instructions

### For the Agent

1. Implement the scenario matrix from Task 11.
2. Prefer focused test files and clear `describe` blocks.
3. Add the smallest testability hooks needed if the code requires them.
4. Record any areas that remain difficult to cover and why.

### For the Human Reviewer

1. Review coverage breadth and readability.
2. Confirm test helpers follow the repo conventions.
3. Confirm the branch now has real logic coverage for the highest-risk City paths.
4. Approve before Task 13 begins.

