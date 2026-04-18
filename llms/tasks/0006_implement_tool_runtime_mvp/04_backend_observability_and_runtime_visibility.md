# Task 04: Backend Observability And Runtime Visibility

## Status
- **Status**: ⏳ PENDING
- **Approved**: [ ] Human sign-off

## Assigned Agent
`dev-logging-daily-guardian`

## Agent Invocation
Act as `dev-logging-daily-guardian` following `llms/constitution.md` and implement the observability slice for Tool Runtime MVP.

## Objective
Add logging, telemetry, metrics, and runtime/operator visibility for tool execution lifecycle transitions.

## Inputs Required

- [ ] `llms/tasks/0006_implement_tool_runtime_mvp/plan.md`
- [ ] Tasks 01 through 03 outputs
- [ ] `lib/lemmings_os/lemming_instances/telemetry.ex`
- [ ] `lib/lemmings_os/runtime/activity_log.ex`
- [ ] `lib/lemmings_os_web/telemetry.ex`

## Expected Outputs

- [ ] Structured logs for tool lifecycle transitions
- [ ] Telemetry events for started/completed/failed tool executions
- [ ] Metrics for volume, success/error rate, and durations
- [ ] Runtime-facing operator visibility aligned with existing patterns

## Acceptance Criteria

- [ ] Tool lifecycle transitions are logged
- [ ] Telemetry includes hierarchy metadata plus tool identity
- [ ] Metrics cover count, success/error, and duration
- [ ] Historical runtime visibility is available beyond live PubSub events

## Technical Notes

### Constraints
- Avoid logging sensitive payloads
- Reuse existing runtime observability patterns

## Execution Instructions

### For the Agent
1. Add lifecycle logs and telemetry for tool execution.
2. Extend runtime metrics/reporting surfaces as needed for this MVP.
3. Keep the observability contract aligned to current runtime conventions.

### For the Human Reviewer
1. Verify logs, telemetry, and metrics all exist.
2. Verify metadata includes runtime hierarchy context.
3. Verify observability covers failures as well as success cases.

---

## Execution Summary
*[Filled by executing agent after completion]*

## Human Review
*[Filled by human reviewer]*
