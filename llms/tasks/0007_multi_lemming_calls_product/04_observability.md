# Task 04: Observability

## Status
- **Status**: COMPLETE
- **Approved**: [X] Human sign-off

## Assigned Agent
`dev-logging-daily-guardian`

## Agent Invocation
Act as `dev-logging-daily-guardian` following `llms/constitution.md` and review/add structured observability for multi-lemming calls.

## Objective
Make delegated work operationally understandable through logs, telemetry, PubSub, and activity log records.

## Inputs Required
- [ ] Task 01 outputs
- [ ] Task 02 outputs
- [ ] Existing telemetry, PubSub, and activity log patterns

## Expected Outputs
- [ ] Structured logs for call creation, start, status change, completion, failure, recovery pending, recovered, and dead.
- [ ] Telemetry events for call lifecycle and duration.
- [ ] PubSub helpers for call upserts/status changes so UI can update without polling where existing patterns support it.
- [ ] Activity log entries for major collaboration events.
- [ ] Runtime dashboard metrics include basic collaboration counts if consistent with current telemetry design.

## Required Metadata
Every log/telemetry event must include:
- `world_id`
- `city_id`
- `department_id` or both caller/callee department ids
- `caller_instance_id`
- `callee_instance_id` when known
- `lemming_call_id`

## Acceptance Criteria
- [ ] No agent payloads or sensitive request/result bodies are logged.
- [ ] Summaries may be logged only when already product-visible and truncated.
- [ ] Telemetry metadata preserves hierarchy context.
- [ ] Observability does not change runtime behavior.

## Execution Instructions
1. Add observability around backend call lifecycle.
2. Reuse existing telemetry/PubSub style.
3. Keep dashboards minimal and avoid broad redesign.

## Human Review
Verify event names and metadata before backend tests lock behavior.
