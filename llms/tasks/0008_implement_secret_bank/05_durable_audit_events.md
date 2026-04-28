# Task 05: Generic Durable Events

## Status
- **Status**: PENDING
- **Approved**: [ ] Human sign-off

## Assigned Agent
`dev-logging-daily-guardian`

## Agent Invocation
Act as `dev-logging-daily-guardian`. Implement/normalize generic durable event recording, then use it for Secret Bank admin and runtime operations.

## Objective
Ensure the app has a simple reusable durable event API and every required Secret Bank operation emits safe events through it. The API must be generic enough for future API calls, tool invocations, approvals, and model requests without over-modeling event metadata.

## Expected Outputs
- Generic event recording helper/context under `lib/lemmings_os/**`.
- Secret Bank integration that records required secret events through the generic helper.
- Recent activity query API filtered by hierarchy scope and event type.
- Notes reconciling event names with ADR-0018.

## Acceptance Criteria
- Event API accepts the minimal generic envelope from Task 01: event type, hierarchy scope, occurred timestamp, safe message, and optional safe payload.
- Event API is not Secret Bank-specific and can record future events such as `api.requested`, `api.succeeded`, `api.failed`, or `tool.invocation_started` without schema changes.
- `secret.created`, `secret.replaced`, `secret.deleted`, `secret.accessed`, and `secret.access_failed` are recorded durably.
- Events include a safe message such as `github.token created` or `github.token used in tools.gh`; optional payload may include safe fields like secret reference, normalized key, resolved source, tool name, and reason.
- Event metadata never includes raw values, old values, new values, previews, hashes, or provider token material.
- Recent activity can be filtered for World, City, Department, and Lemming Secret surfaces.
- Logging and telemetry metadata use hierarchy IDs where applicable and avoid sensitive payloads.

## Review Notes
Reject if event data is in-memory only, Secret Bank-specific, or duplicates secret value material in any form.
