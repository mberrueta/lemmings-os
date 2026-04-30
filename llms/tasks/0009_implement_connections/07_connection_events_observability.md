# Task 07: Connection Events and Observability

## Status
- **Status**: COMPLETED
- **Approved**: [X] Human sign-off

## Assigned Agent
`dev-logging-daily-guardian`

## Agent Invocation
Act as `dev-logging-daily-guardian`. Read `llms/constitution.md`, `llms/project_context.md`, `llms/tasks/0009_implement_connections/plan.md`, and Tasks 01-06, then review and normalize Connection event and logging behavior.

## Objective
Ensure Connection lifecycle, resolution, and test operations are observable through the existing durable event mechanism without leaking credentials.

## Expected Outputs
- Confirmed or adjusted event recording for:
  - `connection.created`
  - `connection.updated`
  - `connection.deleted`
  - `connection.enabled`
  - `connection.disabled`
  - `connection.marked_invalid`
  - `connection.resolve.started`
  - `connection.resolve.succeeded`
  - `connection.resolve.failed`
  - `connection.test.started`
  - `connection.test.succeeded`
  - `connection.test.failed`
- Safe event payload shape using hierarchy IDs, Connection ID, type, status, config key names (not values), and safe failure reason.
- Review of Logger and telemetry metadata added by earlier tasks.
- Execution notes listing any observability fixes made.

## Acceptance Criteria
- Event names match the product vocabulary.
- Events preserve World, City, and Department metadata where applicable.
- Event payloads do not include raw secrets, resolved credentials, API keys, passwords, bearer tokens, secret previews, hashes, or fingerprints.
- Failure events include safe, useful reasons.
- No new event infrastructure is introduced.
- No logs contain raw or derived secret values.

## Review Notes
Reject if observability stores credential material, adds a parallel event system, or logs full provider config payloads without sanitization.
