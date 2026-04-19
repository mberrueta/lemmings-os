# Task 06: Backend Tests Executor And Observability

## Status
- **Status**: ✅ COMPLETED
- **Approved**: [X] Human sign-off

## Assigned Agent
`qa-elixir-test-author`

## Agent Invocation
Act as `qa-elixir-test-author` following `llms/constitution.md` and implement backend tests for the executor tool loop and observability behavior.

## Objective
Add deterministic backend tests for the runtime tool-call loop and the observability work from Tasks 03 and 04.

## Inputs Required

- [x] `llms/tasks/0006_implement_tool_runtime_mvp/plan.md`
- [x] Task 03 outputs
- [x] Task 04 outputs
- [x] Existing executor/runtime telemetry test patterns

## Expected Outputs

- [x] ExUnit coverage for the minimum tool-call loop
- [x] ExUnit coverage for started/completed/failed lifecycle behavior
- [x] ExUnit coverage for telemetry and metrics contracts where appropriate

## Acceptance Criteria

- [x] Tests cover `tool_call` -> tool result -> continued runtime flow
- [x] Tests cover started/completed/failed lifecycle handling
- [x] Tests cover telemetry/logging expectations at the backend contract level where appropriate
- [x] Tests cover metric emission for count, success/error, and duration where appropriate
- [x] Tests remain deterministic and aligned with OTP/runtime testing conventions

## Technical Notes

### Constraints
- No separate verification task
- Keep coverage focused on the MVP loop and observability slice

## Execution Instructions

### For the Agent
1. Add runtime/executor tests for the MVP tool loop.
2. Add observability contract coverage.
3. Keep the tests deterministic and consistent with repo runtime tests.

### For the Human Reviewer
1. Verify the tool-call loop is covered.
2. Verify lifecycle observability is covered.
3. Verify tests remain deterministic.

---

## Execution Summary
Implemented deterministic backend coverage for the executor tool loop and observability slice from Tasks 03 and 04.

### Scenario-to-test mapping
- Minimum `tool_call` loop:
  - `test/lemmings_os/lemming_instances/executor_test.exs`
  - `S08` verifies `tool_call -> runtime execute -> persisted tool result -> continued reasoning -> final assistant reply`.
  - `S09` verifies `tool_call -> persisted tool error -> continued reasoning -> final assistant reply`.
  - `S11` adds unsupported-tool coverage (`exec.run`) and verifies the executor persists the normalized `tool.unsupported` failure while still finishing with a final reply.
- Started/completed/failed lifecycle handling:
  - `S08` asserts `started` and `completed` telemetry plus persisted `ok` execution state.
  - `S09` asserts `started` and `failed` telemetry plus persisted `error` execution state.
  - `S10` asserts structured lifecycle logging for success (`started` and `completed`).
  - `S11` asserts structured lifecycle logging for unsupported-tool failure (`started` and `failed`).
- Telemetry/logging expectations:
  - `test/lemmings_os/lemming_instances/executor_test.exs`
  - `S08`, `S09`, `S10`, and `S11` assert hierarchy metadata, `tool_name`, status, duration, and stable `reason` tokens where applicable.
  - `test/lemmings_os/lemming_instances/telemetry_test.exs` retains backend telemetry coverage for runtime-created, executor-started, scheduler, pool, and DETS events.
- Metric emission/contracts:
  - `test/lemmings_os_web/telemetry_test.exs`
  - `metrics/0 includes tool execution lifecycle metrics` verifies count/success-error/duration metric definitions.
  - `emit_runtime_snapshot/0 emits aggregate runtime instance measurements` verifies the telemetry poller-facing runtime snapshot emits aggregate measurements deterministically.

### Determinism notes
- Tool-loop tests use injected fake model runtimes and injected tool runtimes only.
- Observability tests use telemetry attachments, `capture_log/1`, and local DB state only.
- No real external requests or timing-sensitive sleeps were introduced.

### Validation run
- `mix format`
- `mix test test/lemmings_os/lemming_instances/executor_test.exs test/lemmings_os/lemming_instances/telemetry_test.exs test/lemmings_os_web/telemetry_test.exs`
- `mix precommit`

## Human Review
*[Filled by human reviewer]*
