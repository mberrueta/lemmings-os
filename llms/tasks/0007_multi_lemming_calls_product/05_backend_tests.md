# Task 05: Backend Tests

## Status
- **Status**: PENDING
- **Approved**: [ ] Human sign-off

## Assigned Agent
`qa-elixir-test-author`

## Agent Invocation
Act as `qa-elixir-test-author` following `llms/constitution.md`, `llms/coding_styles/elixir_tests.md`, and test the backend behavior from Tasks 01-04.

## Objective
Add deterministic ExUnit coverage for persistence, boundaries, runtime orchestration, seeds, and observability.

## Inputs Required
- [ ] Tasks 01-04 outputs
- [ ] Existing `test/lemmings_os/**` patterns
- [ ] `test/support/factory.ex`

## Expected Outputs
- [ ] Context tests for `LemmingCalls`.
- [ ] Runtime/executor tests for `:lemming_call`.
- [ ] Boundary tests for manager-only and same-World/same-City enforcement.
- [ ] Bootstrap tests for seeded company setup.
- [ ] Observability tests for telemetry/log-safe behavior where practical.

## Required Scenarios
- Manager calls same-department worker.
- Manager calls other department manager in same city.
- Worker direct delegation is rejected.
- Cross-World and cross-City calls are rejected.
- Direct child user input updates parent call record.
- Partial result remains visible when another child fails or stays pending.
- Expired child continuation creates linked successor call.
- Restart recovery can mark call `recovery_pending` or `dead`.

## Acceptance Criteria
- [ ] Tests use factories by default.
- [ ] OTP/process tests use `start_supervised/1`.
- [ ] Tests are deterministic and DB-sandbox safe.
- [ ] No raw HTML assertions in backend tests.
- [ ] `mix test` passes before moving to UI work.

## Execution Instructions
1. Add focused backend tests for each acceptance scenario.
2. Prefer small unit/context tests plus a few integration tests over one huge flow test.
3. Do not implement UI tests in this task.

## Human Review
Review coverage before UI work begins.
